-- Rewrites magics.indicator from what each magic's server code actually does.
--
-- V091 filled this column from cast_type alone: 'shoot' got a lane from the caster to the aim
-- point, everything else a circle at the aim point sized by a radius parameter, plus a second
-- circle where an attack_range value existed. That is a copy of what the client drew before the
-- column existed, so the column carries the old drawing rather than the magic's behaviour. Reading
-- the game server magic by magic turned up three kinds of error, each fixed below:
--
--   the drawn shape is not the shape the magic makes
--     chain_lightning drew a filled radius-4 circle at the aim point, which reads as "everything in
--     here is hit". ChainShot hits one target and then hops to the next one within that radius, up
--     to five times. dragon_tower fires forward down a lane, not into a ring. wind_totem pushes a
--     forward box and drew nothing at all. firework_tower bursts attack_offset ahead of where it is
--     placed and drew the burst on top of itself.
--
--   the value cannot be reached from the magic's own game object
--     A magic's parameters are found by magic_id, falling back to a game object with the magic's
--     name. Both fail whenever the numbers live on another object: lightning_shot's on
--     electric_shot, vine_toss's on vine, wind_explosion's on wind_explode, lightning_explosion's on
--     electric_explode, vine_world's on giant_vine, leafair's on leaf_drop, crater's reach on
--     crater_ember, every swarm's unit stats on the unit object. Where a magic's own object holds
--     nothing but a magic_id row, the fallback does not even run, so the layer resolved to nothing
--     and the client drew an empty circle or a zero-width lane.
--
--   the value that resolves is the wrong number
--     life_tree and healing_totem keep their heal radius in a parameter named range, and a bare
--     {"parameter": "range"} resolves to the shared build.range (6) instead of the magic's own 1.5.
--     frenzy_totem drew its own body (0.5) where the buff it lands for covers attack_range (1.5).
--
-- Every size below therefore names the object it comes from: {"object": ..., "parameter": ...}.
-- Naming the object also steps around two magic_id rows that are wrong in the data - dimension_toad
-- carries seed_nest's magic_id 70, and thunder_bird carries thunder_spirit's 31 - which today make
-- a magic read another magic's numbers. Those two rows are a separate data fix; this file does not
-- depend on them.
--
-- The client reads an object-qualified size from WordOnlineClient#676. A client without it ignores
-- the object name, looks the parameter up on the magic itself, and skips that one layer when it
-- finds nothing - the same empty drawing as today, never a wrong number. So this migration is safe
-- to deploy first, which is the required order anyway (migration rule 4), and the layers start
-- resolving when that client ships. The lane keys it also adds are used here twice: an explicit
-- length on an end: "target" lane (vine_toss) and end: "aim" (spirit_bomb).
--
-- Two shapes, two meanings, held to across every magic below:
--
--   filled          what the cast puts on the field: the blast, the landing spot, the footprint of
--                   the building or unit, the corridor a projectile flies down.
--   ring (edgeWidth) what it can reach afterwards if something is there: a building's attack range,
--                   a chain's next hop, the burst a shot makes only where it hits.
--
-- What is deliberately not drawn, because it is not settled when the player is aiming:
--
--   chain_lightning past the first hop, and rock_rolling's two bounces - both decided by whatever
--   the projectile meets. shock_overload's second blast, which goes off a second later wherever the
--   marked targets have walked to. tornado_strike's drift toward the arena centre, whose direction
--   depends on where it was cast. electric_tower's chain_radius, which is measured from the target
--   it just hit, not from the tower. rallying_totem's range (2), which is a combat distance handed
--   to each rallied unit and not an area around the totem.
--
-- Approximations that are worth knowing about:
--
--   lightning_drop strikes a square of side radius * 2; the contract has no box, so the circle of
--   the same radius sits inside it and understates the corners.
--   sea_serpent's attack_range is drawn as a ring, though one attack is a beam inside it.
--   titan_remnant, vine_colony and crater draw the distance at which they react, not the size of
--   the hit that follows, which happens at the target and is a different number.
--
-- Numbers written as literals, with no parameter to point at:
--
--   1     Shot.IMPACT_EXPLOSION_RADIUS, the burst water_shot, fire_shot and lightning_shot make on
--         the target they hit.
--   1     AbstractSpawnMagic.SPAWN_RANGE, the +/-1 on x and z each summoned unit of a multi-unit
--         spawn is offset by. Drawn as one circle over the whole scatter instead of one unit's
--         body, which is what a player placing five spirits needs to see. The scatter is a square,
--         so the circle understates its corners by the usual sqrt(2).
--   6     VineTossMagic.VINE_COUNT * VINE_SPACING, the fixed reach of the vine line. It does not
--         follow the cursor and it is not the cast range, so the lane carries its own length.
--         vine_toss.vine_count (9) in the data is read by nothing and does not match the code.
--   4     VineWorldGrowth.OUTER_RADIUS, the ring the vines sprout on 0.75 s after the cast.
--   0.75  SpiritBombChannel.BEAM_WIDTH, the distance from the beam line inside which it picks its
--         target.
--   1.5   half of wind_totem.push_range_y (3), the width of the box it shoves. The contract has no
--         arithmetic and the data has no half-width row, so this literal must be changed by hand if
--         push_range_y ever moves.
--
-- Seven magics are left with the document V091 gave them. nature_shot, rock_shot,
-- nature_explosion, rock_explosion, fire_explosion and wind_slime_swarm have no @Component bean on
-- the game server, so DatabaseMagicParser drops them at startup and they cannot be cast at all;
-- pve_vine is a PVE-only spawn that never reaches a hand. Drawing them correctly would mean
-- guessing at behaviour that does not exist.

