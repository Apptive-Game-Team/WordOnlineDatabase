INSERT INTO parameters
VALUES
    (1, 'speed'),
    (2, 'damage'),
    (3, 'radius'),
    (4, 'hp'),
    (5, 'mass'),
    (6, 'duration'),
    (7, 'magic_id');

SELECT setval('parameters_id_seq', (SELECT MAX(id) FROM parameters), true);
