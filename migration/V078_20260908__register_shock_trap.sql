-- Registers shock_trap: the Build + Explode + Lightning stun trap.
--
-- Recipe. {Build, Explode, Lightning}. DatabaseMagicParser keys magics on the SORTED MULTISET of
-- card names and its init() is a plain map.put, so a duplicate key silently shadows whichever
-- magic was parsed first with nothing logged. The nearest neighbours are tower (Build + Explode +
-- Rock) and electric_tower (Build + Lightning). The assertion at the foot rechecks uniqueness
-- against the live database rather than trusting a reconstruction of it from these files. The
-- insert uses the generate_series form from V069 so that card counts stay expressible.
--
-- magics.cast_type has been NOT NULL with a CHECK since V047, so the magic row carries 'build'.
--
-- Parameters. trigger_delay and stun_duration are new names in the parameters table; this
-- migration adds them. trigger_delay is the arming time in seconds between placement and the
-- trap becoming live. stun_duration is how long a caught target is held. attack_interval is the
-- reload between discharges.
--
-- Values. hp is derived from electric_tower with a subquery rather than written as a literal.
-- This repository's V032 backfill and the live database disagree on the hp scale -- V053
-- multiplied every hp row by 10 and later live balance passes moved some of them again -- so a
-- literal written from these files would be off by an order of magnitude.
--
--   hp = electric_tower.hp x 1.0   The issue asks for the same body as electric_tower.
--
-- Expected value at the time of writing, from the V032 seed of 16 scaled by V053: electric_tower
-- hp 160, so shock_trap gets 160. That reconstruction is an estimate, not a claim --
-- magma_spirit's live hp is 2000 where the same arithmetic predicts 2500 -- which is why hp is a
-- subquery.
--
-- radius, trigger_delay, stun_duration, attack_interval, duration and mass are literals in world
-- units and seconds, which no migration has rescaled. radius 3.0 matches Explode.EXPLODE_RADIUS
-- of 3f on the game server. duration 20.0 is electric_tower's seeded lifetime. mass 1000000.0 is
-- the building mass V073 gave every CAT_Building object, so evil_ent's pull_mass_limit of 5.0
-- cannot drag the trap; V073 already ran, so a new building has to carry that value itself.
--
-- Tags. TYPE_Unit for a body on the field, CAT_Building for what it is, CAT_AoE for the radius,
-- and CAT_CC for the stun -- which is also the tag the ('CAT_CC', 'CAT_Large') and
-- ('CAT_CC', 'CAT_Tank') rules seeded by V056 read. Without CAT_CC the bot never reaches for the
-- trap against the units it exists to answer.
--
-- No magic_game_object_aliases row is needed: the magic and the object are both named shock_trap.

-- shock_trap's hp is meaningless without electric_tower's. Fail before writing a NULL.
DO
$$
    BEGIN
        IF NOT EXISTS (SELECT 1
                       FROM parameter_values parameter_value
                                JOIN game_objects game_object
                                     ON game_object.id = parameter_value.game_object_id
                                JOIN parameters parameter
                                     ON parameter.id = parameter_value.parameter_id
                       WHERE game_object.name = 'electric_tower'
                         AND parameter.name = 'hp'
                         AND parameter_value.value IS NOT NULL) THEN
            RAISE EXCEPTION 'electric_tower has no hp value; shock_trap derives its hp from it';
        END IF;
    END
$$;

