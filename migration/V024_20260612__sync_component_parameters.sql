INSERT INTO parameters(name)
SELECT 'fall_gravity'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'fall_gravity'
);

INSERT INTO parameters(name)
SELECT 'push_force'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'push_force'
);

INSERT INTO parameters(name)
SELECT 'push_range_x'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'push_range_x'
);

INSERT INTO parameters(name)
SELECT 'push_range_y'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'push_range_y'
);

INSERT INTO parameters(name)
SELECT 'spawn_height'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'spawn_height'
);

INSERT INTO parameters(name)
SELECT 'vine_count'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'vine_count'
);

INSERT INTO parameters(name)
SELECT 'vine_spacing'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'vine_spacing'
);

INSERT INTO parameters(name)
SELECT 'vine_spawn_interval'
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters
    WHERE name = 'vine_spawn_interval'
);

INSERT INTO game_objects(name)
SELECT 'chicken_commando'
WHERE NOT EXISTS (
    SELECT 1
    FROM game_objects
    WHERE name = 'chicken_commando'
);

INSERT INTO game_objects(name)
SELECT 'wind_totem'
WHERE NOT EXISTS (
    SELECT 1
    FROM game_objects
    WHERE name = 'wind_totem'
);

INSERT INTO game_objects(name)
SELECT 'vine_toss'
WHERE NOT EXISTS (
    SELECT 1
    FROM game_objects
    WHERE name = 'vine_toss'
);

INSERT INTO game_objects(name)
SELECT 'fire_tadpole'
WHERE NOT EXISTS (
    SELECT 1
    FROM game_objects
    WHERE name = 'fire_tadpole'
);

INSERT INTO game_objects(name)
SELECT 'lightning_tadpole'
WHERE NOT EXISTS (
    SELECT 1
    FROM game_objects
    WHERE name = 'lightning_tadpole'
);

INSERT INTO game_objects(name)
SELECT 'vine_colony'
WHERE NOT EXISTS (
    SELECT 1
    FROM game_objects
    WHERE name = 'vine_colony'
);

INSERT INTO game_objects(name)
SELECT 'ground_tower'
WHERE NOT EXISTS (
    SELECT 1
    FROM game_objects
    WHERE name = 'ground_tower'
);

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 3
FROM game_objects go
JOIN parameters p ON p.name = 'fall_gravity'
WHERE go.name = 'chicken_commando'
  AND NOT EXISTS (
      SELECT 1
      FROM parameter_values pv
      WHERE pv.game_object_id = go.id
        AND pv.parameter_id = p.id
  );

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 10
FROM game_objects go
JOIN parameters p ON p.name = 'spawn_height'
WHERE go.name = 'chicken_commando'
  AND NOT EXISTS (
      SELECT 1
      FROM parameter_values pv
      WHERE pv.game_object_id = go.id
        AND pv.parameter_id = p.id
  );

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 10
FROM game_objects go
JOIN parameters p ON p.name = 'push_force'
WHERE go.name = 'wind_totem'
  AND NOT EXISTS (
      SELECT 1
      FROM parameter_values pv
      WHERE pv.game_object_id = go.id
        AND pv.parameter_id = p.id
  );

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 6
FROM game_objects go
JOIN parameters p ON p.name = 'push_range_x'
WHERE go.name = 'wind_totem'
  AND NOT EXISTS (
      SELECT 1
      FROM parameter_values pv
      WHERE pv.game_object_id = go.id
        AND pv.parameter_id = p.id
  );

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 3
FROM game_objects go
JOIN parameters p ON p.name = 'push_range_y'
WHERE go.name = 'wind_totem'
  AND NOT EXISTS (
      SELECT 1
      FROM parameter_values pv
      WHERE pv.game_object_id = go.id
        AND pv.parameter_id = p.id
  );

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 6
FROM game_objects go
JOIN parameters p ON p.name = 'vine_count'
WHERE go.name = 'vine_toss'
  AND NOT EXISTS (
      SELECT 1
      FROM parameter_values pv
      WHERE pv.game_object_id = go.id
        AND pv.parameter_id = p.id
  );

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 1
FROM game_objects go
JOIN parameters p ON p.name = 'vine_spacing'
WHERE go.name = 'vine_toss'
  AND NOT EXISTS (
      SELECT 1
      FROM parameter_values pv
      WHERE pv.game_object_id = go.id
        AND pv.parameter_id = p.id
  );

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 0.12
FROM game_objects go
JOIN parameters p ON p.name = 'vine_spawn_interval'
WHERE go.name = 'vine_toss'
  AND NOT EXISTS (
      SELECT 1
      FROM parameter_values pv
      WHERE pv.game_object_id = go.id
        AND pv.parameter_id = p.id
  );

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 10
FROM game_objects go
JOIN parameters p ON p.name = 'duration'
WHERE go.name IN ('fire_tadpole', 'lightning_tadpole')
  AND NOT EXISTS (
      SELECT 1
      FROM parameter_values pv
      WHERE pv.game_object_id = go.id
        AND pv.parameter_id = p.id
  );

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT go.id, p.id, 60
FROM game_objects go
JOIN parameters p ON p.name = 'duration'
WHERE go.name IN ('vine_colony', 'ground_tower')
  AND NOT EXISTS (
      SELECT 1
      FROM parameter_values pv
      WHERE pv.game_object_id = go.id
        AND pv.parameter_id = p.id
  );
