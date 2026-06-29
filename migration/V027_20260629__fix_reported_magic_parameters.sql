WITH required_game_objects AS (
    SELECT object_name
    FROM (
        VALUES
            ('tide_call'),
            ('towerback')
    ) AS required(object_name)
),
inserted_game_objects AS (
    INSERT INTO game_objects(name)
    SELECT object_name
    FROM required_game_objects required
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
    JOIN required_game_objects required ON required.object_name = go.name
),
required_parameters AS (
    SELECT parameter_name
    FROM (
        VALUES
            ('radius'),
            ('damage'),
            ('speed'),
            ('duration'),
            ('sub_attack_range')
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
            ('tide_call', 'radius', 0.8),
            ('tide_call', 'damage', 3.0),
            ('tide_call', 'speed', 4.5),
            ('tide_call', 'duration', 3.0),
            ('towerback', 'sub_attack_range', 1.15)
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
SET value = 5.0
FROM game_objects go, parameters p
WHERE pv.game_object_id = go.id
  AND pv.parameter_id = p.id
  AND go.name = 'dimension_toad'
  AND p.name = 'panic_duration';
