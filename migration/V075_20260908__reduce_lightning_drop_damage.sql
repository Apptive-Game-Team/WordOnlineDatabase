-- Lowers lightning_drop damage from 80 to 30.
--
-- LightningDropMagic spawns one PrefabType.LightningCloud. LightningCloudPrefabInitializer reads
-- only lightning_cloud's attack_interval and quantity, and lightning_cloud carries no damage row
-- at all. The cloud then drops quantity PrefabType.LightningDrop instances, and
-- LightningDropPrefabInitializer reads lightning_drop's damage and radius to build the
-- LightningStrike that applies the AttackInfo. So the single row below is the whole change; no
-- damage constant is hardcoded in the game server.
--
-- 30 is a target the balance pass chose, not a multiple of anything, so it is written as a
-- literal rather than derived from a sibling object.
--
-- Scale note. This repository's V032 backfill seeds ('lightning_drop','damage',8) and V053
-- multiplied every hp and %damage% row by 10, which is where the live 80 comes from. The
-- reconstruction is not reliable in general -- magma_spirit's hp is 2000 live where the same
-- arithmetic predicts 2500 -- so the pre-check below reports the value it actually finds instead
-- of assuming it.
--
-- lightning_cloud's attack_interval of 2.0 and quantity of 3.0 decide how often and how many
-- times lightning falls; neither is touched here. Three strikes per cast means the effective
-- damage per cast falls from 240 to 90.

-- Records the value this migration was written against. A warning rather than an exception:
-- migration rule 3 requires the file to stay safe on a database that already holds 30.
DO
$$
    DECLARE
        current_damage DOUBLE PRECISION;
    BEGIN
        SELECT parameter_value.value
        INTO current_damage
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'lightning_drop'
          AND parameter.name = 'damage';

        IF current_damage IS NULL THEN
            RAISE EXCEPTION 'lightning_drop has no damage value to lower';
        END IF;

        IF current_damage <> 80 AND current_damage <> 30 THEN
            RAISE WARNING 'lightning_drop damage was %, not the 80 this migration was written against; 30 was chosen from an 80 baseline',
                current_damage;
        END IF;
    END
$$;

UPDATE parameter_values pv
SET value = updates.value
FROM game_objects go
JOIN (
    VALUES
        ('lightning_drop', 'damage', 30)
) AS updates(game_object_name, parameter_name, value)
    ON updates.game_object_name = go.name
JOIN parameters p
    ON p.name = updates.parameter_name
WHERE pv.game_object_id = go.id
  AND pv.parameter_id = p.id;

DO
$$
    DECLARE
        current_damage DOUBLE PRECISION;
    BEGIN
        SELECT parameter_value.value
        INTO current_damage
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'lightning_drop'
          AND parameter.name = 'damage';

        IF current_damage IS DISTINCT FROM 30::DOUBLE PRECISION THEN
            RAISE EXCEPTION 'lightning_drop damage is %, expected 30',
                COALESCE(current_damage::TEXT, '(none)');
        END IF;
    END
$$;
