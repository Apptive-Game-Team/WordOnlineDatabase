INSERT INTO parameters(name)
SELECT 'quantity'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'quantity'
);

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 2
FROM game_objects go
CROSS JOIN parameters p
WHERE go.name IN ('zap_mouse', 'vine_spirit')
  AND p.name = 'quantity'
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;
