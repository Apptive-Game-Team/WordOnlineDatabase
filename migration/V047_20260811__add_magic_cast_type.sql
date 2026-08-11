ALTER TABLE magics
ADD COLUMN cast_type VARCHAR(10);

WITH magic_cast_types(name, cast_type) AS (
    VALUES
        ('ember_spirit_swarm', 'spawn'),
        ('water_slime_swarm', 'spawn'),
        ('mini_rock_swarm', 'spawn'),
        ('seed_spirit_swarm', 'spawn'),
        ('wind_spirit', 'spawn'),
        ('aqua_archer', 'spawn'),
        ('rock_golem', 'spawn'),
        ('storm_rider', 'spawn'),
        ('thunder_spirit', 'spawn'),
        ('fire_spirit', 'spawn'),
        ('magma_spirit', 'spawn'),
        ('wind_slime_swarm', 'spawn'),
        ('tornado_strike', 'spawn'),
        ('cloud_dragon', 'spawn'),
        ('thunder_bird_swarm', 'spawn'),
        ('tree_golem', 'spawn'),
        ('vine_spirit', 'spawn'),
        ('rock_mage', 'spawn'),
        ('pve_vine', 'spawn'),
        ('zap_mouse', 'spawn'),
        ('fire_lord_spirit', 'spawn'),
        ('dimension_toad', 'spawn'),
        ('bubble_spirit', 'spawn'),

        ('water_shot', 'shoot'),
        ('fire_shot', 'shoot'),
        ('tide_call', 'shoot'),
        ('chain_lightning', 'shoot'),
        ('vine_toss', 'shoot'),
        ('rock_rolling', 'shoot'),
        ('wind_blade', 'shoot'),
        ('nature_shot', 'shoot'),
        ('will_o_wisp', 'shoot'),
        ('rock_shot', 'shoot'),
        ('lightning_shot', 'shoot'),

        ('fire_slime_nest', 'build'),
        ('water_slime_nest', 'build'),
        ('life_tree', 'build'),
        ('rock_turret', 'build'),
        ('wind_totem', 'build'),
        ('cannon', 'build'),
        ('tower', 'build'),
        ('mana_well', 'build'),
        ('healing_totem', 'build'),
        ('pve_nature_slime_nest', 'build'),
        ('vine_colony', 'build'),
        ('crater', 'build'),
        ('rallying_torch', 'build'),
        ('rallying_totem', 'build'),
        ('bubble_generator', 'build'),
        ('electric_tower', 'build'),
        ('towerback', 'build'),
        ('seed_nest', 'build'),

        ('frenzy_totem', 'drop'),
        ('leafair', 'drop'),
        ('lightning_drop', 'drop'),
        ('meteor_shower', 'drop'),
        ('rock_drop', 'drop'),
        ('chicken_commando', 'drop'),

        ('magma_explosion', 'explode'),
        ('water_explosion', 'explode'),
        ('nature_explosion', 'explode'),
        ('wind_explosion', 'explode'),
        ('rock_explosion', 'explode'),
        ('fire_explosion', 'explode'),
        ('sand_storm', 'explode'),
        ('overgrowth', 'explode'),
        ('lightning_explosion', 'explode'),
        ('razor_gale', 'explode'),
        ('shock_overload', 'explode'),
        ('vine_world', 'explode')
)
UPDATE magics m
SET cast_type = mct.cast_type
FROM magic_cast_types mct
WHERE m.name = mct.name;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM magics WHERE cast_type IS NULL) THEN
        RAISE EXCEPTION 'Every magic must have a cast_type';
    END IF;
END $$;

ALTER TABLE magics
ALTER COLUMN cast_type SET NOT NULL;

ALTER TABLE magics
ADD CONSTRAINT chk_magics_cast_type
CHECK (cast_type IN ('spawn', 'drop', 'explode', 'build', 'shoot'));

-- Existing clients version the magic payload from magic_cards.updated_at.
-- Touch every recipe so cached payloads refresh after cast_type is introduced.
UPDATE magic_cards
SET updated_at = NOW();
