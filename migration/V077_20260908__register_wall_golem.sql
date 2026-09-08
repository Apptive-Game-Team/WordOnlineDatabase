-- Registers wall_golem: the Rock x3 + Spawn top-tier tank.
--
-- Recipe. {Rock, Rock, Rock, Spawn}. DatabaseMagicParser keys magics on the SORTED MULTISET of
-- card names and its init() is a plain map.put, so a duplicate key silently shadows whichever
-- magic was parsed first with nothing logged. Card counts are part of that key, which a
-- WHERE name IN (...) cannot express, so the insert below uses the generate_series form from
-- V069. The nearest neighbours are rock_golem (Rock x2 + Spawn) and mini_rock_swarm (Rock +
-- Spawn). The assertion at the foot rechecks uniqueness against the live database rather than
-- trusting a reconstruction of it from these files.
--
-- magics.cast_type has been NOT NULL with a CHECK since V047, so the magic row carries 'spawn'.
--
-- Values. hp, damage and speed are derived from rock_golem with a subquery instead of being
-- written as literals. This repository's V032 backfill and the live database disagree on the hp
-- and damage scale -- V053 multiplied every hp and %damage% row by 10, and later live balance
-- passes moved some of them again -- so a literal written from these files would be off by an
-- order of magnitude. Deriving keeps wall_golem in a fixed ratio to rock_golem whatever the
-- absolute scale turns out to be.
--
--   hp    = rock_golem.hp    x 3.0   The tank premium the issue asks for.
--   damage= rock_golem.damage x 0.8  Slightly under rock_golem: it trades offence for the body.
--   speed = rock_golem.speed x 0.6   A wall that arrives late.
--
-- Expected values at the time of writing, from V032 seeds scaled by V053: rock_golem hp 1000,
-- damage 50, speed 0.5, so wall_golem gets hp 3000, damage 40, speed 0.3. That reconstruction is
-- an estimate, not a claim -- magma_spirit's live hp is 2000 where the same arithmetic predicts
-- 2500 -- which is exactly why these three are subqueries.
--
-- attack_interval, mass, radius and quantity are literals. They are in seconds and world units,
-- which no migration has rescaled: 2.5 is rock_golem's seeded attack_interval, 10.0 is the golem
-- mass class, 1.8 is a body wider than rock_golem's 1.5, and 1 is a single summon.
--
-- Tags. TYPE_Unit for a body on the field, CAT_Tank and CAT_Large for the role and size that
-- rock_golem already carries, CAT_Melee for the contact attack.
--
-- No magic_game_object_aliases row is needed: the magic and the object are both named wall_golem,
-- so the name join in sync_magic_tags_from_game_objects() reaches it directly.

-- wall_golem's hp, damage and speed are meaningless without rock_golem's. Fail before writing a
-- NULL rather than after.
DO
$$
    DECLARE
        missing_parameter TEXT;
    BEGIN
        SELECT expected.name
        INTO missing_parameter
        FROM (VALUES ('hp'), ('damage'), ('speed')) AS expected(name)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = 'rock_golem'
                            AND parameter.name = expected.name
                            AND parameter_value.value IS NOT NULL)
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'rock_golem has no % value; wall_golem derives hp, damage and speed from it',
                missing_parameter;
        END IF;
    END
$$;

