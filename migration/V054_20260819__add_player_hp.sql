INSERT INTO game_objects(name)
VALUES ('player')
ON CONFLICT (name) DO NOTHING;

INSERT INTO parameters(name)
VALUES ('hp')
ON CONFLICT (name) DO NOTHING;

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 100
FROM game_objects go
JOIN parameters p ON p.name = 'hp'
WHERE go.name = 'player'
ON CONFLICT (parameter_id, game_object_id) DO NOTHING;
