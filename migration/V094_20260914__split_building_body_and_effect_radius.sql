-- Splits the one radius row that grass_generator, repair_totem and shock_trap use for two
-- different things. radius drops to the building's body, and the effect area moves to a new
-- effect_radius row carrying the value radius holds today.
--
-- The three buildings V078, V079 and V080 registered pass one radius value to both the body
-- collider and the effect component: the game server's prefab initializer hands the same number
-- to CircleCollider and to the component that reads the effect area, so a value large enough to
-- be a useful effect range is also the body. V092 already settled that radius is the building's
-- body when it took firework_tower's from crater. This applies that rule to the three buildings
-- left over.
--
-- Symptom in play. CombatRange.horizontalEdgeDistance on the game server measures reach between
-- the two collider edges rather than between centres:
--
--     Math.max(0d, centerDistance - radiusOf(source) - radiusOf(target))
--
-- A target's collider radius is subtracted from every attacker's reach. With radius 5.0, a melee
-- unit with attack_range 1.5 and body 0.5 reaches grass_generator from a centre distance of 7.0,
-- where a normal building at 0.65 holds the same unit to 2.65. The distance is not the only
-- problem: the collider is non-trigger with mass 1000000, so it is a solid disc 10 wide inside an
-- arena GameConfig sizes 18 by 10.
--
-- effect_radius values. The value radius holds today moves across unchanged, so no effect range
-- changes: grass_generator 5.0, repair_totem 4.0, shock_trap 3.0. These are literals rather than
-- a subquery reading radius. Step 2 below lowers radius, so a file that copied radius would write
-- the body value into effect_radius on a second run, and migration rule 3 requires this file to
-- stay safe on a database where it already ran. The three numbers are what V078, V079 and V080
-- seeded in world units; no migration has rescaled a radius row. V053 multiplied hp only.
--
-- radius values. Each one is taken with a subquery from the sibling that object's registration
-- migration already derived its hp from, the same reasoning V092 used for firework_tower and
-- crater. A literal here would quietly stop matching if a sibling's body were ever resized.
--
--   grass_generator <- vine_colony.radius     (1.0)
--   repair_totem    <- life_tree.radius       (0.5)
--   shock_trap      <- electric_tower.radius  (0.65)
--
-- effect_radius is already a name in the parameters table: bubble_generator carries one from the
-- V032 backfill, holding 4. The name is still inserted defensively, the way the registration
-- migrations do.
--
-- Leaf field load. V080 counts the slots GrassSpread fills as CEIL(radius / 1.75) * quantity and
-- refuses anything above 24, where 1.75 is GrassSpread.RING_SPACING on the game server. The
-- distance fields are scattered over is what moved to effect_radius, so that count is recomputed
-- here from effect_radius. Saying so matters because a later reader will find V080's copy of the
-- same arithmetic pointing at the body column instead. effect_radius 5.0 with quantity 6 gives 18
-- slots, still under the cap of 24.
--
-- The assertions in V078, V079 and V080 recorded the pre-split radius values and parameter
-- counts. Flyway does not re-run an applied migration and migration rule 1 forbids editing one,
-- so those three files stay as they are.
--
-- Deploy order. This migration goes out before the game server change
-- (Apptive-Game-Team/WordOnlineServer#562). In the window between the two, the old server reads
-- the lowered radius as its effect range as well, so the three buildings are briefly weaker. That
-- is a degradation, not a failure. The reverse order is not available: a new server reading a
-- database without the effect_radius rows reaches ParameterService.getValue, which throws
-- IllegalArgumentException on a missing row, and that exception reaches GameLoop's per-frame
-- catch and ends the match.
--
-- No game_objects row and no magics row is inserted, so the counter tag rules in README.md have
-- nothing to add to this file.

-- The three bodies are meaningless without their siblings' radius. Fail before writing a NULL.
DO
$$
    DECLARE
        missing_source TEXT;
    BEGIN
        SELECT body_source.source_name
        INTO missing_source
        FROM (VALUES ('vine_colony', 'grass_generator'),
                     ('life_tree', 'repair_totem'),
                     ('electric_tower', 'shock_trap')) AS body_source(source_name, target_name)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = body_source.source_name
                            AND parameter.name = 'radius'
                            AND parameter_value.value IS NOT NULL)
        ORDER BY 1
        LIMIT 1;

        IF missing_source IS NOT NULL THEN
            RAISE EXCEPTION '%.radius is missing; the three building bodies are derived from it',
                missing_source;
        END IF;
    END
