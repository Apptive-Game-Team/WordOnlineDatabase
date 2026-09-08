-- Registers grass_generator: the Build + Explode + Nature building that seeds leaf fields around
-- itself.
--
-- Recipe. {Build, Explode, Nature}. DatabaseMagicParser keys magics on the SORTED MULTISET of
-- card names and its init() is a plain map.put, so a duplicate key silently shadows whichever
-- magic was parsed first with nothing logged. The nearest neighbours are tower (Build + Explode +
-- Rock), overgrowth (Explode + Nature) and life_tree (Build + Nature). The assertion at the foot
-- rechecks uniqueness against the live database rather than trusting a reconstruction of it from
-- these files. The insert uses the generate_series form from V069 so that card counts stay
-- expressible.
--
-- magics.cast_type has been NOT NULL with a CHECK since V047, so the magic row carries 'build'.
--
-- leaf_field is already a registered game object. Nothing here touches it.
--
-- Values. hp is derived from vine_colony with a subquery rather than written as a literal. This
-- repository's V032 backfill and the live database disagree on the hp scale -- V053 multiplied
-- every hp row by 10 and later live balance passes moved some of them again -- so a literal
-- written from these files would be off by an order of magnitude.
--
--   hp = vine_colony.hp x 1.0   The other Nature Build structure, and the body this one matches.
--
-- Expected value at the time of writing, from the V032 seed of 40 scaled by V053: vine_colony hp
-- 400, so grass_generator gets 400. That reconstruction is an estimate, not a claim --
-- magma_spirit's live hp is 2000 where the same arithmetic predicts 2500 -- which is why hp is a
-- subquery.
--
-- radius, attack_interval, quantity, duration and mass are literals in world units and seconds,
-- which no migration has rescaled. radius 5.0 is how far a field can land from the generator,
-- attack_interval 2.0 is the gap between rings, quantity 6 is the fields per ring, and duration
-- 15.0 is vine_colony's lifetime as set by V074. mass 1000000.0 is the building mass V073 gave
-- every CAT_Building object, so evil_ent's pull_mass_limit of 5.0 cannot drag the generator; V073
-- already ran, so a new building has to carry that value itself.
--
-- Field load. A ring of 6 goes out every 2 seconds for 15 seconds, so 8 rings and 48 leaf_field
-- spawns over the generator's whole life. leaf_field's duration is 3 seconds, so at most two
-- rings overlap and the peak is 12 concurrent fields, not 48. The assertion at the foot recomputes
-- that peak from the live leaf_field duration and refuses anything above 24.
--
-- Tags. TYPE_Unit for a body on the field, CAT_Building for what it is, CAT_AoE for the ring of
-- fields it lays down. No CAT_Ranged: the generator has no targeted attack, it seeds ground.
--
-- No magic_game_object_aliases row is needed: the magic and the object are both named
-- grass_generator. leaf_field is not a magic, so it needs no alias either.

-- grass_generator's hp is meaningless without vine_colony's. Fail before writing a NULL.
DO
$$
    BEGIN
        IF NOT EXISTS (SELECT 1
                       FROM parameter_values parameter_value
                                JOIN game_objects game_object
                                     ON game_object.id = parameter_value.game_object_id
                                JOIN parameters parameter
                                     ON parameter.id = parameter_value.parameter_id
                       WHERE game_object.name = 'vine_colony'
                         AND parameter.name = 'hp'
                         AND parameter_value.value IS NOT NULL) THEN
            RAISE EXCEPTION 'vine_colony has no hp value; grass_generator derives its hp from it';
        END IF;
    END
$$;

