INSERT INTO parameters(name)
SELECT 'magic_id'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'magic_id'
);

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, m.id
FROM magics m
JOIN game_objects go ON go.name = m.name
JOIN parameters p ON p.name = 'magic_id'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameter_values pv
    WHERE pv.game_object_id = go.id
      AND pv.parameter_id = p.id
);
