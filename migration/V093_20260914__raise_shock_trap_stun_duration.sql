-- Raises shock_trap's stun_duration from 2.0 to 10.0.
--
-- V078 seeded shock_trap as a repeating discharger: attack_interval 8.0 let it reload and fire
-- again, so stun_duration only needed to cover the gap between shocks. The game server made
-- shock_trap one-shot instead (Apptive-Game-Team/WordOnlineServer#559): once it discharges it is
-- spent, so the single stun it delivers is now the whole answer the trap gives, and 2.0 no longer
-- holds a caught target for long enough to matter. 10.0 is the value the balance pass chose for a
-- one-shot trap.
--
-- The same change also drops shock_trap's TimedSelfDestroyer, so the trap now stays on the field
-- until it discharges or is killed, like a landmine, instead of expiring on its own. That leaves
-- attack_interval and duration both deliberately in place even though the one-shot game server no
-- longer reads either. A migration that dropped either row could reach a database before the new
-- game server deploys, and ParameterService.getValue throws IllegalArgumentException on a missing
-- parameter, which would break shock_trap summoning on the old server in the meantime. Removing
-- attack_interval and duration is a follow-up once that deploy has gone out.

-- Records the value this migration was written against. A warning rather than an exception:
-- migration rule 3 requires the file to stay safe on a database that already holds 10.0.
DO
$$
    DECLARE
        current_stun_duration DOUBLE PRECISION;
    BEGIN
        SELECT parameter_value.value
        INTO current_stun_duration
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'shock_trap'
          AND parameter.name = 'stun_duration';

        IF current_stun_duration IS NULL THEN
            RAISE EXCEPTION 'shock_trap has no stun_duration value to raise';
        END IF;

        IF current_stun_duration <> 2.0 AND current_stun_duration <> 10.0 THEN
            RAISE WARNING 'shock_trap stun_duration was %, not the 2.0 this migration was written against; 10.0 was chosen from a 2.0 baseline',
                current_stun_duration;
        END IF;
    END
$$;

UPDATE parameter_values pv
SET value = updates.value
FROM game_objects go
JOIN (
    VALUES
        ('shock_trap', 'stun_duration', 10.0)
) AS updates(game_object_name, parameter_name, value)
    ON updates.game_object_name = go.name
JOIN parameters p
    ON p.name = updates.parameter_name
WHERE pv.game_object_id = go.id
  AND pv.parameter_id = p.id;

DO
$$
    DECLARE
        current_stun_duration DOUBLE PRECISION;
    BEGIN
        SELECT parameter_value.value
        INTO current_stun_duration
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'shock_trap'
          AND parameter.name = 'stun_duration';

        IF current_stun_duration IS DISTINCT FROM 10.0::DOUBLE PRECISION THEN
            RAISE EXCEPTION 'shock_trap stun_duration is %, expected 10.0',
                COALESCE(current_stun_duration::TEXT, '(none)');
        END IF;
    END
$$;
