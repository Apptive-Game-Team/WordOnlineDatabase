-- Registers dragon_tower and dragon_flame: dragon_tower is the Build + Shoot + Fire tower that
-- launches dragon_flame straight forward every attack_interval, whether or not an enemy stands in
-- front of it. It does not pick a target. dragon_flame is the projectile, a separate game object
-- exactly the way firework_tower and firework_shell are a pair in
-- V082_20260908__register_firework_tower.sql.
--
-- Recipe. {Build, Fire, Shoot}. DatabaseMagicParser keys magics on the SORTED MULTISET of card
-- names and its init() is a plain map.put, so a duplicate key silently shadows whichever magic was
-- parsed first with nothing logged. The nearest neighbours are cannon (Build + Rock + Shoot),
-- crater (Build + Fire + Rock) and fire_shot (Fire + Shoot). The assertion at the foot rechecks
-- uniqueness against the live database rather than trusting a reconstruction of it from these
-- files. The insert uses the generate_series form from V069 so that card counts stay expressible.
--
-- magics.cast_type has been NOT NULL with a CHECK since V047, so the magic row carries 'build'.
--
-- Two objects. The magic is dragon_tower and the projectile it fires is dragon_flame, so only
-- dragon_tower is reached by the name join in sync_magic_tags_from_game_objects(). dragon_flame is
-- not a magic, so it needs no magic_game_object_aliases row; it is tagged directly like any other
-- field object.
--
-- Behavior. dragon_tower no longer picks a target or breathes an instantaneous beam. Every
-- attack_interval it spawns one dragon_flame at itself and sends it straight forward: +X for
-- LeftPlayer and -X for RightPlayer, the same rule WindPushComponent already uses on the server.
-- dragon_flame explodes on the first enemy it touches, dealing its damage in a radius around the
-- impact point. If it touches nothing, it flies attack_range world units and disappears there,
-- whether or not the field edge is nearer -- see the indicator contract below for what sets that
-- number.
--
-- Values. dragon_tower.hp and dragon_flame's damage, speed and radius are all derived with
-- subqueries rather than written as literals. This repository's V032 backfill and the live
-- database disagree on the hp and damage scale -- V053 multiplied every hp and %damage% row by 10
-- and later live balance passes moved some of them again -- so hp and damage literals written from
-- these files would be off by an order of magnitude. dragon_flame is the same kind of object as
-- fire_shot, so its speed and radius are read from fire_shot rather than copied as literals, on the
-- chance a later balance pass moved those the same way it moved hp and damage; V053 itself only
-- touched hp and %damage% rows, so speed and radius were not necessarily carried along with it.
--
--   dragon_tower.hp     = ground_tower.hp     x 1.0   The other lasting Build tower, and the body
--                                                      this matches.
--   dragon_flame.damage = electric_tower.damage x 0.6 Carried over from when dragon_tower's fire
--                                                      picked a single target; the projectile has
--                                                      not been rebalanced against that number.
--   dragon_flame.speed  = fire_shot.speed      x 1.0   fire_shot is the nearest existing projectile.
--   dragon_flame.radius = fire_shot.radius     x 1.0   The projectile's own size; nothing else
--                                                      depends on it now.
--
-- Expected values at the time of writing, from V032 seeds scaled by V053: ground_tower hp 400,
-- electric_tower damage 50, fire_shot speed 8 and fire_shot radius 0.5 (V053 does not touch speed
-- or radius). So dragon_tower gets hp 400, and dragon_flame gets damage 30, speed 8 and radius 0.5.
-- That reconstruction is an estimate, not a claim -- magma_spirit's live hp is 2000 where the same
-- arithmetic predicts 2500 -- which is why all four are subqueries.
--
-- attack_interval, attack_range, radius, duration and mass on dragon_tower are literals in world
-- units and seconds, which no migration has rescaled. attack_interval 1.5 sits between
-- electric_tower's 1.0 and ground_tower's 3.0, unchanged from when dragon_tower picked a target.
-- attack_range 8.0 is how far dragon_flame flies before it disappears, and it is no longer related
-- to any radius. Chosen against its ranged siblings: ground_tower and electric_tower both reach
-- 5.0, sea_serpent's beam reaches 7.0, and the field is 18 world units wide, so a half is 9 --
-- 8.0 sits inside that half, past every existing tower's reach, without covering the whole field.
-- It is a deliberate literal in world units, like attack_interval, not a derivation. radius 1.0 is
-- ground_tower's footprint, also unchanged. duration 20.0 is electric_tower's lifetime, unchanged.
-- mass 1000000.0 is the building mass V073 gave every CAT_Building object, so evil_ent's
-- pull_mass_limit of 5.0 cannot drag the tower; V073 already ran, so a new building has to carry
-- that value itself.
--
-- Indicator contract. The client draws the placement point and the threatened area together, and
-- both values live on the tower's own game object. The threatened area is the row directly ahead of
-- the tower, from the placement point out to attack_range world units. dragon_tower.attack_range is
-- the real reach now -- the server reads it to decide how far each dragon_flame it launches flies
-- before it disappears -- and the client indicator draws that same number, not a copy of
-- dragon_flame.radius or of anything else.
--
-- The name 'range' must not be used here. GameParameterResolver.TryGetMagicParameter resolves
-- 'range' against the cast type family 'build' first, so a range row on the tower would never be
-- read: build.range wins, and build.range is the placement distance and has to stay as it is. No
-- other parameter name has that fallback, so attack_range resolves against the magic name directly.
-- The assertion at the foot fails if a range or beam_width row ever appears on either dragon_tower
-- or dragon_flame.
--
-- Tags. dragon_tower gets TYPE_Unit, CAT_Building and CAT_Ranged for what it is and how it attacks,
-- and CAT_AoE because its impact splash is the same kind ground_tower already carries the tag for
-- in V032. dragon_flame gets TYPE_Unit and CAT_Ranged, matching what V032 gives fire_shot.

