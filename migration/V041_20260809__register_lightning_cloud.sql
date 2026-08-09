WITH inserted_game_object AS (
    INSERT INTO game_objects(name)
    SELECT 'lightning_cloud'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'lightning_cloud'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'lightning_cloud'
),
required_parameters(name) AS (
    VALUES
        ('attack_interval'),
        ('quantity')
),
inserted_parameters AS (
    INSERT INTO parameters(name)
    SELECT rp.name
    FROM required_parameters rp
    WHERE NOT EXISTS (
        SELECT 1
        FROM parameters p
        WHERE p.name = rp.name
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
cloud_values(parameter_name, value) AS (
    VALUES
        ('attack_interval', 2.0),
        ('quantity', 3.0)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT tgo.id, tp.id, cv.value
FROM target_game_object tgo
JOIN target_parameters tp ON TRUE
JOIN cloud_values cv ON cv.parameter_name = tp.name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(name) AS (
    VALUES
        ('TYPE_Unit'),
        ('CAT_AoE')
),
inserted_tags AS (
    INSERT INTO tags(name)
    SELECT rt.name
    FROM required_tags rt
    WHERE NOT EXISTS (
        SELECT 1
        FROM tags t
        WHERE t.name = rt.name
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
    SELECT id
    FROM game_objects
    WHERE name = 'lightning_cloud'
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
