-- Rock turret previously used its HP value of 15 as its lifetime. Keep that
-- lifetime while making duration an explicit database parameter. Vine colony
-- receives the same value through its own duration parameter below.
INSERT INTO parameter_values (parameter_id, game_object_id, value)
SELECT p.id, go.id, 15
FROM parameters p
JOIN game_objects go ON go.name = 'rock_turret'
WHERE p.name = 'duration'
ON CONFLICT (parameter_id, game_object_id) DO UPDATE
SET value = EXCLUDED.value;

INSERT INTO parameter_values (parameter_id, game_object_id, value)
SELECT vine_duration.id, vine_colony.id, rock_duration_value.value
FROM parameters vine_duration
JOIN game_objects vine_colony ON vine_colony.name = 'vine_colony'
JOIN parameters rock_duration ON rock_duration.name = 'duration'
JOIN game_objects rock_turret ON rock_turret.name = 'rock_turret'
JOIN parameter_values rock_duration_value
    ON rock_duration_value.parameter_id = rock_duration.id
   AND rock_duration_value.game_object_id = rock_turret.id
WHERE vine_duration.name = 'duration'
ON CONFLICT (parameter_id, game_object_id) DO UPDATE
SET value = EXCLUDED.value;
