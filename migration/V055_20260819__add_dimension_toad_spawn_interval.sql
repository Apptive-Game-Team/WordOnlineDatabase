INSERT INTO game_objects(name)
VALUES ('dimension_toad')
ON CONFLICT (name) DO NOTHING;

INSERT INTO parameters(name)
VALUES ('spawn_interval')
ON CONFLICT (name) DO NOTHING;

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 5
FROM game_objects go
JOIN parameters p ON p.name = 'spawn_interval'
WHERE go.name = 'dimension_toad'
ON CONFLICT (parameter_id, game_object_id) DO UPDATE SET value = EXCLUDED.value;
