INSERT INTO game_objects(name)
SELECT m.name
FROM magics m
WHERE NOT EXISTS (
    SELECT 1
    FROM game_objects go
    WHERE go.name = m.name
);
