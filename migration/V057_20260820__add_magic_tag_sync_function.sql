-- Keeps magic_tags derivable instead of hand-maintained.
--
-- V056 seeded magic_tags once, by joining magics to game_objects on the shared name and
-- copying that object's tags. A one-time seed only covers the magics that existed then, so
-- every later registration migration would have to remember to hand-write its own tag rows,
-- and the one that forgets produces a magic the bot silently never scores.
--
-- This function re-runs the same derivation. Registration migrations call it once at the
-- end; scripts/ci/validate-migrations.sh requires that call, so the omission fails on the
-- pull request rather than becoming invisible data.

CREATE OR REPLACE FUNCTION sync_magic_tags_from_game_objects()
    RETURNS INTEGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    inserted_count INTEGER;
BEGIN
    INSERT INTO magic_tags(magic_id, tag_id)
    SELECT magic.id, game_object_tag.tag_id
    FROM magics magic
             JOIN game_objects game_object ON game_object.name = magic.name
             JOIN game_object_tags game_object_tag ON game_object_tag.game_object_id = game_object.id
    WHERE NOT EXISTS (SELECT 1
                      FROM magic_tags existing
                      WHERE existing.magic_id = magic.id
                        AND existing.tag_id = game_object_tag.tag_id);

    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    RETURN inserted_count;
END
$$;

COMMENT ON FUNCTION sync_magic_tags_from_game_objects() IS
    'Derives magic_tags from game_object_tags through the shared magics/game_objects name space. '
        'Call at the end of any migration that registers a magic. Rows added by hand are left alone.';

-- Reports the current gap rather than failing. A magic that leaves nothing on the field
-- legitimately has no tags, so the count is information, not an error -- but it belongs in
-- the migration log, where a growing number is visible.
DO
$$
    DECLARE
        synced_count         INTEGER;
        untagged_magic_count INTEGER;
    BEGIN
        SELECT sync_magic_tags_from_game_objects() INTO synced_count;

        SELECT COUNT(*)
        INTO untagged_magic_count
        FROM magics magic
        WHERE NOT EXISTS (SELECT 1 FROM magic_tags mt WHERE mt.magic_id = magic.id);

        RAISE NOTICE 'sync_magic_tags_from_game_objects added % rows; % magics still have no tags',
            synced_count, untagged_magic_count;
    END
$$;
