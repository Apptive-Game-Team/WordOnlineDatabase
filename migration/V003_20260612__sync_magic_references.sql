CREATE TEMP TABLE magic_catalog (
    id BIGINT PRIMARY KEY,
    name VARCHAR(255) NOT NULL
) ON COMMIT DROP;

INSERT INTO magic_catalog(id, name)
VALUES
    (1, 'ember_spirit_swarm'),
    (2, 'water_slime_swarm'),
    (3, 'mini_rock_swarm'),
    (4, 'seed_spirit_swarm'),
    (5, 'wind_spirit'),
    (6, 'water_shot'),
    (7, 'fire_shot'),
    (8, 'tide_call'),
    (9, 'chain_lightning'),
    (10, 'vine_toss'),
    (11, 'rock_rolling'),
    (12, 'wind_blade'),
    (13, 'nature_shot'),
    (14, 'fire_slime_nest'),
    (15, 'water_slime_nest'),
    (16, 'life_tree'),
    (17, 'rock_turret'),
    (18, 'wind_totem'),
    (19, 'magma_explosion'),
    (20, 'water_explosion'),
    (21, 'will_o_wisp'),
    (22, 'nature_explosion'),
    (23, 'frenzy_totem'),
    (24, 'leafair'),
    (25, 'cannon'),
    (26, 'tower'),
    (27, 'mana_well'),
    (28, 'aqua_archer'),
    (29, 'rock_golem'),
    (30, 'storm_rider'),
    (31, 'thunder_spirit'),
    (32, 'fire_spirit'),
    (33, 'rock_shot'),
    (35, 'lightning_drop'),
    (36, 'wind_explosion'),
    (37, 'rock_explosion'),
    (38, 'fire_explosion'),
    (39, 'magma_spirit'),
    (40, 'healing_totem'),
    (41, 'sand_storm'),
    (42, 'wind_slime_swarm'),
    (43, 'tornado_strike'),
    (44, 'meteor_shower'),
    (45, 'lightning_shot'),
    (46, 'cloud_dragon'),
    (47, 'thunder_bird_swarm'),
    (48, 'tree_golem'),
    (49, 'vine_spirit'),
    (50, 'vine_colony'),
    (51, 'rock_mage'),
    (52, 'pve_nature_slime_nest'),
    (53, 'pve_vine'),
    (54, 'rock_drop'),
    (55, 'chicken_commando'),
    (56, 'overgrowth'),
    (57, 'crater'),
    (58, 'zap_mouse'),
    (59, 'rallying_torch'),
    (60, 'lightning_explosion'),
    (61, 'razor_gale'),
    (62, 'bubble_generator'),
    (63, 'electric_tower'),
    (64, 'fire_lord_spirit'),
    (65, 'dimension_toad'),
    (66, 'towerback'),
    (67, 'shock_overload'),
    (68, 'bubble_spirit');

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM magics m
        LEFT JOIN magic_catalog c ON c.name = m.name
        WHERE c.name IS NULL
    ) THEN
        RAISE EXCEPTION 'Found magic rows outside canonical catalog';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM magics m
        JOIN magic_catalog c ON c.id = m.id
        WHERE m.name <> c.name
    ) THEN
        RAISE NOTICE 'Canonical ids are held by other magics; leaving magic ids untouched.';
    END IF;
END $$;

-- Renumbering only applies to a database that already follows the canonical id
-- assignment. A database that assigned its own ids keeps them: nothing outside
-- this table depends on the values -- later migrations resolve magics by name,
-- and the client takes ids from whichever server it is talking to -- while
-- renumbering would delete real rows from user_magics and
-- statistic_game_magics wherever the old and target ids both exist for a user.
--
-- An empty map makes every rewrite below affect nothing.
CREATE TEMP TABLE magic_id_map AS
SELECT m.id AS old_id,
       c.id AS target_id,
       m.name
FROM magics m
JOIN magic_catalog c ON c.name = m.name
WHERE NOT EXISTS (
    SELECT 1
    FROM magics other
    JOIN magic_catalog other_catalog ON other_catalog.id = other.id
    WHERE other.name <> other_catalog.name
);

-- Same condition: seeding a catalog row at its canonical id is only correct
-- while ids are canonical. Elsewhere it would add a second row under a name
-- the database already has at a different id.
INSERT INTO magics(id, name)
SELECT c.id, c.name
FROM magic_catalog c
WHERE NOT EXISTS (
    SELECT 1
    FROM magics m
    WHERE m.id = c.id
)
AND NOT EXISTS (
    SELECT 1
    FROM magics other
    JOIN magic_catalog other_catalog ON other_catalog.id = other.id
    WHERE other.name <> other_catalog.name
);

DELETE FROM magic_cards old_magic_card
USING magic_id_map mm
WHERE old_magic_card.magic_id = mm.old_id
  AND mm.old_id <> mm.target_id
  AND EXISTS (
      SELECT 1
      FROM magic_cards existing_magic_card
      WHERE existing_magic_card.magic_id = mm.target_id
        AND existing_magic_card.card_id = old_magic_card.card_id
  );

UPDATE magic_cards magic_card
SET magic_id = mm.target_id
FROM magic_id_map mm
WHERE magic_card.magic_id = mm.old_id
  AND mm.old_id <> mm.target_id;

DELETE FROM user_magics old_user_magic
USING magic_id_map mm
WHERE old_user_magic.magic_id = mm.old_id
  AND mm.old_id <> mm.target_id
  AND EXISTS (
      SELECT 1
      FROM user_magics existing_user_magic
      WHERE existing_user_magic.user_id = old_user_magic.user_id
        AND existing_user_magic.magic_id = mm.target_id
  );

UPDATE user_magics user_magic
SET magic_id = mm.target_id
FROM magic_id_map mm
WHERE user_magic.magic_id = mm.old_id
  AND mm.old_id <> mm.target_id;

DELETE FROM statistic_game_magics old_statistic_magic
USING magic_id_map mm
WHERE old_statistic_magic.magic_id = mm.old_id
  AND mm.old_id <> mm.target_id
  AND EXISTS (
      SELECT 1
      FROM statistic_game_magics existing_statistic_magic
      WHERE existing_statistic_magic.user_id = old_statistic_magic.user_id
        AND existing_statistic_magic.statistic_game_id IS NOT DISTINCT FROM old_statistic_magic.statistic_game_id
        AND existing_statistic_magic.magic_id = mm.target_id
  );

UPDATE statistic_game_magics statistic_magic
SET magic_id = mm.target_id
FROM magic_id_map mm
WHERE statistic_magic.magic_id = mm.old_id
  AND mm.old_id <> mm.target_id;

DELETE FROM magics old_magic
USING magic_id_map mm
WHERE old_magic.id = mm.old_id
  AND mm.old_id <> mm.target_id;

SELECT setval('magics_id_seq', (SELECT MAX(id) FROM magics), true);
