-- Gives a game object the name of the prefab it is.
--
-- The game server picks what to build from a PrefabType enum value, and a magic reaches that value
-- only through the Java class written for it: AquaArcherMagic holds PrefabType.AquaArcher and
-- nothing in the database says so. Issue #155 moves that fact into data, and this column is the
-- half of it that belongs to the object: game object `aqua_archer` is `PrefabType.AquaArcher`.
--
-- The value is the enum constant, not the prefab bean name behind it. The two are not
-- interchangeable: PrefabType.EmberSpirit and PrefabType.FireSlime both carry the bean name
-- "fire_slime_prefab", so a bean name cannot say which of the two a magic means while the enum
-- constant can. The client spawns by that same enum name, so this is the one identifier the game
-- server and the client already agree on.
--
-- Nullable on purpose. Most game objects are not prefabs at all - `shoot`, `build` and `spawn` hold
-- the cast values a whole family shares, `game` holds match settings - and a row that is not a
-- prefab has nothing true to put here. Only the 67 objects the data-driven magics build are filled.
-- Projectiles and sub-prefabs (dragon_flame, crater_ember, titan_fist) stay empty until something
-- needs them; their prefab is chosen inside an initializer, never from a magic row.
--
-- The pairs come from reading the game server's magic classes: the PrefabType a class hands to its
-- Abstract*Magic constructor, against the GameObjectKey the matching prefab initializer reads
-- parameters from. That is what makes `ember_spirit` - where that magic's quantity lives - rather
-- than `fire_slime` the row that carries EmberSpirit.

ALTER TABLE game_objects
    ADD COLUMN IF NOT EXISTS prefab VARCHAR(63);

WITH configured(object_name, prefab) AS (VALUES
       ('aqua_archer', 'AquaArcher'),
       ('bomb_sprite', 'BombSprite'),
       ('boulder_strike', 'BoulderStrike'),
       ('bubble_generator', 'BubbleGenerator'),
       ('bubble_spirit', 'BubbleSpirit'),
       ('chain_lightning', 'ChainLightning'),
       ('cloud_dragon', 'CloudDragon'),
       ('crater', 'Crater'),
       ('dimension_toad', 'DimensionToad'),
       ('dragon_tower', 'DragonTower'),
       ('electric_explode', 'ElectricExplode'),
       ('electric_shot', 'ElectricShot'),
       ('electric_tower', 'ElectricTower'),
       ('ember_spirit', 'EmberSpirit'),
       ('evil_ent', 'EvilEnt'),
       ('fire_lord_spirit', 'FireLordSpirit'),
       ('fire_shot', 'FireShot'),
       ('fire_spirit', 'FireSpirit'),
       ('fire_summon', 'FireSummon'),
       ('firework_tower', 'FireworkTower'),
       ('frenzy_totem', 'FrenzyTotem'),
       ('grass_generator', 'GrassGenerator'),
       ('ground_cannon', 'GroundCannon'),
       ('ground_tower', 'GroundTower'),
       ('healing_totem', 'HealingTotem'),
       ('leaf_drop', 'Leafair'),
       ('life_tree', 'LifeTree'),
       ('lightning_cloud', 'LightningCloud'),
       ('magma_explosion', 'MagmaExplosion'),
       ('magma_spirit', 'MagmaSpirit'),
       ('mana_well', 'ManaWell'),
       ('meteor_shower', 'MeteorShower'),
       ('mini_rock', 'MiniRock'),
       ('overgrowth', 'Overgrowth'),
       ('rallying_totem', 'RallyingTotem'),
       ('razor_gale', 'RazorGale'),
       ('repair_totem', 'RepairTotem'),
       ('rock_drop', 'RockDrop'),
       ('rock_golem', 'RockGolem'),
       ('rock_mage', 'RockMage'),
       ('rock_rolling', 'RockRolling'),
       ('rock_turret', 'RockTurret'),
       ('sand_storm', 'SandStorm'),
       ('sea_serpent', 'SeaSerpent'),
       ('seed_nest', 'SeedNest'),
       ('seed_spirit', 'SeedSpirit'),
       ('shock_overload', 'ShockOverload'),
       ('shock_trap', 'ShockTrap'),
       ('storm_rider', 'StormRider'),
       ('storm_stag', 'StormStag'),
       ('thunder_bird', 'ThunderBird'),
       ('thunder_spirit', 'ThunderSpirit'),
       ('tide_call', 'TideCall'),
       ('titan_remnant', 'TitanRemnant'),
       ('tornado_strike', 'TornadoStrike'),
       ('towerback', 'Towerback'),
       ('tree_golem', 'TreeGolem'),
       ('vine_colony', 'VineColony'),
       ('vine_spirit', 'VineSpirit'),
       ('wall_golem', 'WallGolem'),
       ('water_explosion', 'WaterExplosion'),
       ('water_shot', 'WaterShot'),
       ('water_slime', 'WaterSlime'),
       ('wind_blade', 'WindBlade'),
       ('wind_spirit', 'WindSpirit'),
       ('wind_totem', 'WindTotem'),
       ('zap_mouse', 'ZapMouse')
)
UPDATE game_objects game_object
SET prefab = configured.prefab
FROM configured
WHERE game_object.name = configured.object_name
  AND game_object.prefab IS DISTINCT FROM configured.prefab;

