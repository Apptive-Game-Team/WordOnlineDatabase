-- Registers storm_stag: the Lightning x3 + Spawn + Shoot charge unit.
--
-- The recipe is a multiset. magic_cards deliberately keeps three Lightning rows because
-- DatabaseMagicParser sorts the full card list, including duplicates, before lookup.
--
-- The magic and game object share the storm_stag name, so the standard tag sync reaches it
-- without a magic_game_object_aliases row.

WITH inserted_magic AS (
    INSERT INTO magics(name, cast_type)
    SELECT 'storm_stag', 'spawn'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'storm_stag'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'storm_stag'
),
recipe_cards(card_name, required_count) AS (
    VALUES
        ('Lightning', 3),
        ('Spawn', 1),
        ('Shoot', 1)
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
    SELECT 'storm_stag'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'storm_stag'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'storm_stag'
),
required_parameters(name) AS (
    VALUES
        ('mass'),
        ('radius'),
        ('hp'),
        ('speed'),
        ('acceleration'),
        ('damage'),
        ('attack_interval'),
        ('detection_range'),
        ('panic_duration'),
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
storm_stag_values(parameter_name, value) AS (
    VALUES
        ('mass', 3.0),
        ('radius', 0.8),
        ('hp', 140.0),
        ('speed', 3.0),
        ('acceleration', 0.75),
        ('damage', 18.0),
        ('attack_interval', 0.8),
        ('detection_range', 5.0),
        ('panic_duration', 2.0),
        ('quantity', 1.0)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, seed.value
FROM target_game_object game_object
JOIN target_parameters parameter ON TRUE
JOIN storm_stag_values seed ON seed.parameter_name = parameter.name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(name) AS (
    VALUES
        ('TYPE_Unit'),
        ('CAT_Medium'),
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
    WHERE name = 'storm_stag'
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

SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        recipe            TEXT[];
        colliding_magic   TEXT;
        parameter_count   INTEGER;
        missing_parameter TEXT;
        tag_count         INTEGER;
        magic_tag_count   INTEGER;
    BEGIN
        SELECT ARRAY_AGG(card.name::TEXT ORDER BY card.name)
        INTO recipe
        FROM magics magic
        JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
        JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name = 'storm_stag';

        IF recipe IS DISTINCT FROM ARRAY ['Lightning', 'Lightning', 'Lightning', 'Shoot', 'Spawn'] THEN
            RAISE EXCEPTION 'storm_stag recipe is %, expected Lightning x3 + Shoot + Spawn',
                COALESCE(ARRAY_TO_STRING(recipe, ' + '), '(none)');
        END IF;

        SELECT other.name
        INTO colliding_magic
        FROM (SELECT magic.name,
                     ARRAY_AGG(card.name::TEXT ORDER BY card.name) AS cards
              FROM magics magic
              JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
              JOIN cards card ON card.id = magic_card.card_id
              GROUP BY magic.name) other
        WHERE other.name <> 'storm_stag'
          AND other.cards = recipe
        LIMIT 1;

        IF colliding_magic IS NOT NULL THEN
            RAISE EXCEPTION 'magic % already owns the storm_stag recipe', colliding_magic;
        END IF;

        SELECT COUNT(*)
        INTO parameter_count
        FROM parameter_values parameter_value
        JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
        WHERE game_object.name = 'storm_stag';

        IF parameter_count <> 10 THEN
            RAISE EXCEPTION 'storm_stag has % parameter values, expected 10', parameter_count;
        END IF;

        SELECT expected.name
        INTO missing_parameter
        FROM (VALUES ('mass', 3.0), ('radius', 0.8), ('hp', 140.0), ('speed', 3.0),
                     ('acceleration', 0.75), ('damage', 18.0), ('attack_interval', 0.8),
                     ('detection_range', 5.0), ('panic_duration', 2.0), ('quantity', 1.0))
                 AS expected(name, value)
        WHERE NOT EXISTS (
            SELECT 1
            FROM parameter_values parameter_value
            JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
            JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
            WHERE game_object.name = 'storm_stag'
              AND parameter.name = expected.name
              AND parameter_value.value = expected.value
        )
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'storm_stag parameter % is missing or incorrect', missing_parameter;
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
        JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
        JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'storm_stag'
          AND tag.name IN ('TYPE_Unit', 'CAT_Medium', 'CAT_Melee');

        IF tag_count <> 3 THEN
            RAISE EXCEPTION 'storm_stag carries % of its 3 required tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO magic_tag_count
        FROM magic_tags magic_tag
        JOIN magics magic ON magic.id = magic_tag.magic_id
        WHERE magic.name = 'storm_stag';

        IF magic_tag_count < 3 THEN
            RAISE EXCEPTION 'magic storm_stag carries only % tags', magic_tag_count;
        END IF;
    END
$$;
