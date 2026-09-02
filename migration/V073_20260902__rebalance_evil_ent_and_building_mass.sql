-- Buildings must remain outside evil_ent's pull_mass_limit of 5.0. V023 already
-- uses 1000.0 for towerback, so this gives every CAT_Building object one shared mass.
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, 1000.0
FROM game_objects game_object
JOIN game_object_tags game_object_tag ON game_object_tag.game_object_id = game_object.id
JOIN tags tag ON tag.id = game_object_tag.tag_id
JOIN parameters parameter ON parameter.name = 'mass'
WHERE tag.name = 'CAT_Building'
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

-- Fire fist needs a stronger hit, while a five-second pull charge interval makes pulls
-- available often enough to build and spend the three-charge stockpile. V069 used 28.0 damage
-- and a 12.0-second interval.
WITH evil_ent_values(parameter_name, value) AS (
    VALUES
        ('sub_damage', 40.0),
        ('sub_attack_interval', 5.0)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, evil_ent_values.value
FROM game_objects game_object
JOIN evil_ent_values ON TRUE
JOIN parameters parameter ON parameter.name = evil_ent_values.parameter_name
WHERE game_object.name = 'evil_ent'
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;
