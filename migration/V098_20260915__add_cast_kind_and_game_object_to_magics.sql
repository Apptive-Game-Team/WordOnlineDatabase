-- Says what each magic builds, so the game server stops needing a class per magic.
--
-- 74 magics can be cast today and 67 of them hold nothing but two facts: which family of magic they
-- are, and what they put on the field. Both live only in a Java class - AquaArcherMagic extends
-- AbstractSpawnMagic and passes PrefabType.AquaArcher - so adding a magic means writing a class and
-- deploying the server. These two columns carry those facts instead (issue #155,
-- Apptive-Game-Team/WordOnlineServer#564).
--
--   cast_kind        how the server builds it. A different axis from cast_type: cast_type is the
--                    cast card a recipe uses, and the two disagree where it matters - tornado_strike
--                    is cast_type 'spawn' and is built by AbstractExplosionMagic.
--   game_object_id   what it builds. That row carries the prefab name (V097), the stats its prefab
--                    initializer reads, and, for a Spawn, the quantity.
--
-- A reference rather than a prefab name spelled into magics, because one row then answers all three
-- questions and a foreign key keeps it honest. V096 had to repair eleven magic_id rows that named
-- the wrong magic precisely because nothing stopped them.
--
-- Both columns are nullable, and a null does not always mean "not filled in yet":
--
--   Code   the seven magics whose class does more than build one prefab. chicken_commando reads its
--          fall height from a parameter, spirit_bomb builds nothing and attaches a component to the
--          caster, tidal_warhead picks one of two prefabs by what it locks onto, vine_toss lays six
--          vines in a line, vine_world grows its vine after it lands, will_o_wisp hands its target
--          to a MindControlShot, and wind_explosion leaves what it built with no owner
--          (Master.None). They keep their bean, and carry cast_kind 'Code' with nothing to build.
--   null   water_slime_nest and pve_nature_slime_nest. Each has a bean under a different name
--          (pve_water_slime_nest, nature_slime_nest), so DatabaseMagicParser drops both and neither
--          is castable today. Filling these columns would make them castable, which is a balance
--          decision and not this file's. They stay empty and stay dead.
--
-- Deploy order. This migration goes out before the server change that deletes those 67 classes
-- (Apptive-Game-Team/WordOnlineServer#564), never after: a server that has dropped the classes and
-- finds no cast_kind registers no magics at all. The reverse direction is safe - today's server
-- ignores both columns.

ALTER TABLE magics
    ADD COLUMN IF NOT EXISTS cast_kind VARCHAR(15);

ALTER TABLE magics
    ADD COLUMN IF NOT EXISTS game_object_id BIGINT;

ALTER TABLE magics
    DROP CONSTRAINT IF EXISTS chk_magics_cast_kind;

ALTER TABLE magics
    ADD CONSTRAINT chk_magics_cast_kind
        CHECK (cast_kind IS NULL OR
               cast_kind IN ('Shot', 'Drop', 'Explosion', 'Summon', 'Spawn', 'Code'));

ALTER TABLE magics
    DROP CONSTRAINT IF EXISTS fk_magics_game_object;

-- RESTRICT rather than CASCADE: a game object a magic builds must not be deleted out from under it.
ALTER TABLE magics
    ADD CONSTRAINT fk_magics_game_object
        FOREIGN KEY (game_object_id) REFERENCES game_objects (id) ON DELETE RESTRICT;

WITH configured(magic_name, cast_kind, object_name) AS (VALUES
       ('aqua_archer', 'Spawn', 'aqua_archer'),
       ('bomb_sprite', 'Spawn', 'bomb_sprite'),
       ('boulder_strike', 'Shot', 'boulder_strike'),
       ('bubble_generator', 'Summon', 'bubble_generator'),
       ('bubble_spirit', 'Spawn', 'bubble_spirit'),
       ('cannon', 'Summon', 'ground_cannon'),
       ('chain_lightning', 'Shot', 'chain_lightning'),
       ('cloud_dragon', 'Spawn', 'cloud_dragon'),
       ('crater', 'Summon', 'crater'),
       ('dimension_toad', 'Spawn', 'dimension_toad'),
       ('dragon_tower', 'Summon', 'dragon_tower'),
       ('electric_tower', 'Summon', 'electric_tower'),
       ('ember_spirit_swarm', 'Spawn', 'ember_spirit'),
       ('evil_ent', 'Spawn', 'evil_ent'),
       ('fire_lord_spirit', 'Spawn', 'fire_lord_spirit'),
       ('fire_shot', 'Shot', 'fire_shot'),
       ('fire_slime_nest', 'Summon', 'fire_summon'),
       ('fire_spirit', 'Spawn', 'fire_spirit'),
       ('firework_tower', 'Summon', 'firework_tower'),
       ('frenzy_totem', 'Drop', 'frenzy_totem'),
       ('grass_generator', 'Summon', 'grass_generator'),
       ('healing_totem', 'Summon', 'healing_totem'),
       ('leafair', 'Drop', 'leaf_drop'),
       ('life_tree', 'Summon', 'life_tree'),
       ('lightning_drop', 'Drop', 'lightning_cloud'),
       ('lightning_explosion', 'Explosion', 'electric_explode'),
       ('lightning_shot', 'Shot', 'electric_shot'),
       ('magma_explosion', 'Explosion', 'magma_explosion'),
       ('magma_spirit', 'Spawn', 'magma_spirit'),
       ('mana_well', 'Summon', 'mana_well'),
       ('meteor_shower', 'Drop', 'meteor_shower'),
       ('mini_rock_swarm', 'Spawn', 'mini_rock'),
       ('overgrowth', 'Explosion', 'overgrowth'),
       ('rallying_totem', 'Summon', 'rallying_totem'),
       ('razor_gale', 'Explosion', 'razor_gale'),
       ('repair_totem', 'Summon', 'repair_totem'),
       ('rock_drop', 'Drop', 'rock_drop'),
       ('rock_golem', 'Spawn', 'rock_golem'),
       ('rock_mage', 'Spawn', 'rock_mage'),
       ('rock_rolling', 'Shot', 'rock_rolling'),
       ('rock_turret', 'Summon', 'rock_turret'),
       ('sand_storm', 'Explosion', 'sand_storm'),
       ('sea_serpent', 'Spawn', 'sea_serpent'),
       ('seed_nest', 'Summon', 'seed_nest'),
       ('seed_spirit_swarm', 'Spawn', 'seed_spirit'),
       ('shock_overload', 'Explosion', 'shock_overload'),
       ('shock_trap', 'Summon', 'shock_trap'),
       ('storm_rider', 'Spawn', 'storm_rider'),
       ('storm_stag', 'Spawn', 'storm_stag'),
       ('thunder_bird_swarm', 'Spawn', 'thunder_bird'),
       ('thunder_spirit', 'Spawn', 'thunder_spirit'),
       ('tide_call', 'Shot', 'tide_call'),
       ('titan_remnant', 'Summon', 'titan_remnant'),
       ('tornado_strike', 'Explosion', 'tornado_strike'),
       ('tower', 'Summon', 'ground_tower'),
       ('towerback', 'Summon', 'towerback'),
       ('tree_golem', 'Spawn', 'tree_golem'),
       ('vine_colony', 'Summon', 'vine_colony'),
       ('vine_spirit', 'Spawn', 'vine_spirit'),
       ('wall_golem', 'Spawn', 'wall_golem'),
       ('water_explosion', 'Explosion', 'water_explosion'),
       ('water_shot', 'Shot', 'water_shot'),
       ('water_slime_swarm', 'Spawn', 'water_slime'),
       ('wind_blade', 'Shot', 'wind_blade'),
       ('wind_spirit', 'Spawn', 'wind_spirit'),
       ('wind_totem', 'Summon', 'wind_totem'),
       ('zap_mouse', 'Spawn', 'zap_mouse')
)
UPDATE magics magic
SET cast_kind      = configured.cast_kind,
    game_object_id = game_object.id
FROM configured
         JOIN game_objects game_object ON game_object.name = configured.object_name
WHERE magic.name = configured.magic_name
  AND (magic.cast_kind IS DISTINCT FROM configured.cast_kind
    OR magic.game_object_id IS DISTINCT FROM game_object.id);

UPDATE magics
SET cast_kind      = 'Code',
    game_object_id = NULL
WHERE name IN ('chicken_commando', 'spirit_bomb', 'tidal_warhead', 'vine_toss', 'vine_world', 'will_o_wisp', 'wind_explosion')
  AND (cast_kind IS DISTINCT FROM 'Code' OR game_object_id IS NOT NULL);

DO
$$
    DECLARE
        nothing_to_build TEXT;
        prefabless       TEXT;
        built_count      INTEGER;
        code_count       INTEGER;
    BEGIN
        -- A cast_kind with no object is a magic the server would read as buildable and then fail to
        -- build. Only 'Code' is allowed to carry nothing.
        SELECT COALESCE(STRING_AGG(magic.name, ', ' ORDER BY magic.name), '')
        INTO nothing_to_build
        FROM magics magic
        WHERE magic.cast_kind IS NOT NULL
          AND magic.cast_kind <> 'Code'
          AND magic.game_object_id IS NULL;

        IF nothing_to_build <> '' THEN
            RAISE EXCEPTION 'these magics have a cast_kind but nothing to build: %', nothing_to_build;
        END IF;

        -- The object a magic builds has to know which prefab it is, or the server cannot turn the
        -- row into a PrefabType.
        SELECT COALESCE(STRING_AGG(magic.name || ' -> ' || game_object.name, ', ' ORDER BY magic.name), '')
        INTO prefabless
        FROM magics magic
                 JOIN game_objects game_object ON game_object.id = magic.game_object_id
        WHERE game_object.prefab IS NULL;

        IF prefabless <> '' THEN
            RAISE EXCEPTION 'these magics build an object with no prefab name: %', prefabless;
        END IF;

        SELECT COUNT(*) FILTER (WHERE cast_kind IS NOT NULL AND cast_kind <> 'Code'),
               COUNT(*) FILTER (WHERE cast_kind = 'Code')
        INTO built_count, code_count
        FROM magics;

        IF built_count <> 67 OR code_count <> 7 THEN
            RAISE EXCEPTION 'expected 67 data-driven magics and 7 Code magics, found % and %',
                built_count, code_count;
        END IF;

        RAISE NOTICE '% magics say what they build, % keep their class', built_count, code_count;
    END
$$;
