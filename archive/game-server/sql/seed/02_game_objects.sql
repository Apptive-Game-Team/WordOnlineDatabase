INSERT INTO game_objects
VALUES
    (1, 'slime'),
    (2, 'shoot'),
    (3, 'explode'),
    (4, 'spawn'),
    (5, 'build'),
    (6, 'field');

SELECT setval('game_objects_id_seq', (SELECT MAX(id) FROM game_objects), true);
