WITH inserted_game_object AS (
    INSERT INTO game_objects(name)
    SELECT 'giant_vine'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'giant_vine'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'giant_vine'
),
required_parameters AS (
    SELECT parameter_name
    FROM (
        VALUES
            ('radius'),
            ('damage'),
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
            ('radius', 1.5),
            ('damage', 24.0),
            ('duration', 3.0)
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

WITH required_tags AS (
    SELECT tag_name
    FROM (
        VALUES
            ('TYPE_Unit'),
            ('CAT_Large'),
            ('CAT_AoE'),
            ('CAT_Building')
    ) AS tags(tag_name)
),
inserted_tags AS (
    INSERT INTO tags(name)
    SELECT tag_name
    FROM required_tags rt
    WHERE NOT EXISTS (
        SELECT 1
        FROM tags t
        WHERE t.name = rt.tag_name
    )
    RETURNING id, name
),
target_tags AS (
    SELECT id, name FROM inserted_tags
    UNION ALL
    SELECT t.id, t.name
    FROM tags t
    JOIN required_tags rt ON rt.tag_name = t.name
),
target_game_object AS (
    SELECT id
    FROM game_objects
    WHERE name = 'giant_vine'
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
