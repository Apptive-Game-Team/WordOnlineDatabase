INSERT INTO cards(id, name, card_type)
VALUES
    (1, 'Fire', 'Type'),
    (2, 'Water', 'Type'),
    (3, 'Lightning', 'Type'),
    (4, 'Rock', 'Type'),
    (5, 'Nature', 'Type'),
    (6, 'Shoot', 'Magic'),
    (7, 'Build', 'Magic'),
    (8, 'Spawn', 'Magic'),
    (9, 'Explode', 'Magic'),
    (10, 'Wind', 'Type'),
    (11, 'Drop', 'Magic')
ON CONFLICT (id) DO NOTHING;

INSERT INTO game_objects(name)
SELECT object_name
FROM (
    VALUES
        ('slime'),
        ('shoot'),
        ('explode'),
        ('spawn'),
        ('build'),
        ('field')
) AS core_objects(object_name)
ON CONFLICT (name) DO NOTHING;

INSERT INTO parameters(name)
SELECT parameter_name
FROM (
    VALUES
        ('speed'),
        ('damage'),
        ('radius'),
        ('hp'),
        ('mass'),
        ('duration'),
        ('magic_id')
) AS core_parameters(parameter_name)
ON CONFLICT (name) DO NOTHING;

WITH core_values(game_object_name, parameter_name, value) AS (
    VALUES
        ('slime', 'radius', 0.5),
        ('shoot', 'radius', 0.5),
        ('explode', 'radius', 0.5),
        ('build', 'radius', 0.5),
        ('field', 'radius', 0.5),
        ('slime', 'damage', 3.0),
        ('shoot', 'damage', 10.0),
        ('explode', 'damage', 8.0),
        ('slime', 'hp', 8.0),
        ('build', 'hp', 5.0),
        ('slime', 'speed', 0.8),
        ('slime', 'mass', 1.0),
        ('field', 'duration', 3.0)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, cv.value
FROM core_values cv
JOIN game_objects go ON go.name = cv.game_object_name
JOIN parameters p ON p.name = cv.parameter_name
ON CONFLICT (parameter_id, game_object_id) DO NOTHING;
