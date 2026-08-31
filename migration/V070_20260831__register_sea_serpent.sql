-- Registers sea_serpent: the Spawn + Shoot + Water x3 upper-tier summon.
--
-- magic_cards stores a multiset rather than distinct card names. The three Water rows below
-- are therefore intentional and are asserted at the end of the migration. The parser sorts
-- that multiset as its key, so a duplicate recipe would silently shadow another magic.
--
-- Sea Serpent is a large ranged area unit. It travels submerged, leaves WaterField objects
-- along its path, and fires a straight hydro-pump beam that can hit ground and air targets.
-- beam_width is the radius around the attack segment used by the server's hit test.

WITH inserted_magic AS (
    INSERT INTO magics(name, cast_type)
    SELECT 'sea_serpent', 'spawn'
    WHERE NOT EXISTS (
        SELECT 1 FROM magics WHERE name = 'sea_serpent'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id FROM magics WHERE name = 'sea_serpent'
),
recipe_cards(card_name, required_count) AS (
    VALUES
        ('Spawn', 1),
        ('Shoot', 1),
        ('Water', 3)
),
target_cards AS (
    SELECT c.id, rc.required_count
    FROM cards c
    JOIN recipe_cards rc ON rc.card_name = c.name
),
existing_magic_cards AS (
    SELECT mc.card_id, COUNT(*) AS existing_count
    FROM magic_cards mc
    JOIN target_magic tm ON tm.id = mc.magic_id
    GROUP BY mc.card_id
),
missing_magic_cards AS (
    SELECT tc.id
    FROM target_cards tc
    LEFT JOIN existing_magic_cards emc ON emc.card_id = tc.id
    CROSS JOIN generate_series(1, GREATEST(tc.required_count - COALESCE(emc.existing_count, 0), 0))
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT tm.id, mmc.id
FROM target_magic tm
CROSS JOIN missing_magic_cards mmc;

WITH inserted_game_object AS (
    INSERT INTO game_objects(name)
    SELECT 'sea_serpent'
    WHERE NOT EXISTS (
        SELECT 1 FROM game_objects WHERE name = 'sea_serpent'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id FROM game_objects WHERE name = 'sea_serpent'
),
required_parameters(name) AS (
    VALUES
        ('mass'),
        ('radius'),
        ('hp'),
        ('speed'),
        ('damage'),
        ('attack_interval'),
        ('attack_range'),
        ('beam_width'),
        ('quantity')
),
inserted_parameters AS (
    INSERT INTO parameters(name)
    SELECT rp.name
    FROM required_parameters rp
    WHERE NOT EXISTS (
        SELECT 1 FROM parameters p WHERE p.name = rp.name
    )
    RETURNING id, name
),
target_parameters AS (
    SELECT id, name FROM inserted_parameters
    UNION ALL
    SELECT p.id, p.name
    FROM parameters p
    JOIN required_parameters rp ON rp.name = p.name
),
sea_serpent_values(parameter_name, value) AS (
    VALUES
        ('mass', 10.0),
        ('radius', 1.2),
        ('hp', 160.0),
        ('speed', 0.55),
        ('damage', 16.0),
        ('attack_interval', 3.5),
        ('attack_range', 7.0),
        ('beam_width', 1.0),
        ('quantity', 1.0)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT tgo.id, tp.id, ssv.value
FROM target_game_object tgo
JOIN target_parameters tp ON TRUE
JOIN sea_serpent_values ssv ON ssv.parameter_name = tp.name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(name) AS (
    VALUES
        ('TYPE_Unit'),
        ('CAT_Large'),
        ('CAT_Ranged'),
        ('CAT_AoE')
),
inserted_tags AS (
    INSERT INTO tags(name)
    SELECT rt.name
    FROM required_tags rt
    WHERE NOT EXISTS (
        SELECT 1 FROM tags t WHERE t.name = rt.name
    )
    RETURNING id, name
),
target_tags AS (
    SELECT id, name FROM inserted_tags
    UNION ALL
    SELECT t.id, t.name
    FROM tags t
    JOIN required_tags rt ON rt.name = t.name
),
target_game_object AS (
    SELECT id FROM game_objects WHERE name = 'sea_serpent'
)
INSERT INTO game_object_tags(game_object_id, tag_id)
SELECT tgo.id, tt.id
FROM target_game_object tgo
JOIN target_tags tt ON TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM game_object_tags got
    WHERE got.game_object_id = tgo.id
      AND got.tag_id = tt.id
);

SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        recipe            TEXT[];
        colliding_magic   TEXT;
        missing_parameter TEXT;
        tag_count         INTEGER;
        magic_tag_count   INTEGER;
    BEGIN
        SELECT ARRAY_AGG(card.name::TEXT ORDER BY card.name)
        INTO recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name = 'sea_serpent';

        IF recipe IS DISTINCT FROM ARRAY ['Shoot', 'Spawn', 'Water', 'Water', 'Water'] THEN
            RAISE EXCEPTION 'sea_serpent recipe is %, expected Shoot + Spawn + Water x3',
                COALESCE(ARRAY_TO_STRING(recipe, ' + '), '(none)');
        END IF;

        SELECT other.name
        INTO colliding_magic
        FROM (SELECT magic.name, ARRAY_AGG(card.name::TEXT ORDER BY card.name) AS cards
              FROM magics magic
                       JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                       JOIN cards card ON card.id = magic_card.card_id
              GROUP BY magic.name) other
        WHERE other.name <> 'sea_serpent'
          AND other.cards = recipe
        LIMIT 1;

        IF colliding_magic IS NOT NULL THEN
            RAISE EXCEPTION 'magic % already owns recipe %',
                colliding_magic, ARRAY_TO_STRING(recipe, ' + ');
        END IF;

        SELECT expected.name
        INTO missing_parameter
        FROM (VALUES ('mass', 10.0), ('radius', 1.2), ('hp', 160.0), ('speed', 0.55),
                     ('damage', 16.0), ('attack_interval', 3.5), ('attack_range', 7.0),
                     ('beam_width', 1.0), ('quantity', 1.0)) AS expected(name, value)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = 'sea_serpent'
                            AND parameter.name = expected.name
                            AND parameter_value.value = expected.value)
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'sea_serpent parameter % is missing or wrong', missing_parameter;
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'sea_serpent'
          AND tag.name IN ('TYPE_Unit', 'CAT_Large', 'CAT_Ranged', 'CAT_AoE');

        IF tag_count <> 4 THEN
            RAISE EXCEPTION 'sea_serpent carries % of 4 required tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO magic_tag_count
        FROM magic_tags magic_tag
                 JOIN magics magic ON magic.id = magic_tag.magic_id
        WHERE magic.name = 'sea_serpent';

        IF magic_tag_count < 4 THEN
            RAISE EXCEPTION 'magic sea_serpent carries only % tags', magic_tag_count;
        END IF;
    END
$$;
