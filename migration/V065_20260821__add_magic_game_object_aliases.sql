-- Teaches sync_magic_tags_from_game_objects() the magics whose name is not their object's.
--
-- V057 derives a magic's tags by joining magics.name to game_objects.name. That join is the
-- right idea -- a hand-written copy of an object's tags goes stale the first time the object
-- is re-categorised -- but it only reaches magics that were named after the object they
-- create. Twenty were not, and every one of them came back with no tags at all:
--
--   * swarm magics carry a _swarm suffix and spawn the singular object
--     (ember_spirit_swarm -> ember_spirit, and four more)
--   * two magics predate the ground_ prefix (cannon -> ground_cannon, tower -> ground_tower)
--   * vine_world creates giant_vine and has no game_objects row of its own
--   * lightning_/nature_ magics meet electric_/leaf_ objects
--   * a set of dead names left over from V003 that duplicate a live object
--
-- Nine of the twenty have a card recipe, so they are castable today and the bot has been
-- scoring every one of them at the neutral 0.0.
--
-- A lookup table rather than twenty hand-written magic_tags rows: the next swarm magic is
-- one row here and inherits its object's tags forever after, where hand-written rows would
-- have to be remembered again and would drift the moment the object is re-tagged.

CREATE TABLE IF NOT EXISTS magic_game_object_aliases
(
    magic_name       VARCHAR(255) PRIMARY KEY,
    game_object_name VARCHAR(255) NOT NULL,
    reason           TEXT         NOT NULL
);

COMMENT ON TABLE magic_game_object_aliases IS
    'Maps a magic to the game object it puts on the field when the two do not share a name. '
        'Read only by sync_magic_tags_from_game_objects(). Add a row instead of writing '
        'magic_tags by hand, so the magic keeps following the object it creates.';

INSERT INTO magic_game_object_aliases(magic_name, game_object_name, reason)
SELECT alias.magic_name, alias.game_object_name, alias.reason
FROM (VALUES
          -- Castable today: these have a magic_cards recipe.
          ('ember_spirit_swarm', 'ember_spirit', 'EmberSpiritSwarmMagic spawns PrefabType.EmberSpirit'),
          ('mini_rock_swarm', 'mini_rock', 'MiniRockSwarmMagic spawns PrefabType.MiniRock'),
          ('seed_spirit_swarm', 'seed_spirit', 'SeedSpiritSwarmMagic spawns PrefabType.SeedSpirit'),
          ('thunder_bird_swarm', 'thunder_bird', 'thunderBirdSwarmMagic spawns PrefabType.ThunderBird'),
          ('water_slime_swarm', 'water_slime', 'WaterSlimeSwarmMagic spawns PrefabType.WaterSlime'),
          ('cannon', 'ground_cannon', 'CannonMagic spawns PrefabType.GroundCannon'),
          ('tower', 'ground_tower', 'TowerMagic spawns PrefabType.GroundTower'),
          ('vine_world', 'giant_vine', 'VineWorldMagic spawns PrefabType.GiantVine; vine_world has no game_objects row'),
          ('lightning_explosion', 'electric_explode', 'LightningExplosionMagic spawns PrefabType.ElectricExplode'),

          -- Implemented on the game server but with no recipe, so unreachable until one is
          -- added. Listed now so adding the recipe is the only step left.
          ('fire_slime_nest', 'fire_summon', 'FireSlimeNestMagic spawns PrefabType.FireSummon'),
          ('lightning_shot', 'electric_shot', 'LightningShotMagic spawns PrefabType.ElectricShot'),
          ('wind_explosion', 'wind_explode', 'WindExplosionMagic spawns PrefabType.WindExplode'),

          -- Dead names from the V003 catalogue: no recipe and no magic bean on the game
          -- server. Kept rather than deleted because statistic_game_magics may reference
          -- them, and pointed at the live object that replaced each one so the coverage
          -- check below can be an equality rather than a list of exceptions.
          ('fire_explosion', 'fire_explode', 'superseded by the fire_explode object'),
          ('nature_explosion', 'leaf_explode', 'superseded by the leaf_explode object'),
          ('rock_explosion', 'rock_explode', 'superseded by the rock_explode object'),
          ('nature_shot', 'vine_toss', 'the nature shoot magic is vine_toss'),
          ('rock_shot', 'rock_rolling', 'the rock shoot magic is rock_rolling'),
          ('wind_slime_swarm', 'wind_slime', 'follows the other swarm magics'),
          ('water_slime_nest', 'pve_water_slime_nest', 'the only water slime nest that exists'),
          ('pve_vine', 'vine', 'the PVE vine spawn puts vine objects on the field')
     ) AS alias(magic_name, game_object_name, reason)
