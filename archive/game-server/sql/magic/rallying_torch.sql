WITH inserted_magic AS (
    INSERT INTO magics(name)
    SELECT 'rallying_torch'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'rallying_torch'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'rallying_torch'
),
target_cards AS (
    SELECT id
    FROM cards
    WHERE name IN ('Fire', 'Drop')
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
    SELECT 'rallying_torch'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'rallying_torch'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'rallying_torch'
),
required_parameters AS (
    SELECT parameter_name
    FROM (
        VALUES
            ('radius'),
            ('duration'),
            ('buff_duration')
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
            ('radius', 0.6),
            ('duration', 10.0),
            ('buff_duration', 10.0)
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
