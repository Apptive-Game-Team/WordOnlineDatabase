-- DEV-30: the WaterSlime swarm spell must summon exactly 3 units, not 10.
-- Idempotent, id-agnostic: resolves game_objects/parameters by natural name and upserts,
-- so the row is inserted when absent and corrected when it already exists.
-- Scope is water_slime/quantity only; ember_spirit and seed_spirit keep quantity = 10.
INSERT INTO parameter_values(parameter_id, game_object_id, value)
SELECT p.id, go.id, 3
FROM game_objects go
JOIN parameters p ON p.name = 'quantity'
WHERE go.name = 'water_slime'
ON CONFLICT (parameter_id, game_object_id) DO UPDATE
    SET value = EXCLUDED.value;
