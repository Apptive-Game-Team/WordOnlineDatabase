WITH inserted_magic AS (
    INSERT INTO magics(name)
    SELECT 'dimension_toad'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'dimension_toad'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'dimension_toad'
),
recipe_cards AS (
    SELECT *
    FROM (
        VALUES
            ('Fire', 1),
            ('Lightning', 1),
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
    SELECT 'dimension_toad'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'dimension_toad'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'dimension_toad'
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
            ('detection_range'),
            ('panic_duration')
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
            ('mass', 2.2),
            ('radius', 0.65),
            ('hp', 32.0),
            ('speed', 0.65),
            ('damage', 5.0),
            ('attack_interval', 1.1),
            ('detection_range', 5.5),
            ('panic_duration', 4.0)
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

WITH tadpole_seed AS (
    SELECT *
    FROM (
        VALUES
            ('fire_tadpole', 'mass', 0.8),
            ('fire_tadpole', 'radius', 0.3),
            ('fire_tadpole', 'hp', 7.0),
            ('fire_tadpole', 'speed', 1.15),
            ('fire_tadpole', 'damage', 3.0),
            ('fire_tadpole', 'attack_interval', 0.8),
            ('fire_tadpole', 'detection_range', 4.5),
            ('fire_tadpole', 'panic_duration', 3.0),
            ('lightning_tadpole', 'mass', 0.75),
            ('lightning_tadpole', 'radius', 0.3),
            ('lightning_tadpole', 'hp', 6.0),
            ('lightning_tadpole', 'speed', 1.25),
            ('lightning_tadpole', 'damage', 3.0),
            ('lightning_tadpole', 'attack_interval', 0.7),
            ('lightning_tadpole', 'detection_range', 5.0),
            ('lightning_tadpole', 'panic_duration', 3.5)
    ) AS seed(game_object_name, parameter_name, parameter_value)
),
required_game_objects AS (
    SELECT DISTINCT game_object_name
    FROM tadpole_seed
),
inserted_game_objects AS (
    INSERT INTO game_objects(name)
    SELECT game_object_name
    FROM required_game_objects rgo
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects go
        WHERE go.name = rgo.game_object_name
    )
    RETURNING id, name
),
target_game_objects AS (
    SELECT id, name FROM inserted_game_objects
    UNION ALL
    SELECT go.id, go.name
    FROM game_objects go
    JOIN required_game_objects rgo ON rgo.game_object_name = go.name
),
required_parameters AS (
    SELECT DISTINCT parameter_name
    FROM tadpole_seed
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
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT tgo.id, tp.id, ts.parameter_value
FROM tadpole_seed ts
JOIN target_game_objects tgo ON tgo.name = ts.game_object_name
JOIN target_parameters tp ON tp.name = ts.parameter_name
WHERE NOT EXISTS (
    SELECT 1
    FROM parameter_values pv
    WHERE pv.game_object_id = tgo.id
      AND pv.parameter_id = tp.id
);
