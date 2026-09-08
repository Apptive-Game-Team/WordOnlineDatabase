-- Registers dragon_tower: the Build + Shoot + Fire defensive tower that hits ground and air.
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
-- Values. hp and damage are derived with subqueries rather than written as literals. This
-- repository's V032 backfill and the live database disagree on the hp and damage scale -- V053
-- multiplied every hp and %damage% row by 10 and later live balance passes moved some of them
-- again -- so literals written from these files would be off by an order of magnitude.
--
--   hp     = ground_tower.hp     x 1.0   The other lasting Build tower, and the body this matches.
--   damage = electric_tower.damage x 0.6 Under electric_tower, which is what a tower that reaches
--                                        both ground and air pays for the extra coverage.
--
-- Expected values at the time of writing, from V032 seeds scaled by V053: ground_tower hp 400 and
-- electric_tower damage 50, so dragon_tower gets hp 400 and damage 30. That reconstruction is an
-- estimate, not a claim -- magma_spirit's live hp is 2000 where the same arithmetic predicts 2500
-- -- which is why both are subqueries.
--
-- attack_interval, attack_range, radius, duration and mass are literals in world units and
-- seconds, which no migration has rescaled. attack_interval 1.5 sits between electric_tower's 1.0
-- and ground_tower's 3.0. attack_range 5.0 is what both towers already reach. radius 1.0 is
-- ground_tower's footprint. duration 20.0 is electric_tower's lifetime. mass 1000000.0 is the
-- building mass V073 gave every CAT_Building object, so evil_ent's pull_mass_limit of 5.0 cannot
-- drag the tower; V073 already ran, so a new building has to carry that value itself.
--
-- Indicator contract. The client draws the placement point and the threatened area together, and
-- both values live on the tower's own game object. attack_range is the radius of the threatened
-- area. dragon_tower gets no attack_offset: it threatens a circle around where it stands, so the
-- indicator centres on the placement point, which is what a missing or zero attack_offset means.
--
-- The name 'range' must not be used here. GameParameterResolver.TryGetMagicParameter looks up
-- 'range' under the cast type family name 'build' before it falls back to the magic name, so a
-- range row on the tower would never be read: build.range wins, and build.range is the placement
-- distance and has to stay as it is. No other parameter name has that fallback, so attack_range
-- resolves against the magic name directly. The assertion at the foot fails if a range row ever
-- appears on dragon_tower.
--
-- Tags. TYPE_Unit for a body on the field, CAT_Building for what it is, CAT_Ranged for the shots.
-- No CAT_AoE: dragon_tower fires at one target at a time.
--
-- No magic_game_object_aliases row is needed: the magic and the object are both named
-- dragon_tower.

-- dragon_tower's hp and damage are meaningless without their siblings'. Fail before writing NULLs.
DO
$$
    DECLARE
        missing_sibling TEXT;
    BEGIN
        SELECT expected.object_name || '.' || expected.parameter_name
        INTO missing_sibling
        FROM (VALUES ('ground_tower', 'hp'),
                     ('electric_tower', 'damage')) AS expected(object_name, parameter_name)
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
            RAISE EXCEPTION '% is missing; dragon_tower derives its hp and damage from it',
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

WITH inserted_game_object AS (
    INSERT INTO game_objects(name)
    SELECT 'dragon_tower'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'dragon_tower'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'dragon_tower'
),
required_parameters(name) AS (
    VALUES
        ('hp'),
        ('damage'),
        ('attack_interval'),
        ('attack_range'),
        ('radius'),
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
sibling_parameters(object_name, name, value) AS (
    SELECT game_object.name, parameter.name, parameter_value.value
    FROM parameter_values parameter_value
    JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
    JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
    WHERE game_object.name IN ('ground_tower', 'electric_tower')
),
dragon_tower_values(parameter_name, value) AS (
    SELECT 'hp'::TEXT,
           (SELECT value
            FROM sibling_parameters
            WHERE object_name = 'ground_tower'
              AND name = 'hp') * 1.0
    UNION ALL
    SELECT 'damage'::TEXT,
           (SELECT value
            FROM sibling_parameters
            WHERE object_name = 'electric_tower'
              AND name = 'damage') * 0.6
    UNION ALL
    SELECT 'attack_interval'::TEXT, 1.5::DOUBLE PRECISION
    UNION ALL
    SELECT 'attack_range'::TEXT, 5.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'radius'::TEXT, 1.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'duration'::TEXT, 20.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'mass'::TEXT, 1000000.0::DOUBLE PRECISION
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, seed.value
FROM target_game_object game_object
JOIN target_parameters parameter ON TRUE
JOIN dragon_tower_values seed ON seed.parameter_name = parameter.name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(name) AS (
    VALUES
        ('TYPE_Unit'),
        ('CAT_Building'),
        ('CAT_Ranged')
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
    WHERE name = 'dragon_tower'
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
        tower_damage       DOUBLE PRECISION;
        electric_damage    DOUBLE PRECISION;
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

        IF parameter_count <> 7 THEN
            RAISE EXCEPTION 'dragon_tower has % parameter values, expected 7', parameter_count;
        END IF;

        SELECT expected.name
        INTO missing_parameter
        FROM (VALUES ('attack_interval', 1.5), ('attack_range', 5.0), ('radius', 1.0),
                     ('duration', 20.0), ('mass', 1000000.0)) AS expected(name, value)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = 'dragon_tower'
                            AND parameter.name = expected.name
                            AND parameter_value.value = expected.value)
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'dragon_tower parameter % is missing or holds the wrong value',
                missing_parameter;
        END IF;

        -- GameParameterResolver.TryGetMagicParameter resolves 'range' against the cast type family
        -- 'build' first, so a range row here would be read as the placement distance instead of
        -- the tower's reach, and the indicator would draw the wrong circle.
        IF EXISTS (SELECT 1
                   FROM parameter_values parameter_value
                            JOIN game_objects game_object
                                 ON game_object.id = parameter_value.game_object_id
                            JOIN parameters parameter
                                 ON parameter.id = parameter_value.parameter_id
                   WHERE game_object.name = 'dragon_tower'
                     AND parameter.name = 'range') THEN
            RAISE EXCEPTION 'dragon_tower carries a range parameter; build.range shadows it, use attack_range';
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
        INTO tower_damage
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'dragon_tower'
          AND parameter.name = 'damage';

        SELECT parameter_value.value
        INTO electric_damage
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'electric_tower'
          AND parameter.name = 'damage';

        IF tower_damage IS NULL OR electric_damage IS NULL
            OR ABS(tower_damage - electric_damage * 0.6) >= 1e-6 THEN
            RAISE EXCEPTION 'dragon_tower damage is %, expected 0.6 of electric_tower damage %',
                COALESCE(tower_damage::TEXT, '(none)'), COALESCE(electric_damage::TEXT, '(none)');
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'dragon_tower'
          AND tag.name IN ('TYPE_Unit', 'CAT_Building', 'CAT_Ranged');

        IF tag_count <> 3 THEN
            RAISE EXCEPTION 'dragon_tower carries % of its 3 counter tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO magic_tag_count
        FROM magic_tags magic_tag
                 JOIN magics magic ON magic.id = magic_tag.magic_id
        WHERE magic.name = 'dragon_tower';

        IF magic_tag_count < 3 THEN
            RAISE EXCEPTION 'magic dragon_tower carries only % tags; the name sync did not reach it',
                magic_tag_count;
        END IF;
    END
$$;
