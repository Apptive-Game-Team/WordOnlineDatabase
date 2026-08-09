INSERT INTO parameter_values (game_object_id, parameter_id, value)
SELECT go.id, p.id, 3
FROM game_objects go
JOIN parameters p ON p.name = 'push_force'
WHERE go.name = 'wind_totem'
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;