-- dragon_tower's hp and dragon_flame's damage, speed and radius are meaningless without their
-- siblings'. Fail before writing NULLs.
DO
$$
    DECLARE
        missing_sibling TEXT;
    BEGIN
        SELECT expected.object_name || '.' || expected.parameter_name
        INTO missing_sibling
        FROM (VALUES ('ground_tower', 'hp'),
                     ('electric_tower', 'damage'),
                     ('fire_shot', 'speed'),
                     ('fire_shot', 'radius')) AS expected(object_name, parameter_name)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = expected.object_name
                            AND parameter.name = expected.parameter_name
                            AND parameter_value.value IS NOT NULL)
        LIMIT 1;

        IF missing_sibling IS NOT NULL THEN
            RAISE EXCEPTION '% is missing; dragon_tower and dragon_flame derive their hp, damage, speed and radius from it',
                missing_sibling;
        END IF;
    END
$$;

WITH inserted_magic AS (
    INSERT INTO magics(name, cast_type)
    SELECT 'dragon_tower', 'build'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'dragon_tower'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'dragon_tower'
),
recipe_cards(card_name, required_count) AS (
    VALUES
        ('Build', 1),
        ('Shoot', 1),
        ('Fire', 1)
),
target_cards AS (
    SELECT card.id, recipe.required_count
    FROM cards card
    JOIN recipe_cards recipe ON recipe.card_name = card.name
),
existing_magic_cards AS (
    SELECT magic_card.card_id, COUNT(*) AS existing_count
    FROM magic_cards magic_card
    JOIN target_magic magic ON magic.id = magic_card.magic_id
    GROUP BY magic_card.card_id
),
missing_magic_cards AS (
    SELECT target.id
    FROM target_cards target
    LEFT JOIN existing_magic_cards existing ON existing.card_id = target.id
    CROSS JOIN generate_series(
        1,
        GREATEST(target.required_count - COALESCE(existing.existing_count, 0), 0)
    )
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT magic.id, missing.id
FROM target_magic magic
CROSS JOIN missing_magic_cards missing;

INSERT INTO parameters(name)
SELECT required.name
FROM (VALUES ('hp'),
             ('attack_interval'),
             ('attack_range'),
             ('radius'),
             ('duration'),
             ('mass'),
             ('damage'),
             ('speed')) AS required(name)
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters parameter
    WHERE parameter.name = required.name
);

