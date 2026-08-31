-- The players stand at x = 1 and x = 17 (GameConfig.LEFT_PLAYER_POSITION and
-- GameConfig.RIGHT_PLAYER_POSITION), so they are 16 apart. A drop cast range of 18 let a caster
-- place the spell on top of the opposing player. 14 stops the reachable area 2 short of them.
UPDATE parameter_values pv
SET value = updates.value
FROM game_objects go
JOIN (
    VALUES
        ('drop', 'range', 14)
) AS updates(game_object_name, parameter_name, value)
    ON updates.game_object_name = go.name
JOIN parameters p
    ON p.name = updates.parameter_name
WHERE pv.game_object_id = go.id
  AND pv.parameter_id = p.id;