WHERE NOT EXISTS (SELECT 1
                  FROM magic_game_object_aliases existing
                  WHERE existing.magic_name = alias.magic_name);

-- Same derivation as V057, with the alias consulted first. An alias wins over an
-- equal-named game object on purpose: a magic gets an alias exactly when the same-named row
-- is not the object it creates.
CREATE OR REPLACE FUNCTION sync_magic_tags_from_game_objects()
    RETURNS INTEGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    inserted_count INTEGER;
BEGIN
    INSERT INTO magic_tags(magic_id, tag_id)
    SELECT resolved.magic_id, game_object_tag.tag_id
    FROM (SELECT magic.id                                     AS magic_id,
                 COALESCE(alias.game_object_name, magic.name) AS game_object_name
          FROM magics magic
                   LEFT JOIN magic_game_object_aliases alias ON alias.magic_name = magic.name) resolved
             JOIN game_objects game_object ON game_object.name = resolved.game_object_name
             JOIN game_object_tags game_object_tag ON game_object_tag.game_object_id = game_object.id
    WHERE NOT EXISTS (SELECT 1
                      FROM magic_tags existing
                      WHERE existing.magic_id = resolved.magic_id
                        AND existing.tag_id = game_object_tag.tag_id);

    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    RETURN inserted_count;
END
$$;

COMMENT ON FUNCTION sync_magic_tags_from_game_objects() IS
    'Derives magic_tags from game_object_tags, through the shared magics/game_objects name '
        'space or through magic_game_object_aliases when the names differ. Call at the end of '
        'any migration that registers a magic. Rows added by hand are left alone.';

DO
$$
    DECLARE
        unresolved_alias TEXT;
        synced_count     INTEGER;
        untagged_count   INTEGER;
        untagged_names   TEXT;
    BEGIN
        -- An alias pointing at a game object that does not exist would be silent again.
        SELECT alias.magic_name
        INTO unresolved_alias
        FROM magic_game_object_aliases alias
        WHERE NOT EXISTS (SELECT 1 FROM game_objects go WHERE go.name = alias.game_object_name)
           OR NOT EXISTS (SELECT 1 FROM magics m WHERE m.name = alias.magic_name)
        LIMIT 1;

        IF unresolved_alias IS NOT NULL THEN
            RAISE EXCEPTION 'alias % names a magic or game object that does not exist', unresolved_alias;
        END IF;

        SELECT sync_magic_tags_from_game_objects() INTO synced_count;

        SELECT COUNT(*), COALESCE(STRING_AGG(magic.name, ', ' ORDER BY magic.name), '')
        INTO untagged_count, untagged_names
        FROM magics magic
        WHERE NOT EXISTS (SELECT 1 FROM magic_tags mt WHERE mt.magic_id = magic.id);

        -- V056 could only report this number. With V063, V064 and the aliases above it is
        -- zero, so from here it is an assertion: any magic added later without tags fails
        -- the next migration that runs this check instead of disappearing from bot scoring.
        IF untagged_count > 0 THEN
            RAISE EXCEPTION 'still % magics with no tags: %', untagged_count, untagged_names;
        END IF;

        RAISE NOTICE 'alias sync added % rows; every magic now carries tags', synced_count;
    END
$$;
