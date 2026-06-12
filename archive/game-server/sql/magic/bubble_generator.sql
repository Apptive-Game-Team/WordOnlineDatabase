WITH inserted_magic AS (
    INSERT INTO magics(name)
    SELECT 'bubble_generator'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'bubble_generator'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'bubble_generator'
),
target_cards AS (
    SELECT id
    FROM cards
    WHERE name IN ('Water', 'Build')
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT tm.id, tc.id
FROM target_magic tm
CROSS JOIN target_cards tc
WHERE NOT EXISTS (
    SELECT 1
    FROM magic_cards mc
    WHERE mc.magic_id = tm.id
      AND mc.card_id = tc.id
);

WITH inserted_game_objects AS (
    INSERT INTO game_objects(name)
    SELECT object_name
    FROM (
        VALUES
            ('bubble_generator')
    ) AS required(object_name)
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects go
        WHERE go.name = required.object_name
    )
    RETURNING id, name
),
target_game_objects AS (
    SELECT id, name FROM inserted_game_objects
    UNION ALL
    SELECT go.id, go.name
    FROM game_objects go
    WHERE go.name IN ('bubble_generator')
),
required_parameters AS (
    SELECT parameter_name
    FROM (
        VALUES
            ('hp'),
            ('mass'),
            ('radius'),
            ('attack_range'),
            ('attack_interval'),
            ('duration')
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
            ('bubble_generator', 'hp', 18.0),
            ('bubble_generator', 'mass', 1000.0),
            ('bubble_generator', 'radius', 0.65),
            ('bubble_generator', 'attack_range', 4.0),
            ('bubble_generator', 'attack_interval', 1.2),
            ('bubble_generator', 'duration', 12.0)
    ) AS seed(game_object_name, parameter_name, parameter_value)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT tgo.id, tp.id, psv.parameter_value
FROM target_game_objects tgo
JOIN parameter_seed_values psv ON psv.game_object_name = tgo.name
JOIN target_parameters tp ON tp.name = psv.parameter_name
WHERE NOT EXISTS (
    SELECT 1
    FROM parameter_values pv
    WHERE pv.game_object_id = tgo.id
      AND pv.parameter_id = tp.id
);

UPDATE parameter_values pv
SET value = 2.5
FROM game_objects go, parameters p
WHERE pv.game_object_id = go.id
  AND pv.parameter_id = p.id
  AND go.name = 'bubble_generator'
  AND p.name = 'attack_range';
