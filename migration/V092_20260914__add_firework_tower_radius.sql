-- Adds the firework_tower.radius row V082 left out. Without it, casting the firework tower
-- ends the match.
--
-- FireworkTowerPrefabInitializer.initialize builds the tower's body collider on its second
-- statement:
--
--     gameObject.addCollider(new CircleCollider(gameObject, params.floatValue(RADIUS), false));
--
-- ParameterService.getValue throws IllegalArgumentException for a row that does not exist
-- rather than returning a default, so initialization stops there and DummyMob,
-- FireworkLauncher, TimedSelfDestroyer and BuildingEffectReceiver are never added. The
-- exception then leaves ObjectsInfoDtoBuilder.createGameObject before the CreatedObjectDto is
-- recorded, so the client is never told the tower exists, and it reaches the per-frame catch in
-- GameLoop, which calls finalizeAfterFailure() and breaks the loop. The match ends.
--
-- V082's own assertion wrote the gap down as correct -- 'firework_tower has % parameter values,
-- expected 6' -- and the game server's FireworkTowerPrefabInitializerTest mocks RADIUS at 1.2f,
-- so neither side could report it. V082 has been applied to the dev database, so migration rule
-- 1 leaves this forward fix as the repair.
--
-- Value. radius here is the building's body, not the blast; the blast is firework_shell.radius
-- and V082 already holds that equal to firework_tower.attack_range. The siblings are
-- rock_turret 0.5, electric_tower 0.65, crater 0.75, dragon_tower 1.0 and ground_cannon 1.0.
-- 0.75 copies crater, which V082 already used as the source for firework_tower.hp: the other
-- Build structure that bombards a fixed spot. Written as a subquery for the same reason V082
-- wrote hp as one -- if crater's body is ever resized, a literal here would quietly stop
-- matching the object this tower was balanced against.
--
-- Client. FieldSelector draws the placement circle from
-- GameParameterResolver.TryGetMagicParameter(magic, "radius", ...). With no row it resolves to
-- 0 and the circle is drawn at zero radius; with this row the firework tower gets the same
-- placement circle every other build tower has. Unlike 'range', 'radius' has no cast type
-- family fallback in GetObjectNamesForParameter, so there is no build.radius to shadow it.
--
-- The assertion at the foot checks every parameter name FireworkTowerPrefabInitializer and
-- FireworkShellPrefabInitializer read, not just the one added here. A second missing row would
-- fail the same way this one did, and the count check V082 used cannot say which name is gone.

-- crater.radius is what this value is derived from. Fail before writing a NULL.
DO
$$
    BEGIN
        IF NOT EXISTS (SELECT 1
                       FROM parameter_values parameter_value
                                JOIN game_objects game_object
                                     ON game_object.id = parameter_value.game_object_id
                                JOIN parameters parameter
                                     ON parameter.id = parameter_value.parameter_id
                       WHERE game_object.name = 'crater'
                         AND parameter.name = 'radius'
                         AND parameter_value.value IS NOT NULL) THEN
            RAISE EXCEPTION 'crater.radius is missing; firework_tower.radius is derived from it';
        END IF;
    END
$$;

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT firework_tower.id, radius.id, crater_radius.value
FROM game_objects firework_tower
         JOIN parameters radius ON radius.name = 'radius'
         JOIN game_objects crater ON crater.name = 'crater'
         JOIN parameter_values crater_radius
              ON crater_radius.game_object_id = crater.id
                  AND crater_radius.parameter_id = radius.id
WHERE firework_tower.name = 'firework_tower'
ON CONFLICT (parameter_id, game_object_id)
    DO UPDATE SET value = EXCLUDED.value;

DO
$$
    DECLARE
        missing_parameter TEXT;
        tower_radius      DOUBLE PRECISION;
        crater_radius     DOUBLE PRECISION;
    BEGIN
        -- Every parameter name the two prefab initializers read. Each one is a thrown
        -- IllegalArgumentException on the game loop thread if its row is absent.
        SELECT required.game_object_name || '.' || required.parameter_name
        INTO missing_parameter
        FROM (VALUES ('firework_tower', 'mass'),
                     ('firework_tower', 'radius'),
                     ('firework_tower', 'hp'),
                     ('firework_tower', 'attack_interval'),
                     ('firework_tower', 'attack_offset'),
                     ('firework_tower', 'duration'),
                     ('firework_shell', 'radius'),
                     ('firework_shell', 'duration'),
                     ('firework_shell', 'damage')) AS required(game_object_name, parameter_name)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = required.game_object_name
                            AND parameter.name = required.parameter_name
                            AND parameter_value.value IS NOT NULL)
        ORDER BY 1
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'parameter % is missing; the prefab initializer throws and the match ends when the tower is cast',
                missing_parameter;
        END IF;

        SELECT parameter_value.value
        INTO tower_radius
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'firework_tower'
          AND parameter.name = 'radius';

        SELECT parameter_value.value
        INTO crater_radius
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'crater'
          AND parameter.name = 'radius';

        IF tower_radius IS NULL OR crater_radius IS NULL
            OR ABS(tower_radius - crater_radius) >= 1e-6 THEN
            RAISE EXCEPTION 'firework_tower radius is % but crater radius is %; they were meant to match',
                COALESCE(tower_radius::TEXT, '(none)'), COALESCE(crater_radius::TEXT, '(none)');
        END IF;
    END
$$;
