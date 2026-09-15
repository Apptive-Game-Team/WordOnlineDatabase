-- Removes the seven magics no server can cast, and the rows that only existed to describe them.
--
-- The game server builds its magic list by asking Spring for a bean named after each magics row
-- (DatabaseMagicParser). These seven have no bean under that name and never have had one, so the
-- parser logs a warning and drops them at every startup:
--
--   fire_explosion, nature_explosion, rock_explosion   superseded by the fire_explode, leaf_explode
--                                                      and rock_explode objects, per the alias table
--   nature_shot, rock_shot                             the nature and rock shoot magics that
--                                                      actually shipped are vine_toss and rock_rolling
--   wind_slime_swarm                                   no class was ever written
--   pve_vine                                           a PVE-only spawn that never reaches a hand
--
-- None of them is reachable by a player either: all seven have zero magic_cards rows, so no recipe
-- produces them. What they do have is 557 user_magics rows each - every account "owns" all seven -
-- plus counter tags and an aim indicator, which is work spent describing magics that cannot exist.
-- Issue #157 removes them rather than carrying them through the cast_kind work, where each would
-- need a decision it cannot earn.
--
-- What goes with them:
--
--   user_magics, magic_tags, magic_cards   deleted by the existing ON DELETE CASCADE.
--   statistic_game_magics                  deleted here. There is no foreign key on that table, so
--                                          without this the rows would outlive their magic and name
--                                          an id that resolves to nothing - the same dangling shape
--                                          V096 has just finished repairing. 443 rows across six of
--                                          the seven; pve_vine was never played. This is the one
--                                          irreversible loss in the file: those games happened, and
--                                          afterwards nothing records which magic those casts were.
--   magic_game_object_aliases              one row each, naming a magic that will not exist.
--   game_objects and parameter_values      each of the seven has a placeholder object holding
--                                          nothing but its own magic_id row, and no tags. Both go.
--
-- Deliberately not touched: the objects those aliases pointed at (fire_explode, leaf_explode,
-- rock_explode, vine_toss, rock_rolling, wind_slime, vine). Every one of them is live data used by
-- a magic that works.

-- ------------------------------------------------------------------ what must be true first
DO
$$
    DECLARE
        reachable TEXT;
    BEGIN
        -- A recipe would mean a player can hold one of these, which would make this a balance change
        -- rather than a cleanup. None exists today; fail rather than delete if that has changed.
        SELECT COALESCE(STRING_AGG(magic.name, ', ' ORDER BY magic.name), '')
        INTO reachable
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
        WHERE magic.name IN ('fire_explosion', 'nature_explosion', 'rock_explosion', 'nature_shot',
                             'rock_shot', 'wind_slime_swarm', 'pve_vine')
        GROUP BY magic.name;

        IF reachable <> '' THEN
            RAISE EXCEPTION 'these magics now have a recipe and are no longer unreachable: %', reachable;
        END IF;
    END
$$;

-- --------------------------------------------------------------------------- the deletions
DELETE
FROM statistic_game_magics statistic
    USING magics magic
WHERE statistic.magic_id = magic.id
  AND magic.name IN ('fire_explosion', 'nature_explosion', 'rock_explosion', 'nature_shot',
                     'rock_shot', 'wind_slime_swarm', 'pve_vine');

DELETE
FROM magic_game_object_aliases alias
WHERE alias.magic_name IN ('fire_explosion', 'nature_explosion', 'rock_explosion', 'nature_shot',
                           'rock_shot', 'wind_slime_swarm', 'pve_vine');

-- The placeholder objects, and the one parameter row each holds. parameter_values first: game_objects
-- is the parent of that foreign key.
DELETE
FROM parameter_values parameter_value
    USING game_objects game_object
WHERE parameter_value.game_object_id = game_object.id
  AND game_object.name IN ('fire_explosion', 'nature_explosion', 'rock_explosion', 'nature_shot',
                           'rock_shot', 'wind_slime_swarm', 'pve_vine')
  AND NOT EXISTS (SELECT 1 FROM magics magic WHERE magic.game_object_id = game_object.id);

DELETE
FROM game_objects game_object
WHERE game_object.name IN ('fire_explosion', 'nature_explosion', 'rock_explosion', 'nature_shot',
                           'rock_shot', 'wind_slime_swarm', 'pve_vine')
  AND NOT EXISTS (SELECT 1 FROM parameter_values parameter_value
                  WHERE parameter_value.game_object_id = game_object.id)
  AND NOT EXISTS (SELECT 1 FROM game_object_tags tag
                  WHERE tag.game_object_id = game_object.id)
  AND NOT EXISTS (SELECT 1 FROM magics magic WHERE magic.game_object_id = game_object.id);

DELETE
FROM magics magic
WHERE magic.name IN ('fire_explosion', 'nature_explosion', 'rock_explosion', 'nature_shot',
                     'rock_shot', 'wind_slime_swarm', 'pve_vine');

-- --------------------------------------------------------------------------- assertions
DO
$$
    DECLARE
        survivors     TEXT;
        dangling_stat INTEGER;
        magic_count   INTEGER;
    BEGIN
        SELECT COALESCE(STRING_AGG(magic.name, ', ' ORDER BY magic.name), '')
        INTO survivors
        FROM magics magic
        WHERE magic.name IN ('fire_explosion', 'nature_explosion', 'rock_explosion', 'nature_shot',
                             'rock_shot', 'wind_slime_swarm', 'pve_vine');

        IF survivors <> '' THEN
            RAISE EXCEPTION 'these magics are still here: %', survivors;
        END IF;

        -- statistic_game_magics carries no foreign key, so this is the only place the invariant is
        -- checked at all: every recorded cast still names a magic that exists.
        SELECT COUNT(*)
        INTO dangling_stat
        FROM statistic_game_magics statistic
        WHERE NOT EXISTS (SELECT 1 FROM magics magic WHERE magic.id = statistic.magic_id);

        IF dangling_stat > 0 THEN
            RAISE EXCEPTION '% statistic rows name a magic that does not exist', dangling_stat;
        END IF;

        SELECT COUNT(*) INTO magic_count FROM magics;
        -- Two of the survivors, water_slime_nest and pve_nature_slime_nest, still have no bean under
        -- their own name and no cast_kind. They stay because reviving them is a balance decision
        -- (V098), not because they work.
        RAISE NOTICE '% magics remain', magic_count;
    END
$$;