-- --------------------------------------------------------------------------- the documents
--
-- A temporary table rather than one CTE, so the assertions below can check the same list the
-- UPDATE used. Flyway runs this file in one transaction on PostgreSQL, so the table goes away with
-- the commit.
CREATE TEMP TABLE configured_indicator
(
    magic_name TEXT PRIMARY KEY,
    layers     JSONB NOT NULL
) ON COMMIT DROP;

INSERT INTO configured_indicator(magic_name, layers)
VALUES
    -- shoot: a lane the projectile flies down, plus what happens where it lands
    ('water_shot', '[{"shape": "lane", "origin": "caster", "end": "target", "halfWidth": {"object": "water_shot", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": 1, "edgeWidth": 0.08}]'),
    ('fire_shot', '[{"shape": "lane", "origin": "caster", "end": "target", "halfWidth": {"object": "fire_shot", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": 1, "edgeWidth": 0.08}]'),
    ('lightning_shot', '[{"shape": "lane", "origin": "caster", "end": "target", "halfWidth": {"object": "electric_shot", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": 1, "edgeWidth": 0.08}]'),
    ('chain_lightning', '[{"shape": "lane", "origin": "caster", "end": "target", "halfWidth": {"object": "chain_lightning", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "chain_lightning", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('tide_call', '[{"shape": "lane", "origin": "caster", "end": "target", "halfWidth": {"object": "tide_call", "parameter": "radius"}}]'),
    ('rock_rolling', '[{"shape": "lane", "origin": "caster", "end": "target", "halfWidth": {"object": "rock_rolling", "parameter": "radius"}}]'),
    ('wind_blade', '[{"shape": "lane", "origin": "caster", "end": "target", "halfWidth": {"object": "wind_blade", "parameter": "radius"}}]'),
    ('will_o_wisp', '[{"shape": "lane", "origin": "caster", "end": "target", "halfWidth": {"object": "will_o_wisp", "parameter": "radius"}}]'),
    ('vine_toss', '[{"shape": "lane", "origin": "caster", "end": "target", "length": 6, "halfWidth": {"object": "vine", "parameter": "radius"}}]'),
    ('boulder_strike', '[{"shape": "lane", "origin": "caster", "end": "target", "halfWidth": {"object": "boulder_strike", "parameter": "radius"}}]'),
    ('spirit_bomb', '[{"shape": "lane", "origin": "caster", "end": "aim", "halfWidth": 0.75}]'),
    ('tidal_warhead', '[{"shape": "circle", "origin": "target", "radius": {"object": "tidal_warhead", "parameter": "radius"}, "edgeWidth": 0.08}]'),

    -- explode: one circle where the blast lands
    ('magma_explosion', '[{"shape": "circle", "origin": "target", "radius": {"object": "magma_explosion", "parameter": "radius"}}]'),
    ('water_explosion', '[{"shape": "circle", "origin": "target", "radius": {"object": "water_explosion", "parameter": "radius"}}]'),
    ('wind_explosion', '[{"shape": "circle", "origin": "target", "radius": {"object": "wind_explode", "parameter": "radius"}}]'),
    ('lightning_explosion', '[{"shape": "circle", "origin": "target", "radius": {"object": "electric_explode", "parameter": "radius"}}]'),
    ('sand_storm', '[{"shape": "circle", "origin": "target", "radius": {"object": "sand_storm", "parameter": "radius"}}]'),
    ('overgrowth', '[{"shape": "circle", "origin": "target", "radius": {"object": "overgrowth", "parameter": "radius"}}]'),
    ('razor_gale', '[{"shape": "circle", "origin": "target", "radius": {"object": "razor_gale", "parameter": "radius"}}]'),
    ('shock_overload', '[{"shape": "circle", "origin": "target", "radius": {"object": "shock_overload", "parameter": "radius"}}]'),
    ('vine_world', '[{"shape": "circle", "origin": "target", "radius": {"object": "giant_vine", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": 4, "edgeWidth": 0.08}]'),
    ('tornado_strike', '[{"shape": "circle", "origin": "target", "radius": {"object": "tornado_strike", "parameter": "radius"}}]'),

    -- drop: one circle where the falling thing does its work
    ('frenzy_totem', '[{"shape": "circle", "origin": "target", "radius": {"object": "frenzy_totem", "parameter": "attack_range"}}]'),
    ('leafair', '[{"shape": "circle", "origin": "target", "radius": {"object": "leaf_drop", "parameter": "radius"}}]'),
    ('lightning_drop', '[{"shape": "circle", "origin": "target", "radius": {"object": "lightning_drop", "parameter": "radius"}}]'),
    ('meteor_shower', '[{"shape": "circle", "origin": "target", "radius": {"object": "meteor_shower", "parameter": "radius"}}]'),
    ('rock_drop', '[{"shape": "circle", "origin": "target", "radius": {"object": "rock_drop", "parameter": "radius"}}]'),
    ('chicken_commando', '[{"shape": "circle", "origin": "target", "radius": {"object": "chicken_commando", "parameter": "radius"}}]'),

    -- build: the footprint, then the threat the building projects from it
    ('fire_slime_nest', '[{"shape": "circle", "origin": "target", "radius": {"object": "fire_summon", "parameter": "radius"}}]'),
    ('water_slime_nest', '[{"shape": "circle", "origin": "target", "radius": {"object": "pve_water_slime_nest", "parameter": "radius"}}]'),
    ('pve_nature_slime_nest', '[{"shape": "circle", "origin": "target", "radius": {"object": "pve_nature_slime_nest", "parameter": "radius"}}]'),
    ('seed_nest', '[{"shape": "circle", "origin": "target", "radius": {"object": "seed_nest", "parameter": "radius"}}]'),
    ('life_tree', '[{"shape": "circle", "origin": "target", "radius": {"object": "life_tree", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "life_tree", "parameter": "range"}, "edgeWidth": 0.08}]'),
    ('healing_totem', '[{"shape": "circle", "origin": "target", "radius": {"object": "healing_totem", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "healing_totem", "parameter": "range"}, "edgeWidth": 0.08}]'),
    ('mana_well', '[{"shape": "circle", "origin": "target", "radius": {"object": "mana_well", "parameter": "radius"}}]'),
    ('rallying_totem', '[{"shape": "circle", "origin": "target", "radius": {"object": "rallying_totem", "parameter": "radius"}}]'),
    ('rock_turret', '[{"shape": "circle", "origin": "target", "radius": {"object": "rock_turret", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "rock_turret", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('cannon', '[{"shape": "circle", "origin": "target", "radius": {"object": "ground_cannon", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "ground_cannon", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('tower', '[{"shape": "circle", "origin": "target", "radius": {"object": "ground_tower", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "ground_tower", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('towerback', '[{"shape": "circle", "origin": "target", "radius": {"object": "towerback", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "towerback", "parameter": "sub_attack_range"}, "edgeWidth": 0.08}, {"shape": "circle", "origin": "target", "radius": {"object": "towerback", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('electric_tower', '[{"shape": "circle", "origin": "target", "radius": {"object": "electric_tower", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "electric_tower", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('bubble_generator', '[{"shape": "circle", "origin": "target", "radius": {"object": "bubble_generator", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "bubble_generator", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('vine_colony', '[{"shape": "circle", "origin": "target", "radius": {"object": "vine_colony", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "vine_colony", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('crater', '[{"shape": "circle", "origin": "target", "radius": {"object": "crater", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "crater_ember", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('wind_totem', '[{"shape": "circle", "origin": "target", "radius": {"object": "wind_totem", "parameter": "radius"}}, {"shape": "lane", "origin": "target", "end": "forward", "length": {"object": "wind_totem", "parameter": "push_range_x"}, "halfWidth": 1.5}]'),
    ('dragon_tower', '[{"shape": "circle", "origin": "target", "radius": {"object": "dragon_tower", "parameter": "radius"}}, {"shape": "lane", "origin": "target", "end": "forward", "length": {"object": "dragon_tower", "parameter": "attack_range"}, "halfWidth": {"object": "dragon_flame", "parameter": "radius"}}]'),
    ('firework_tower', '[{"shape": "circle", "origin": "target", "radius": {"object": "firework_tower", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "forwardOffset": {"object": "firework_tower", "parameter": "attack_offset"}, "radius": {"object": "firework_tower", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('repair_totem', '[{"shape": "circle", "origin": "target", "radius": {"object": "repair_totem", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "repair_totem", "parameter": "effect_radius"}, "edgeWidth": 0.08}]'),
    ('grass_generator', '[{"shape": "circle", "origin": "target", "radius": {"object": "grass_generator", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "grass_generator", "parameter": "effect_radius"}, "edgeWidth": 0.08}]'),
    ('shock_trap', '[{"shape": "circle", "origin": "target", "radius": {"object": "shock_trap", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "shock_trap", "parameter": "effect_radius"}, "edgeWidth": 0.08}]'),
    ('titan_remnant', '[{"shape": "circle", "origin": "target", "radius": {"object": "titan_remnant", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "titan_remnant", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),

    -- spawn: where the unit lands, then how far it reaches from there
    ('evil_ent', '[{"shape": "circle", "origin": "target", "radius": {"object": "evil_ent", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "evil_ent", "parameter": "attack_range"}, "edgeWidth": 0.08}, {"shape": "circle", "origin": "target", "radius": {"object": "evil_ent", "parameter": "sub_attack_range"}, "edgeWidth": 0.08}]'),
    ('storm_stag', '[{"shape": "circle", "origin": "target", "radius": {"object": "storm_stag", "parameter": "radius"}}]'),
    ('rock_golem', '[{"shape": "circle", "origin": "target", "radius": {"object": "rock_golem", "parameter": "radius"}}]'),
    ('storm_rider', '[{"shape": "circle", "origin": "target", "radius": {"object": "storm_rider", "parameter": "radius"}}]'),
    ('tree_golem', '[{"shape": "circle", "origin": "target", "radius": {"object": "tree_golem", "parameter": "radius"}}]'),
    ('wall_golem', '[{"shape": "circle", "origin": "target", "radius": {"object": "wall_golem", "parameter": "radius"}}]'),
    ('fire_lord_spirit', '[{"shape": "circle", "origin": "target", "radius": {"object": "fire_lord_spirit", "parameter": "radius"}}]'),
    ('dimension_toad', '[{"shape": "circle", "origin": "target", "radius": {"object": "dimension_toad", "parameter": "radius"}}]'),
    ('zap_mouse', '[{"shape": "circle", "origin": "target", "radius": 1}]'),
    ('wind_spirit', '[{"shape": "circle", "origin": "target", "radius": {"object": "wind_spirit", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "wind_spirit", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('aqua_archer', '[{"shape": "circle", "origin": "target", "radius": {"object": "aqua_archer", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "aqua_archer", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('thunder_spirit', '[{"shape": "circle", "origin": "target", "radius": {"object": "thunder_spirit", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "thunder_spirit", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('fire_spirit', '[{"shape": "circle", "origin": "target", "radius": {"object": "fire_spirit", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "fire_spirit", "parameter": "sub_attack_range"}, "edgeWidth": 0.08}, {"shape": "circle", "origin": "target", "radius": {"object": "fire_spirit", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('magma_spirit', '[{"shape": "circle", "origin": "target", "radius": {"object": "magma_spirit", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "magma_spirit", "parameter": "sub_attack_range"}, "edgeWidth": 0.08}, {"shape": "circle", "origin": "target", "radius": {"object": "magma_spirit", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('cloud_dragon', '[{"shape": "circle", "origin": "target", "radius": {"object": "cloud_dragon", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "cloud_dragon", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('rock_mage', '[{"shape": "circle", "origin": "target", "radius": {"object": "rock_mage", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "rock_mage", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('bubble_spirit', '[{"shape": "circle", "origin": "target", "radius": {"object": "bubble_spirit", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "bubble_spirit", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('sea_serpent', '[{"shape": "circle", "origin": "target", "radius": {"object": "sea_serpent", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "sea_serpent", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('bomb_sprite', '[{"shape": "circle", "origin": "target", "radius": {"object": "bomb_sprite", "parameter": "radius"}}, {"shape": "circle", "origin": "target", "radius": {"object": "bomb_sprite", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('ember_spirit_swarm', '[{"shape": "circle", "origin": "target", "radius": 1}]'),
    ('mini_rock_swarm', '[{"shape": "circle", "origin": "target", "radius": 1}]'),
    ('seed_spirit_swarm', '[{"shape": "circle", "origin": "target", "radius": 1}]'),
    ('water_slime_swarm', '[{"shape": "circle", "origin": "target", "radius": 1}, {"shape": "circle", "origin": "target", "radius": {"object": "aqua_archer", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('thunder_bird_swarm', '[{"shape": "circle", "origin": "target", "radius": 1}, {"shape": "circle", "origin": "target", "radius": {"object": "thunder_bird", "parameter": "attack_range"}, "edgeWidth": 0.08}]'),
    ('vine_spirit', '[{"shape": "circle", "origin": "target", "radius": 1}, {"shape": "circle", "origin": "target", "radius": {"object": "vine_spirit", "parameter": "attack_range"}, "edgeWidth": 0.08}]');

UPDATE magics magic
SET indicator = jsonb_build_object('version', 1, 'layers', configured.layers)
FROM configured_indicator configured
WHERE magic.name = configured.magic_name;

-- --------------------------------------------------------------------------- assertions
DO
$$
    DECLARE
        unknown_magics     TEXT;
        unresolved_sizes   TEXT;
        written_count      INTEGER;
        layer_count        INTEGER;
        ring_count         INTEGER;
        lane_count         INTEGER;
    BEGIN
        -- A name that matches no magic updates nothing and says nothing, which is how a typo would
        -- ship. Every name in the list above was read off this database's magics table.
        SELECT COALESCE(STRING_AGG(configured.magic_name, ', ' ORDER BY configured.magic_name), '')
        INTO unknown_magics
        FROM configured_indicator configured
        WHERE NOT EXISTS (SELECT 1 FROM magics magic WHERE magic.name = configured.magic_name);

        IF unknown_magics <> '' THEN
            RAISE EXCEPTION 'these configured names are not magics: %', unknown_magics;
        END IF;

        -- Every size that names an object must find a value there. A size that resolves to nothing
        -- makes the client drop that layer, which is exactly the silent hole this file exists to
        -- close, so it fails here instead of on someone's screen.
        SELECT COALESCE(STRING_AGG(DISTINCT reference.described, ', ' ORDER BY reference.described), '')
        INTO unresolved_sizes
        FROM (SELECT configured.magic_name || ' -> ' || (size ->> 'object') || '.' || (size ->> 'parameter')
                         AS described,
                     size ->> 'object'    AS object_name,
                     size ->> 'parameter' AS parameter_name
              FROM configured_indicator configured,
                   jsonb_array_elements(configured.layers) AS layer,
                   LATERAL (VALUES (layer -> 'radius'),
                                   (layer -> 'halfWidth'),
                                   (layer -> 'length'),
                                   (layer -> 'forwardOffset'),
                                   (layer -> 'edgeWidth')) AS sizes(size)
              WHERE jsonb_typeof(size) = 'object'
                AND (size ->> 'object') IS NOT NULL) AS reference
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = reference.object_name
                            AND parameter.name = reference.parameter_name
                            AND parameter_value.value IS NOT NULL);

        IF unresolved_sizes <> '' THEN
            RAISE EXCEPTION 'these indicator sizes find no parameter value: %', unresolved_sizes;
        END IF;

        SELECT COUNT(*)
        INTO written_count
        FROM magics magic
                 JOIN configured_indicator configured ON configured.magic_name = magic.name
        WHERE magic.indicator -> 'layers' = configured.layers;

        SELECT COUNT(*) FILTER (WHERE TRUE),
               COUNT(*) FILTER (WHERE layer -> 'edgeWidth' IS NOT NULL),
               COUNT(*) FILTER (WHERE layer ->> 'shape' = 'lane')
        INTO layer_count, ring_count, lane_count
        FROM magics magic,
             jsonb_array_elements(magic.indicator -> 'layers') AS layer;

        IF written_count <> (SELECT COUNT(*) FROM configured_indicator) THEN
            RAISE EXCEPTION 'wrote % of % configured indicator documents',
                written_count, (SELECT COUNT(*) FROM configured_indicator);
        END IF;

        RAISE NOTICE '% magics carry a behaviour-derived indicator', written_count;
        RAISE NOTICE '% layers across every magic, % of them rings and % of them lanes',
            layer_count, ring_count, lane_count;
    END
$$;