WITH inserted_magic AS (
    INSERT INTO magics(name, cast_type)
    SELECT 'shock_trap', 'build'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'shock_trap'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'shock_trap'
),
recipe_cards(card_name, required_count) AS (
    VALUES
        ('Build', 1),
        ('Explode', 1),
        ('Lightning', 1)
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

WITH inserted_game_object AS (
    INSERT INTO game_objects(name)
    SELECT 'shock_trap'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'shock_trap'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'shock_trap'
),
required_parameters(name) AS (
    VALUES
        ('hp'),
        ('radius'),
        ('trigger_delay'),
        ('stun_duration'),
        ('attack_interval'),
        ('duration'),
        ('mass')
),
inserted_parameters AS (
    INSERT INTO parameters(name)
    SELECT required.name
    FROM required_parameters required
    WHERE NOT EXISTS (
        SELECT 1
        FROM parameters parameter
        WHERE parameter.name = required.name
    )
    RETURNING id, name
),
target_parameters AS (
    SELECT id, name FROM inserted_parameters
    UNION ALL
    SELECT parameter.id, parameter.name
    FROM parameters parameter
    JOIN required_parameters required ON required.name = parameter.name
),
electric_tower_parameters(name, value) AS (
    SELECT parameter.name, parameter_value.value
    FROM parameter_values parameter_value
    JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
    JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
    WHERE game_object.name = 'electric_tower'
),
shock_trap_values(parameter_name, value) AS (
    SELECT 'hp'::TEXT,
           (SELECT value FROM electric_tower_parameters WHERE name = 'hp') * 1.0
    UNION ALL
    SELECT 'radius'::TEXT, 3.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'trigger_delay'::TEXT, 1.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'stun_duration'::TEXT, 2.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'attack_interval'::TEXT, 8.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'duration'::TEXT, 20.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'mass'::TEXT, 1000000.0::DOUBLE PRECISION
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, seed.value
FROM target_game_object game_object
JOIN target_parameters parameter ON TRUE
JOIN shock_trap_values seed ON seed.parameter_name = parameter.name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(name) AS (
    VALUES
        ('TYPE_Unit'),
        ('CAT_Building'),
        ('CAT_CC'),
        ('CAT_AoE')
),
inserted_tags AS (
    INSERT INTO tags(name)
    SELECT required.name
    FROM required_tags required
    WHERE NOT EXISTS (
        SELECT 1
        FROM tags tag
        WHERE tag.name = required.name
    )
    RETURNING id, name
),
target_tags AS (
    SELECT id, name FROM inserted_tags
    UNION ALL
    SELECT tag.id, tag.name
    FROM tags tag
    JOIN required_tags required ON required.name = tag.name
),
target_game_object AS (
    SELECT id
    FROM game_objects
    WHERE name = 'shock_trap'
)
INSERT INTO game_object_tags(game_object_id, tag_id)
SELECT game_object.id, tag.id
FROM target_game_object game_object
JOIN target_tags tag ON TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM game_object_tags existing
    WHERE existing.game_object_id = game_object.id
      AND existing.tag_id = tag.id
);

-- Without this the bot scores shock_trap at the neutral 0.0 and nothing reports it.
SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        recipe            TEXT[];
        colliding_magic   TEXT;
        parameter_count   INTEGER;
        missing_parameter TEXT;
        trap_hp           DOUBLE PRECISION;
        tower_hp          DOUBLE PRECISION;
        tag_count         INTEGER;
        magic_tag_count   INTEGER;
    BEGIN
        SELECT ARRAY_AGG(card.name::TEXT ORDER BY card.name)
        INTO recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name = 'shock_trap';

        IF recipe IS DISTINCT FROM ARRAY ['Build', 'Explode', 'Lightning'] THEN
            RAISE EXCEPTION 'shock_trap recipe is %, expected Build + Explode + Lightning',
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
        WHERE other.name <> 'shock_trap'
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
        WHERE game_object.name = 'shock_trap';

        IF parameter_count <> 7 THEN
            RAISE EXCEPTION 'shock_trap has % parameter values, expected 7', parameter_count;
        END IF;

        SELECT expected.name
        INTO missing_parameter
        FROM (VALUES ('radius', 3.0), ('trigger_delay', 1.0), ('stun_duration', 2.0),
                     ('attack_interval', 8.0), ('duration', 20.0),
                     ('mass', 1000000.0)) AS expected(name, value)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = 'shock_trap'
                            AND parameter.name = expected.name
                            AND parameter_value.value = expected.value)
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'shock_trap parameter % is missing or holds the wrong value',
                missing_parameter;
        END IF;

        SELECT parameter_value.value
        INTO trap_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'shock_trap'
          AND parameter.name = 'hp';

        SELECT parameter_value.value
        INTO tower_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'electric_tower'
          AND parameter.name = 'hp';

        IF trap_hp IS NULL OR tower_hp IS NULL OR ABS(trap_hp - tower_hp) >= 1e-6 THEN
            RAISE EXCEPTION 'shock_trap hp is % but electric_tower hp is %; they were meant to match',
                COALESCE(trap_hp::TEXT, '(none)'), COALESCE(tower_hp::TEXT, '(none)');
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'shock_trap'
          AND tag.name IN ('TYPE_Unit', 'CAT_Building', 'CAT_CC', 'CAT_AoE');

        IF tag_count <> 4 THEN
            RAISE EXCEPTION 'shock_trap carries % of its 4 counter tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO magic_tag_count
        FROM magic_tags magic_tag
                 JOIN magics magic ON magic.id = magic_tag.magic_id
        WHERE magic.name = 'shock_trap';

        IF magic_tag_count < 4 THEN
            RAISE EXCEPTION 'magic shock_trap carries only % tags; the name sync did not reach it',
                magic_tag_count;
        END IF;
    END
$$;
