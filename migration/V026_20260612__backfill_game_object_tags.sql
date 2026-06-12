CREATE TABLE IF NOT EXISTS tags (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(20) UNIQUE
);

CREATE TABLE IF NOT EXISTS game_object_tags (
    id BIGSERIAL PRIMARY KEY,
    game_object_id BIGINT REFERENCES game_objects(id),
    tag_id BIGINT REFERENCES tags(id),
    CONSTRAINT uq_game_object_id_tag_id UNIQUE (game_object_id, tag_id)
);

WITH required_tags AS (
    SELECT tag_name
    FROM (
        VALUES
            ('TYPE_Unit'),
            ('TYPE_Data'),
            ('TYPE_Card'),
            ('CAT_Small'),
            ('CAT_Medium'),
            ('CAT_Large'),
            ('CAT_Melee'),
            ('CAT_Ranged'),
            ('CAT_Tank'),
            ('CAT_Flying'),
            ('CAT_CC'),
            ('CAT_AoE'),
            ('CAT_Building')
    ) AS tags(tag_name)
),
inserted_tags AS (
    INSERT INTO tags(name)
    SELECT tag_name
    FROM required_tags rt
    WHERE NOT EXISTS (
        SELECT 1
        FROM tags t
        WHERE t.name = rt.tag_name
    )
    RETURNING id, name
),
target_tags AS (
    SELECT id, name FROM inserted_tags
    UNION ALL
    SELECT t.id, t.name
    FROM tags t
    JOIN required_tags rt ON rt.tag_name = t.name
),
required_game_object_tags AS (
    SELECT *
    FROM (
        VALUES
            ('bubble_generator', 'TYPE_Unit'),
            ('bubble_generator', 'CAT_Building'),
            ('bubble_generator', 'CAT_Ranged'),
            ('bubble_spirit', 'TYPE_Unit'),
            ('bubble_spirit', 'CAT_Flying'),
            ('bubble_spirit', 'CAT_Ranged'),
            ('bubble_spirit', 'CAT_Small'),
            ('chain_lightning', 'TYPE_Unit'),
            ('chain_lightning', 'CAT_AoE'),
            ('chain_lightning', 'CAT_Ranged'),
            ('chicken_commando', 'TYPE_Unit'),
            ('chicken_commando', 'CAT_Melee'),
            ('chicken_commando', 'CAT_Small'),
            ('crater', 'TYPE_Unit'),
            ('crater', 'CAT_AoE'),
            ('crater', 'CAT_Building'),
            ('crater_ember', 'TYPE_Unit'),
            ('crater_ember', 'CAT_AoE'),
            ('dimension_toad', 'TYPE_Unit'),
            ('dimension_toad', 'CAT_Large'),
            ('electric_tower', 'TYPE_Unit'),
            ('electric_tower', 'CAT_AoE'),
            ('electric_tower', 'CAT_Building'),
            ('electric_tower', 'CAT_Ranged'),
            ('field', 'TYPE_Data'),
            ('fire_child_spirit', 'TYPE_Unit'),
            ('fire_child_spirit', 'CAT_Flying'),
            ('fire_child_spirit', 'CAT_Ranged'),
            ('fire_child_spirit', 'CAT_Small'),
            ('fire_lord_spirit', 'TYPE_Unit'),
            ('fire_lord_spirit', 'CAT_Flying'),
            ('fire_lord_spirit', 'CAT_Large'),
            ('fire_lord_spirit', 'CAT_Ranged'),
            ('fire_tadpole', 'TYPE_Unit'),
            ('fire_tadpole', 'CAT_Melee'),
            ('fire_tadpole', 'CAT_Small'),
            ('lightning_tadpole', 'TYPE_Unit'),
            ('lightning_tadpole', 'CAT_Melee'),
            ('lightning_tadpole', 'CAT_Small'),
            ('magma_fist', 'TYPE_Unit'),
            ('magma_fist', 'CAT_AoE'),
            ('meteor_drop', 'TYPE_Unit'),
            ('meteor_drop', 'CAT_AoE'),
            ('meteor_shower', 'TYPE_Data'),
            ('overgrowth', 'TYPE_Unit'),
            ('overgrowth', 'CAT_AoE'),
            ('pve_nature_slime_nest', 'TYPE_Unit'),
            ('pve_nature_slime_nest', 'CAT_Building'),
            ('pve_nature_slime_nest', 'CAT_Ranged'),
            ('pve_vine_colony', 'TYPE_Unit'),
            ('pve_vine_colony', 'CAT_Building'),
            ('pve_vine_colony', 'CAT_Ranged'),
            ('pve_water_slime_nest', 'TYPE_Unit'),
            ('pve_water_slime_nest', 'CAT_Building'),
            ('pve_water_slime_nest', 'CAT_Ranged'),
            ('pve_vine_witch', 'TYPE_Unit'),
            ('pve_vine_witch', 'CAT_Ranged'),
            ('rallying_torch', 'TYPE_Unit'),
            ('rallying_torch', 'CAT_AoE'),
            ('razor_gale', 'TYPE_Unit'),
            ('razor_gale', 'CAT_AoE'),
            ('tide_call', 'TYPE_Unit'),
            ('tide_call', 'CAT_CC'),
            ('tide_call', 'CAT_AoE'),
            ('tornado_strike', 'TYPE_Unit'),
            ('tornado_strike', 'CAT_CC'),
            ('tornado_strike', 'CAT_AoE'),
            ('towerback', 'TYPE_Unit'),
            ('towerback', 'CAT_Building'),
            ('towerback', 'CAT_Ranged'),
            ('vine', 'TYPE_Data'),
            ('wind_explode', 'TYPE_Unit'),
            ('wind_explode', 'CAT_AoE'),
            ('wind_explode', 'CAT_CC'),
            ('wind_shoot', 'TYPE_Data'),
            ('wind_totem', 'TYPE_Unit'),
            ('wind_totem', 'CAT_Building'),
            ('wind_totem', 'CAT_CC'),
            ('zap_mouse', 'TYPE_Unit'),
            ('zap_mouse', 'CAT_CC'),
            ('zap_mouse', 'CAT_Small')
    ) AS mappings(game_object_name, tag_name)
),
target_game_objects AS (
    SELECT go.id, go.name
    FROM game_objects go
    JOIN required_game_object_tags rgot ON rgot.game_object_name = go.name
    GROUP BY go.id, go.name
)
INSERT INTO game_object_tags(game_object_id, tag_id)
SELECT tgo.id, tt.id
FROM required_game_object_tags rgot
JOIN target_game_objects tgo ON tgo.name = rgot.game_object_name
JOIN target_tags tt ON tt.name = rgot.tag_name
WHERE NOT EXISTS (
    SELECT 1
    FROM game_object_tags got
    WHERE got.game_object_id = tgo.id
      AND got.tag_id = tt.id
);
