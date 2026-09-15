-- Two balance values changed after playing the build: dragon_tower reaches the far edge, and
-- repair_totem lives long enough to be worth placing.
--
-- dragon_tower.attack_range 8.0 -> 18.0
--   FlameLauncher uses this number twice: the box it scans ahead of the tower is attackRange long,
--   and the flame it fires is destroyed once it has flown attackRange. At 8 the tower covers less
--   than half of an arena GameConfig sizes 18 by 10, so a tower placed on its own side cannot reach
--   the other. 18 is that width, which means the lane spans the field from wherever it is built.
--   The aim indicator follows without another edit: V095 draws dragon_tower's lane with
--   {"object": "dragon_tower", "parameter": "attack_range"} as its length.
--
-- repair_totem.duration 6.0 -> 60.0
--   V079 registered the totem with the 6 seconds its sibling life_tree carries. The totem freezes
--   the lifetime of allied buildings around it, which is a slow effect measured against those
--   buildings' own durations - vine_colony 15, electric_tower 20, dragon_tower 20. Six seconds
--   expires before it has held anything for long. A minute is one to two building lifetimes, which
--   is the scale the effect works on.
--
-- Both statements resolve the row by name and leave a value that already matches alone, so a second
-- run changes nothing.

WITH configured(game_object_name, parameter_name, value) AS (VALUES
       ('dragon_tower', 'attack_range', 18.0),
       ('repair_totem', 'duration', 60.0)
)
UPDATE parameter_values parameter_value
SET value      = configured.value,
    updated_at = NOW()
FROM configured,
     game_objects game_object,
     parameters parameter
WHERE parameter_value.game_object_id = game_object.id
  AND parameter_value.parameter_id = parameter.id
  AND game_object.name = configured.game_object_name
  AND parameter.name = configured.parameter_name
  AND parameter_value.value IS DISTINCT FROM configured.value;

DO
$$
    DECLARE
        dragon_range    DOUBLE PRECISION;
        totem_duration  DOUBLE PRECISION;
    BEGIN
        SELECT parameter_value.value
        INTO dragon_range
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'dragon_tower'
          AND parameter.name = 'attack_range';

        SELECT parameter_value.value
        INTO totem_duration
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'repair_totem'
          AND parameter.name = 'duration';

        -- A missing row would leave these null rather than fail the UPDATE, and the game server
        -- throws on a missing parameter at cast time, which ends the match.
        IF dragon_range IS DISTINCT FROM 18.0 THEN
            RAISE EXCEPTION 'dragon_tower.attack_range is %, expected 18', COALESCE(dragon_range::TEXT, 'missing');
        END IF;

        IF totem_duration IS DISTINCT FROM 60.0 THEN
            RAISE EXCEPTION 'repair_totem.duration is %, expected 60', COALESCE(totem_duration::TEXT, 'missing');
        END IF;

        RAISE NOTICE 'dragon_tower reaches % and repair_totem lives % seconds', dragon_range, totem_duration;
    END
$$;
