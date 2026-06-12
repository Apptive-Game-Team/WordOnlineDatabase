WITH inserted_magic AS (
    INSERT INTO magics(name)
    SELECT 'fire_lord_spirit'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'fire_lord_spirit'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'fire_lord_spirit'
),
recipe_cards AS (
    SELECT *
    FROM (
        VALUES
            ('Fire', 1),
            ('Wind', 1),
            ('Spawn', 2)
    ) AS recipe(card_name, required_count)
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
    SELECT 'fire_lord_spirit'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'fire_lord_spirit'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'fire_lord_spirit'
),
required_parameters AS (
    SELECT parameter_name
    FROM (
        VALUES
            ('mass'),
            ('radius'),
            ('hp'),
            ('speed'),
            ('damage'),
            ('attack_interval')
    ) AS params(parameter_name)
),
inserted_parameters AS (
    INSERT INTO parameters(name)
    SELECT parameter_name
    FROM required_parameters rp
    WHERE NOT EXISTS (
        SELECT 1
        FROM parameters p
        WHERE p.name = rp.parameter_name
    )
    RETURNING id, name
),
target_parameters AS (
    SELECT id, name FROM inserted_parameters
    UNION ALL
    SELECT p.id, p.name
    FROM parameters p
    JOIN required_parameters rp ON rp.parameter_name = p.name
),
parameter_seed_values AS (
    SELECT *
    FROM (
        VALUES
            ('mass', 3.0),
            ('radius', 0.9),
            ('hp', 45.0),
            ('speed', 0.45),
            ('damage', 8.0),
            ('attack_interval', 1.6)
    ) AS seed(parameter_name, parameter_value)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT tgo.id, tp.id, psv.parameter_value
FROM target_game_object tgo
JOIN target_parameters tp ON TRUE
JOIN parameter_seed_values psv ON psv.parameter_name = tp.name
WHERE NOT EXISTS (
    SELECT 1
    FROM parameter_values pv
    WHERE pv.game_object_id = tgo.id
      AND pv.parameter_id = tp.id
);

WITH inserted_game_object AS (
    INSERT INTO game_objects(name)
    SELECT 'fire_child_spirit'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'fire_child_spirit'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'fire_child_spirit'
),
required_parameters AS (
    SELECT parameter_name
    FROM (
        VALUES
            ('mass'),
            ('radius'),
            ('hp'),
            ('speed'),
            ('damage'),
            ('attack_interval'),
            ('attack_range')
    ) AS params(parameter_name)
),
inserted_parameters AS (
    INSERT INTO parameters(name)
    SELECT parameter_name
    FROM required_parameters rp
    WHERE NOT EXISTS (
        SELECT 1
        FROM parameters p
        WHERE p.name = rp.parameter_name
    )
    RETURNING id, name
),
target_parameters AS (
    SELECT id, name FROM inserted_parameters
    UNION ALL
    SELECT p.id, p.name
    FROM parameters p
    JOIN required_parameters rp ON rp.parameter_name = p.name
),
parameter_seed_values AS (
    SELECT *
    FROM (
        VALUES
            ('mass', 1.0),
            ('radius', 0.35),
            ('hp', 9.0),
            ('speed', 0.8),
            ('damage', 4.0),
            ('attack_interval', 1.0),
            ('attack_range', 4.0)
    ) AS seed(parameter_name, parameter_value)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT tgo.id, tp.id, psv.parameter_value
FROM target_game_object tgo
JOIN target_parameters tp ON TRUE
JOIN parameter_seed_values psv ON psv.parameter_name = tp.name
WHERE NOT EXISTS (
    SELECT 1
    FROM parameter_values pv
    WHERE pv.game_object_id = tgo.id
      AND pv.parameter_id = tp.id
);