INSERT INTO game_objects(name)
SELECT required.name
FROM (VALUES ('dragon_tower'), ('dragon_flame')) AS required(name)
WHERE NOT EXISTS (
    SELECT 1
    FROM game_objects game_object
    WHERE game_object.name = required.name
);

WITH ground_tower_parameters(name, value) AS (
    SELECT parameter.name, parameter_value.value
    FROM parameter_values parameter_value
    JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
    JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
    WHERE game_object.name = 'ground_tower'
),
electric_tower_parameters(name, value) AS (
    SELECT parameter.name, parameter_value.value
    FROM parameter_values parameter_value
    JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
    JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
    WHERE game_object.name = 'electric_tower'
),
fire_shot_parameters(name, value) AS (
    SELECT parameter.name, parameter_value.value
    FROM parameter_values parameter_value
    JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
    JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
    WHERE game_object.name = 'fire_shot'
),
dragon_values(game_object_name, parameter_name, value) AS (
    SELECT 'dragon_tower'::TEXT, 'hp'::TEXT,
           (SELECT value FROM ground_tower_parameters WHERE name = 'hp') * 1.0
    UNION ALL
    SELECT 'dragon_tower'::TEXT, 'attack_interval'::TEXT, 1.5::DOUBLE PRECISION
    UNION ALL
    SELECT 'dragon_tower'::TEXT, 'attack_range'::TEXT, 8.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'dragon_tower'::TEXT, 'radius'::TEXT, 1.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'dragon_tower'::TEXT, 'duration'::TEXT, 20.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'dragon_tower'::TEXT, 'mass'::TEXT, 1000000.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'dragon_flame'::TEXT, 'damage'::TEXT,
           (SELECT value FROM electric_tower_parameters WHERE name = 'damage') * 0.6
    UNION ALL
    SELECT 'dragon_flame'::TEXT, 'speed'::TEXT,
           (SELECT value FROM fire_shot_parameters WHERE name = 'speed') * 1.0
    UNION ALL
    SELECT 'dragon_flame'::TEXT, 'radius'::TEXT,
           (SELECT value FROM fire_shot_parameters WHERE name = 'radius') * 1.0
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, seed.value
FROM dragon_values seed
JOIN game_objects game_object ON game_object.name = seed.game_object_name
JOIN parameters parameter ON parameter.name = seed.parameter_name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(game_object_name, tag_name) AS (
    VALUES
        ('dragon_tower', 'TYPE_Unit'),
        ('dragon_tower', 'CAT_Building'),
        ('dragon_tower', 'CAT_Ranged'),
        ('dragon_tower', 'CAT_AoE'),
        ('dragon_flame', 'TYPE_Unit'),
        ('dragon_flame', 'CAT_Ranged')
),
inserted_tags AS (
    INSERT INTO tags(name)
    SELECT DISTINCT required.tag_name
    FROM required_tags required
    WHERE NOT EXISTS (
        SELECT 1
        FROM tags tag
        WHERE tag.name = required.tag_name
    )
    RETURNING id, name
)
INSERT INTO game_object_tags(game_object_id, tag_id)
SELECT game_object.id, tag.id
FROM required_tags required
JOIN game_objects game_object ON game_object.name = required.game_object_name
JOIN (
    SELECT id, name FROM inserted_tags
    UNION ALL
    SELECT id, name FROM tags
) tag ON tag.name = required.tag_name
WHERE NOT EXISTS (
    SELECT 1
    FROM game_object_tags existing
    WHERE existing.game_object_id = game_object.id
      AND existing.tag_id = tag.id
);

-- Without this the bot scores dragon_tower at the neutral 0.0 and nothing reports it.
SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        recipe             TEXT[];
        colliding_magic    TEXT;
        parameter_count    INTEGER;
        missing_parameter  TEXT;
        tower_hp           DOUBLE PRECISION;
        ground_tower_hp    DOUBLE PRECISION;
        flame_damage       DOUBLE PRECISION;
        electric_damage    DOUBLE PRECISION;
        flame_speed        DOUBLE PRECISION;
        fire_shot_speed    DOUBLE PRECISION;
        flame_radius       DOUBLE PRECISION;
        fire_shot_radius   DOUBLE PRECISION;
        tag_count          INTEGER;
        magic_tag_count    INTEGER;
    BEGIN
        SELECT ARRAY_AGG(card.name::TEXT ORDER BY card.name)
        INTO recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name = 'dragon_tower';

        IF recipe IS DISTINCT FROM ARRAY ['Build', 'Fire', 'Shoot'] THEN
            RAISE EXCEPTION 'dragon_tower recipe is %, expected Build + Fire + Shoot',
                COALESCE(ARRAY_TO_STRING(recipe, ' + '), '(none)');
        END IF;

        -- DatabaseMagicParser.init() keys on the sorted multiset and overwrites on collision
        -- without logging, so a shared recipe silently disables one of the two magics.
        SELECT other.name
        INTO colliding_magic
        FROM (SELECT magic.name,
                     ARRAY_AGG(card.name::TEXT ORDER BY card.name) AS cards
              FROM magics magic
                       JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                       JOIN cards card ON card.id = magic_card.card_id
              GROUP BY magic.name) other
        WHERE other.name <> 'dragon_tower'
          AND other.cards = recipe
        LIMIT 1;

        IF colliding_magic IS NOT NULL THEN
            RAISE EXCEPTION 'magic % already owns the recipe %; one of the two would be shadowed',
                colliding_magic, ARRAY_TO_STRING(recipe, ' + ');
        END IF;

        SELECT COUNT(*)
        INTO parameter_count
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
        WHERE game_object.name = 'dragon_tower';

        IF parameter_count <> 6 THEN
            RAISE EXCEPTION 'dragon_tower has % parameter values, expected 6', parameter_count;
        END IF;

        SELECT COUNT(*)
        INTO parameter_count
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
        WHERE game_object.name = 'dragon_flame';

        IF parameter_count <> 3 THEN
            RAISE EXCEPTION 'dragon_flame has % parameter values, expected 3', parameter_count;
        END IF;

        SELECT expected.game_object_name || '.' || expected.parameter_name
        INTO missing_parameter
        FROM (VALUES ('dragon_tower', 'attack_interval', 1.5),
                     ('dragon_tower', 'attack_range', 8.0),
                     ('dragon_tower', 'radius', 1.0),
                     ('dragon_tower', 'duration', 20.0),
                     ('dragon_tower', 'mass', 1000000.0))
                 AS expected(game_object_name, parameter_name, value)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = expected.game_object_name
                            AND parameter.name = expected.parameter_name
                            AND parameter_value.value = expected.value)
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'parameter % is missing or holds the wrong value', missing_parameter;
        END IF;

        -- GameParameterResolver.TryGetMagicParameter resolves 'range' against the cast type family
        -- 'build' first, so a range row here would be read as the placement distance instead of the
        -- indicator radius, and the client would draw the wrong circle. beam_width belonged to the
        -- old beam design and must not linger on either object.
        IF EXISTS (SELECT 1
                   FROM parameter_values parameter_value
                            JOIN game_objects game_object
                                 ON game_object.id = parameter_value.game_object_id
                            JOIN parameters parameter
                                 ON parameter.id = parameter_value.parameter_id
                   WHERE game_object.name IN ('dragon_tower', 'dragon_flame')
                     AND parameter.name IN ('range', 'beam_width')) THEN
            RAISE EXCEPTION 'dragon_tower or dragon_flame carries a range or beam_width parameter; use attack_range or radius instead';
        END IF;

        SELECT parameter_value.value
        INTO tower_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'dragon_tower'
          AND parameter.name = 'hp';

        SELECT parameter_value.value
        INTO ground_tower_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'ground_tower'
          AND parameter.name = 'hp';

        IF tower_hp IS NULL OR ground_tower_hp IS NULL
            OR ABS(tower_hp - ground_tower_hp) >= 1e-6 THEN
            RAISE EXCEPTION 'dragon_tower hp is % but ground_tower hp is %; they were meant to match',
                COALESCE(tower_hp::TEXT, '(none)'), COALESCE(ground_tower_hp::TEXT, '(none)');
        END IF;

        SELECT parameter_value.value
        INTO flame_damage
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'dragon_flame'
          AND parameter.name = 'damage';

        SELECT parameter_value.value
        INTO electric_damage
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'electric_tower'
          AND parameter.name = 'damage';

        IF flame_damage IS NULL OR electric_damage IS NULL
            OR ABS(flame_damage - electric_damage * 0.6) >= 1e-6 THEN
            RAISE EXCEPTION 'dragon_flame damage is %, expected 0.6 of electric_tower damage %',
                COALESCE(flame_damage::TEXT, '(none)'), COALESCE(electric_damage::TEXT, '(none)');
        END IF;

        SELECT parameter_value.value
        INTO flame_speed
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'dragon_flame'
          AND parameter.name = 'speed';

        SELECT parameter_value.value
        INTO fire_shot_speed
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'fire_shot'
          AND parameter.name = 'speed';

        IF flame_speed IS NULL OR fire_shot_speed IS NULL
            OR ABS(flame_speed - fire_shot_speed) >= 1e-6 THEN
            RAISE EXCEPTION 'dragon_flame speed is % but fire_shot speed is %; they were meant to match',
                COALESCE(flame_speed::TEXT, '(none)'), COALESCE(fire_shot_speed::TEXT, '(none)');
        END IF;

        SELECT parameter_value.value
        INTO flame_radius
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'dragon_flame'
          AND parameter.name = 'radius';

        SELECT parameter_value.value
        INTO fire_shot_radius
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'fire_shot'
          AND parameter.name = 'radius';

        IF flame_radius IS NULL OR fire_shot_radius IS NULL
            OR ABS(flame_radius - fire_shot_radius) >= 1e-6 THEN
            RAISE EXCEPTION 'dragon_flame radius is % but fire_shot radius is %; they were meant to match',
                COALESCE(flame_radius::TEXT, '(none)'), COALESCE(fire_shot_radius::TEXT, '(none)');
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'dragon_tower'
          AND tag.name IN ('TYPE_Unit', 'CAT_Building', 'CAT_Ranged', 'CAT_AoE');

        IF tag_count <> 4 THEN
            RAISE EXCEPTION 'dragon_tower carries % of its 4 counter tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'dragon_flame'
          AND tag.name IN ('TYPE_Unit', 'CAT_Ranged');

        IF tag_count <> 2 THEN
            RAISE EXCEPTION 'dragon_flame carries % of its 2 counter tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO magic_tag_count
        FROM magic_tags magic_tag
                 JOIN magics magic ON magic.id = magic_tag.magic_id
        WHERE magic.name = 'dragon_tower';

        IF magic_tag_count < 4 THEN
            RAISE EXCEPTION 'magic dragon_tower carries only % tags; the name sync did not reach it',
                magic_tag_count;
        END IF;
    END
$$;