WITH inserted_magic AS (
    INSERT INTO magics(name, cast_type)
    SELECT 'wall_golem', 'spawn'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'wall_golem'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'wall_golem'
),
recipe_cards(card_name, required_count) AS (
    VALUES
        ('Rock', 3),
        ('Spawn', 1)
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
    SELECT 'wall_golem'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'wall_golem'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'wall_golem'
),
required_parameters(name) AS (
    VALUES
        ('hp'),
        ('speed'),
        ('damage'),
        ('attack_interval'),
        ('mass'),
        ('radius'),
        ('quantity')
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
rock_golem_parameters(name, value) AS (
    SELECT parameter.name, parameter_value.value
    FROM parameter_values parameter_value
    JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
    JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
    WHERE game_object.name = 'rock_golem'
),
wall_golem_values(parameter_name, value) AS (
    SELECT 'hp'::TEXT,
           (SELECT value FROM rock_golem_parameters WHERE name = 'hp') * 3.0
    UNION ALL
    SELECT 'damage'::TEXT,
           (SELECT value FROM rock_golem_parameters WHERE name = 'damage') * 0.8
    UNION ALL
    SELECT 'speed'::TEXT,
           (SELECT value FROM rock_golem_parameters WHERE name = 'speed') * 0.6
    UNION ALL
    SELECT 'attack_interval'::TEXT, 2.5::DOUBLE PRECISION
    UNION ALL
    SELECT 'mass'::TEXT, 10.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'radius'::TEXT, 1.8::DOUBLE PRECISION
    UNION ALL
    SELECT 'quantity'::TEXT, 1.0::DOUBLE PRECISION
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, seed.value
FROM target_game_object game_object
JOIN target_parameters parameter ON TRUE
JOIN wall_golem_values seed ON seed.parameter_name = parameter.name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(name) AS (
    VALUES
        ('TYPE_Unit'),
        ('CAT_Tank'),
        ('CAT_Large'),
        ('CAT_Melee')
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
    WHERE name = 'wall_golem'
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

-- Without this the bot scores wall_golem at the neutral 0.0 and nothing reports it.
SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        recipe            TEXT[];
        colliding_magic   TEXT;
        parameter_count   INTEGER;
        missing_parameter TEXT;
        derived_gap       TEXT;
        tag_count         INTEGER;
        magic_tag_count   INTEGER;
    BEGIN
        SELECT ARRAY_AGG(card.name::TEXT ORDER BY card.name)
        INTO recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name = 'wall_golem';

        IF recipe IS DISTINCT FROM ARRAY ['Rock', 'Rock', 'Rock', 'Spawn'] THEN
            RAISE EXCEPTION 'wall_golem recipe is %, expected Rock x3 + Spawn',
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
        WHERE other.name <> 'wall_golem'
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
        WHERE game_object.name = 'wall_golem';

        IF parameter_count <> 7 THEN
            RAISE EXCEPTION 'wall_golem has % parameter values, expected 7', parameter_count;
        END IF;

        SELECT expected.name
        INTO missing_parameter
        FROM (VALUES ('attack_interval', 2.5), ('mass', 10.0), ('radius', 1.8),
                     ('quantity', 1.0)) AS expected(name, value)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = 'wall_golem'
                            AND parameter.name = expected.name
                            AND parameter_value.value = expected.value)
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'wall_golem parameter % is missing or holds the wrong value',
                missing_parameter;
        END IF;

        -- The three derived rows are checked as ratios, which is what the file actually promises.
        SELECT expected.name
        INTO derived_gap
        FROM (VALUES ('hp', 3.0), ('damage', 0.8), ('speed', 0.6)) AS expected(name, multiplier)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values wall_value
                                   JOIN game_objects wall ON wall.id = wall_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = wall_value.parameter_id
                                   JOIN game_objects rock ON rock.name = 'rock_golem'
                                   JOIN parameter_values rock_value
                                        ON rock_value.game_object_id = rock.id
                                            AND rock_value.parameter_id = parameter.id
                          WHERE wall.name = 'wall_golem'
                            AND parameter.name = expected.name
                            AND ABS(wall_value.value - rock_value.value * expected.multiplier) < 1e-6)
        LIMIT 1;

        IF derived_gap IS NOT NULL THEN
            RAISE EXCEPTION 'wall_golem % is not the intended multiple of rock_golem %',
                derived_gap, derived_gap;
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'wall_golem'
          AND tag.name IN ('TYPE_Unit', 'CAT_Tank', 'CAT_Large', 'CAT_Melee');

        IF tag_count <> 4 THEN
            RAISE EXCEPTION 'wall_golem carries % of its 4 counter tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO magic_tag_count
        FROM magic_tags magic_tag
                 JOIN magics magic ON magic.id = magic_tag.magic_id
        WHERE magic.name = 'wall_golem';

        IF magic_tag_count < 4 THEN
            RAISE EXCEPTION 'magic wall_golem carries only % tags; the name sync did not reach it',
                magic_tag_count;
        END IF;
    END
$$;