DO
$$
    DECLARE
        missing_objects TEXT;
        filled_count    INTEGER;
    BEGIN
        -- A name that matches no game object writes nothing and says nothing, which is how a typo
        -- would ship. Every name in the list was read off this database's game_objects table.
        SELECT COALESCE(STRING_AGG(configured.object_name, ', ' ORDER BY configured.object_name), '')
        INTO missing_objects
        FROM (VALUES
       ('aqua_archer', 'AquaArcher'),
       ('bomb_sprite', 'BombSprite'),
       ('boulder_strike', 'BoulderStrike'),
       ('bubble_generator', 'BubbleGenerator'),
       ('bubble_spirit', 'BubbleSpirit'),
       ('chain_lightning', 'ChainLightning'),
       ('cloud_dragon', 'CloudDragon'),
       ('crater', 'Crater'),
       ('dimension_toad', 'DimensionToad'),
       ('dragon_tower', 'DragonTower'),
       ('electric_explode', 'ElectricExplode'),
       ('electric_shot', 'ElectricShot'),
       ('electric_tower', 'ElectricTower'),
       ('ember_spirit', 'EmberSpirit'),
       ('evil_ent', 'EvilEnt'),
       ('fire_lord_spirit', 'FireLordSpirit'),
       ('fire_shot', 'FireShot'),
       ('fire_spirit', 'FireSpirit'),
       ('fire_summon', 'FireSummon'),
       ('firework_tower', 'FireworkTower'),
       ('frenzy_totem', 'FrenzyTotem'),
       ('grass_generator', 'GrassGenerator'),
       ('ground_cannon', 'GroundCannon'),
       ('ground_tower', 'GroundTower'),
       ('healing_totem', 'HealingTotem'),
       ('leaf_drop', 'Leafair'),
       ('life_tree', 'LifeTree'),
       ('lightning_cloud', 'LightningCloud'),
       ('magma_explosion', 'MagmaExplosion'),
       ('magma_spirit', 'MagmaSpirit'),
       ('mana_well', 'ManaWell'),
       ('meteor_shower', 'MeteorShower'),
       ('mini_rock', 'MiniRock'),
       ('overgrowth', 'Overgrowth'),
       ('rallying_totem', 'RallyingTotem'),
       ('razor_gale', 'RazorGale'),
       ('repair_totem', 'RepairTotem'),
       ('rock_drop', 'RockDrop'),
       ('rock_golem', 'RockGolem'),
       ('rock_mage', 'RockMage'),
       ('rock_rolling', 'RockRolling'),
       ('rock_turret', 'RockTurret'),
       ('sand_storm', 'SandStorm'),
       ('sea_serpent', 'SeaSerpent'),
       ('seed_nest', 'SeedNest'),
       ('seed_spirit', 'SeedSpirit'),
       ('shock_overload', 'ShockOverload'),
       ('shock_trap', 'ShockTrap'),
       ('storm_rider', 'StormRider'),
       ('storm_stag', 'StormStag'),
       ('thunder_bird', 'ThunderBird'),
       ('thunder_spirit', 'ThunderSpirit'),
       ('tide_call', 'TideCall'),
       ('titan_remnant', 'TitanRemnant'),
       ('tornado_strike', 'TornadoStrike'),
       ('towerback', 'Towerback'),
       ('tree_golem', 'TreeGolem'),
       ('vine_colony', 'VineColony'),
       ('vine_spirit', 'VineSpirit'),
       ('wall_golem', 'WallGolem'),
       ('water_explosion', 'WaterExplosion'),
       ('water_shot', 'WaterShot'),
       ('water_slime', 'WaterSlime'),
       ('wind_blade', 'WindBlade'),
       ('wind_spirit', 'WindSpirit'),
       ('wind_totem', 'WindTotem'),
       ('zap_mouse', 'ZapMouse')
             ) AS configured(object_name, prefab)
        WHERE NOT EXISTS (SELECT 1 FROM game_objects game_object WHERE game_object.name = configured.object_name);

        IF missing_objects <> '' THEN
            RAISE EXCEPTION 'these configured names are not game objects: %', missing_objects;
        END IF;

        SELECT COUNT(*) INTO filled_count FROM game_objects WHERE prefab IS NOT NULL;
        RAISE NOTICE '% game objects carry the name of the prefab they are', filled_count;
    END
$$;
