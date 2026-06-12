WITH inserted_magic AS (
    INSERT INTO magics(name)
    SELECT 'zap_mouse'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'zap_mouse'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'zap_mouse'
),
target_cards AS (
    SELECT id
    FROM cards
    WHERE name IN ('Lightning', 'Spawn')
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

WITH inserted_game_object AS (
    INSERT INTO game_objects(name)
    SELECT 'zap_mouse'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'zap_mouse'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'zap_mouse'
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
            ('mass', 1.0),
            ('radius', 0.35),
            ('hp', 7.0),
            ('speed', 1.2),
            ('damage', 4.0),
            ('attack_interval', 0.8),
            ('detection_range', 6.0),
            ('panic_duration', 5.0)
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
