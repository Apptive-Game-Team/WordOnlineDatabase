WITH inserted_magic AS (
    INSERT INTO magics(name)
    SELECT 'crater'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'crater'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'crater'
),
target_cards AS (
    SELECT id
    FROM cards
    WHERE name IN ('Fire', 'Build')
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
            ('crater'),
            ('crater_ember')
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
    WHERE go.name IN ('crater', 'crater_ember')
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
            ('duration'),
            ('damage')
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
            ('crater', 'hp', 15.0),
            ('crater', 'mass', 1000.0),
            ('crater', 'radius', 0.75),
            ('crater', 'attack_interval', 0.33333334),
            ('crater', 'duration', 8.0),
            ('crater_ember', 'radius', 0.35),
            ('crater_ember', 'attack_range', 1.5),
            ('crater_ember', 'damage', 3.0)
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