WITH inserted_magic AS (
    INSERT INTO magics(name, cast_type)
    SELECT 'grass_generator', 'build'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'grass_generator'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'grass_generator'
),
recipe_cards(card_name, required_count) AS (
    VALUES
        ('Build', 1),
        ('Explode', 1),
        ('Nature', 1)
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
    SELECT 'grass_generator'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'grass_generator'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'grass_generator'
),
required_parameters(name) AS (
    VALUES
        ('hp'),
        ('radius'),
        ('attack_interval'),
        ('quantity'),
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
vine_colony_parameters(name, value) AS (
    SELECT parameter.name, parameter_value.value
    FROM parameter_values parameter_value
    JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
    JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
    WHERE game_object.name = 'vine_colony'
),
grass_generator_values(parameter_name, value) AS (
    SELECT 'hp'::TEXT,
           (SELECT value FROM vine_colony_parameters WHERE name = 'hp') * 1.0
    UNION ALL
    SELECT 'radius'::TEXT, 5.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'attack_interval'::TEXT, 2.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'quantity'::TEXT, 6.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'duration'::TEXT, 15.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'mass'::TEXT, 1000000.0::DOUBLE PRECISION
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, seed.value
FROM target_game_object game_object
JOIN target_parameters parameter ON TRUE
JOIN grass_generator_values seed ON seed.parameter_name = parameter.name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(name) AS (
    VALUES
        ('TYPE_Unit'),
        ('CAT_Building'),
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
    WHERE name = 'grass_generator'
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

-- Without this the bot scores grass_generator at the neutral 0.0 and nothing reports it.
SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        recipe               TEXT[];
        colliding_magic      TEXT;
        parameter_count      INTEGER;
        missing_parameter    TEXT;
        generator_hp         DOUBLE PRECISION;
        colony_hp            DOUBLE PRECISION;
        leaf_field_duration  DOUBLE PRECISION;
        peak_field_count     DOUBLE PRECISION;
        tag_count            INTEGER;
        magic_tag_count      INTEGER;
    BEGIN
        SELECT ARRAY_AGG(card.name::TEXT ORDER BY card.name)
        INTO recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name = 'grass_generator';

        IF recipe IS DISTINCT FROM ARRAY ['Build', 'Explode', 'Nature'] THEN
            RAISE EXCEPTION 'grass_generator recipe is %, expected Build + Explode + Nature',
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
        WHERE other.name <> 'grass_generator'
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
        WHERE game_object.name = 'grass_generator';

        IF parameter_count <> 6 THEN
            RAISE EXCEPTION 'grass_generator has % parameter values, expected 6', parameter_count;
        END IF;

        SELECT expected.name
        INTO missing_parameter
        FROM (VALUES ('radius', 5.0), ('attack_interval', 2.0), ('quantity', 6.0),
                     ('duration', 15.0), ('mass', 1000000.0)) AS expected(name, value)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = 'grass_generator'
                            AND parameter.name = expected.name
                            AND parameter_value.value = expected.value)
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'grass_generator parameter % is missing or holds the wrong value',
                missing_parameter;
        END IF;

        SELECT parameter_value.value
        INTO generator_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'grass_generator'
          AND parameter.name = 'hp';

        SELECT parameter_value.value
        INTO colony_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'vine_colony'
          AND parameter.name = 'hp';

        IF generator_hp IS NULL OR colony_hp IS NULL OR ABS(generator_hp - colony_hp) >= 1e-6 THEN
            RAISE EXCEPTION 'grass_generator hp is % but vine_colony hp is %; they were meant to match',
                COALESCE(generator_hp::TEXT, '(none)'), COALESCE(colony_hp::TEXT, '(none)');
        END IF;

        -- Concurrent leaf fields are quantity x (leaf_field duration / attack_interval). A live
        -- leaf_field duration far above the 3 seconds seeded by V032 would turn one generator
        -- into a field carpet, so the peak is recomputed here rather than assumed.
        SELECT parameter_value.value
        INTO leaf_field_duration
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'leaf_field'
          AND parameter.name = 'duration';

        IF leaf_field_duration IS NOT NULL THEN
            peak_field_count := 6.0 * CEIL(leaf_field_duration / 2.0);

            IF peak_field_count > 24 THEN
                RAISE EXCEPTION 'grass_generator would hold % leaf fields at once (leaf_field duration %); raise attack_interval or lower quantity',
                    peak_field_count, leaf_field_duration;
            END IF;
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'grass_generator'
          AND tag.name IN ('TYPE_Unit', 'CAT_Building', 'CAT_AoE');

        IF tag_count <> 3 THEN
            RAISE EXCEPTION 'grass_generator carries % of its 3 counter tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO magic_tag_count
        FROM magic_tags magic_tag
                 JOIN magics magic ON magic.id = magic_tag.magic_id
        WHERE magic.name = 'grass_generator';

        IF magic_tag_count < 3 THEN
            RAISE EXCEPTION 'magic grass_generator carries only % tags; the name sync did not reach it',
                magic_tag_count;
        END IF;
    END
$$;