$$;

-- Records the radius values this file was written against. A warning rather than an exception:
-- migration rule 3 requires the file to stay safe on a database where it already ran, and there
-- radius already holds the lowered body value.
DO
$$
    DECLARE
        baseline       RECORD;
        current_radius DOUBLE PRECISION;
        sibling_radius DOUBLE PRECISION;
    BEGIN
        FOR baseline IN
            SELECT *
            FROM (VALUES ('grass_generator', 5.0::DOUBLE PRECISION, 'vine_colony'),
                         ('repair_totem', 4.0, 'life_tree'),
                         ('shock_trap', 3.0, 'electric_tower'))
                     AS written_against(target_name, radius_before_split, source_name)
            LOOP
                SELECT parameter_value.value
                INTO current_radius
                FROM parameter_values parameter_value
                         JOIN game_objects game_object
                              ON game_object.id = parameter_value.game_object_id
                         JOIN parameters parameter
                              ON parameter.id = parameter_value.parameter_id
                WHERE game_object.name = baseline.target_name
                  AND parameter.name = 'radius';

                SELECT parameter_value.value
                INTO sibling_radius
                FROM parameter_values parameter_value
                         JOIN game_objects game_object
                              ON game_object.id = parameter_value.game_object_id
                         JOIN parameters parameter
                              ON parameter.id = parameter_value.parameter_id
                WHERE game_object.name = baseline.source_name
                  AND parameter.name = 'radius';

                IF current_radius IS NULL THEN
                    RAISE WARNING '% has no radius row; this file writes one from %.radius',
                        baseline.target_name, baseline.source_name;
                ELSIF current_radius <> baseline.radius_before_split
                    AND current_radius IS DISTINCT FROM sibling_radius THEN
                    RAISE WARNING '% radius is %, neither the % this file was written against nor the %.radius it is moving to; effect_radius still takes the literal %',
                        baseline.target_name, current_radius, baseline.radius_before_split,
                        baseline.source_name, baseline.radius_before_split;
                END IF;
            END LOOP;
    END
$$;

-- Step 1. Add the effect_radius rows. bubble_generator already uses the name, but it is inserted
-- first anyway, the way the registration migrations do, for a database that lacks it.
INSERT INTO parameters(name)
SELECT 'effect_radius'
WHERE NOT EXISTS (SELECT 1
                  FROM parameters
                  WHERE name = 'effect_radius');

INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, effect_radius.id, seed.value
FROM (VALUES ('grass_generator', 5.0::DOUBLE PRECISION),
             ('repair_totem', 4.0),
             ('shock_trap', 3.0)) AS seed(game_object_name, value)
         JOIN game_objects game_object ON game_object.name = seed.game_object_name
         JOIN parameters effect_radius ON effect_radius.name = 'effect_radius'
ON CONFLICT (parameter_id, game_object_id)
    DO UPDATE SET value = EXCLUDED.value;

-- Step 2. Lower radius to the sibling's body value. Written as an insert with ON CONFLICT rather
-- than an update so that a database missing the radius row ends in the same state.
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT target_object.id, radius.id, sibling_value.value
FROM (VALUES ('grass_generator', 'vine_colony'),
             ('repair_totem', 'life_tree'),
             ('shock_trap', 'electric_tower')) AS body_source(target_name, source_name)
         JOIN game_objects target_object ON target_object.name = body_source.target_name
         JOIN game_objects source_object ON source_object.name = body_source.source_name
         JOIN parameters radius ON radius.name = 'radius'
         JOIN parameter_values sibling_value
              ON sibling_value.game_object_id = source_object.id
                  AND sibling_value.parameter_id = radius.id
