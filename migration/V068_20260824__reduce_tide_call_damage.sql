-- tide_call (PushShot) is not consumed on contact: it travels for its whole duration, damaging
-- every enemy it passes through once and pushing each of them, and it drops a water field along
-- the path. Its damage was seeded at 3.0 in V027 and then raised to 4 by the V032 backfill. 1
-- leaves the push, the wet effect and the field as the reason to cast it.
UPDATE parameter_values pv
SET value = updates.value
FROM game_objects go
JOIN (
    VALUES
        ('tide_call', 'damage', 1)
) AS updates(game_object_name, parameter_name, value)
    ON updates.game_object_name = go.name
JOIN parameters p
    ON p.name = updates.parameter_name
WHERE pv.game_object_id = go.id
  AND pv.parameter_id = p.id;
