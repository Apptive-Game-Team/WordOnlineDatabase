INSERT INTO pve_scenarios(id, stage_id)
VALUES
    (11, '1-1'),
    (12, '1-2'),
    (13, '1-3'),
    (14, '1-4');

INSERT INTO pve_scenario_objectives(scenario_id, installer_id, sort_order)
VALUES
    (11, 'enemy_boss_1', 1),
    (12, 'nature_nest', 1),
    (12, 'water_nest', 2),
    (13, 'pve_vine_colony', 1),
    (14, 'pve_vine_witch', 1);

INSERT INTO pve_scenario_installers(
    scenario_id,
    installer_id,
    prefab_type,
    master,
    position_x,
    position_y,
    position_z,
    sort_order
)
VALUES
    (11, 'enemy_boss_1', 'PveNatureSlimeNest', 'RightPlayer', 14, 5, 0, 1),
    (12, 'nature_nest', 'PveNatureSlimeNest', 'RightPlayer', 14, 7, 0, 1),
    (12, 'water_nest', 'PveWaterSlimeNest', 'RightPlayer', 14, 3, 0, 2),
    (13, 'pve_vine_colony', 'PveVineColony', 'RightPlayer', 14, 5, 0, 1),
    (14, 'pve_vine_witch', 'PveVineWitch', 'RightPlayer', 14, 5, 0, 1);

INSERT INTO pve_scenario_events(
    id,
    scenario_id,
    event_id,
    trigger_type,
    trigger_value,
    speaker_installer_id,
    message_key,
    sort_order
)
VALUES
    (111, 11, 'intro', 'FrameNumGte', 10, 'enemy_boss_1', 'pve_1_1_intro', 1),
    (112, 11, 'enemyLine', 'FrameNumGte', 20, 'enemy_boss_1', 'pve_1_1_enemy_line', 2),
    (121, 12, 'intro', 'FrameNumGte', 10, 'water_nest', 'pve_1_2_intro', 1),
    (122, 12, 'enemyLine', 'FrameNumGte', 20, 'water_nest', 'pve_1_2_enemy_line', 2),
    (131, 13, 'intro', 'FrameNumGte', 10, 'pve_vine_colony', 'pve_1_3_intro', 1),
    (132, 13, 'enemyLine', 'FrameNumGte', 20, 'pve_vine_colony', 'pve_1_3_enemy_line', 2),
    (141, 14, 'intro', 'FrameNumGte', 10, 'pve_vine_witch', 'pve_1_4_intro', 1),
    (142, 14, 'enemyLine', 'FrameNumGte', 20, 'pve_vine_witch', 'pve_1_4_enemy_line', 2);

INSERT INTO pve_scenario_event_lines(event_row_id, line_order, line_text)
VALUES
    (111, 1, 'Stage 1-1'),
    (111, 2, 'Destroy the enemy nest!'),
    (112, 1, 'Burn it all down!'),

    (121, 1, 'Stage 1-2'),
    (121, 2, 'Destroy the enemy nest!'),
    (122, 1, 'Burn it all down!'),

    (131, 1, 'Stage 1-3'),
    (131, 2, 'Destroy the vine colony!'),
    (132, 1, 'Burn it all down!'),

    (141, 1, 'Stage 1-4'),
    (141, 2, 'Destroy the vine witch!'),
    (142, 1, 'Burn it all down!');