ON CONFLICT (parameter_id, game_object_id)
    DO UPDATE SET value = EXCLUDED.value;

DO
$$
    DECLARE
        expected                RECORD;
        body_radius             DOUBLE PRECISION;
        sibling_radius          DOUBLE PRECISION;
        area_radius             DOUBLE PRECISION;
        generator_area_radius   DOUBLE PRECISION;
        generator_quantity      DOUBLE PRECISION;
        slot_count              DOUBLE PRECISION;
    BEGIN
        FOR expected IN
            SELECT *
            FROM (VALUES ('grass_generator', 'vine_colony', 5.0::DOUBLE PRECISION),
                         ('repair_totem', 'life_tree', 4.0),
                         ('shock_trap', 'electric_tower', 3.0))
                     AS split(target_name, source_name, effect_radius_after_split)
            LOOP
                SELECT parameter_value.value
                INTO body_radius
                FROM parameter_values parameter_value
                         JOIN game_objects game_object
                              ON game_object.id = parameter_value.game_object_id
                         JOIN parameters parameter
                              ON parameter.id = parameter_value.parameter_id
                WHERE game_object.name = expected.target_name
                  AND parameter.name = 'radius';

                SELECT parameter_value.value
                INTO sibling_radius
                FROM parameter_values parameter_value
                         JOIN game_objects game_object
                              ON game_object.id = parameter_value.game_object_id
                         JOIN parameters parameter
                              ON parameter.id = parameter_value.parameter_id
                WHERE game_object.name = expected.source_name
                  AND parameter.name = 'radius';

                SELECT parameter_value.value
                INTO area_radius
                FROM parameter_values parameter_value
                         JOIN game_objects game_object
                              ON game_object.id = parameter_value.game_object_id
                         JOIN parameters parameter
                              ON parameter.id = parameter_value.parameter_id
                WHERE game_object.name = expected.target_name
                  AND parameter.name = 'effect_radius';

                IF body_radius IS NULL THEN
                    RAISE EXCEPTION '% has no radius value; the prefab initializer throws and the match ends when it is cast',
                        expected.target_name;
                END IF;

                IF area_radius IS NULL THEN
                    RAISE EXCEPTION '% has no effect_radius value; the new game server throws on it and the match ends',
                        expected.target_name;
                END IF;

                IF sibling_radius IS NULL OR ABS(body_radius - sibling_radius) >= 1e-6 THEN
                    RAISE EXCEPTION '% radius is % but %.radius is %; the body was meant to match',
                        expected.target_name, body_radius, expected.source_name,
                        COALESCE(sibling_radius::TEXT, '(none)');
                END IF;

                IF ABS(area_radius - expected.effect_radius_after_split) >= 1e-6 THEN
                    RAISE EXCEPTION '% effect_radius is %, expected %; the effect area was meant to carry the value radius held before the split',
                        expected.target_name, area_radius, expected.effect_radius_after_split;
                END IF;
            END LOOP;

        -- Recounts V080's leaf field cap against the new parameter. GrassSpread fills
        -- CEIL(effect_radius / RING_SPACING) * quantity slots and plants one leaf field in each.
        -- 1.75 is GrassSpread.RING_SPACING on the game server, so keep the two in sync if that
        -- constant ever moves. V080 ran the same arithmetic on radius; the distance fields are
        -- scattered over now lives in effect_radius, so this column sets the cap.
        SELECT parameter_value.value
        INTO generator_area_radius
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'grass_generator'
          AND parameter.name = 'effect_radius';

        SELECT parameter_value.value
        INTO generator_quantity
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'grass_generator'
          AND parameter.name = 'quantity';

        IF generator_area_radius IS NOT NULL AND generator_quantity IS NOT NULL THEN
            slot_count := CEIL(generator_area_radius / 1.75) * generator_quantity;

            IF slot_count > 24 THEN
                RAISE EXCEPTION 'grass_generator would hold % leaf fields at once (effect_radius %, quantity %); lower effect_radius or quantity',
                    slot_count, generator_area_radius, generator_quantity;
            END IF;
        END IF;
    END
$$;
