-- Registers the September composite-magic set and replaces shock_overload's recipe.
-- The runtime implementations live on the main lineage and use the existing cast_type contract.
--
-- never-applied: the first version of this file gave titan_remnant Build + Explode + Rock, which
-- the magic tower has held since V032. The collision assertion below stopped the migration, Flyway
-- rolled the transaction back, and no flyway_schema_history row was written on any database, so
-- there is nothing for a forward-fix migration to correct. Every database is still at V088 and
-- stays there until this file itself succeeds. titan_remnant now takes Build + Rock + Rock, which
-- no magic uses; TitanRemnantPrefabInitializer sets ElementType.ROCK and nothing else, so the
-- Explode card was not carrying an element the runtime reads.

-- --------------------------------------------------------------------------- catalogue
INSERT INTO magics(name, access_type, cast_type)
SELECT pending.name, 'DEFAULT', pending.cast_type
FROM (VALUES ('titan_remnant', 'build'),
             ('spirit_bomb', 'shoot'),
             ('tidal_warhead', 'shoot'),
             ('boulder_strike', 'shoot'),
             ('bomb_sprite', 'spawn')) pending(name, cast_type)
WHERE NOT EXISTS (SELECT 1 FROM magics existing WHERE existing.name = pending.name);

UPDATE magics magic
SET access_type = 'DEFAULT',
    cast_type = expected.cast_type
FROM (VALUES ('titan_remnant', 'build'),
             ('spirit_bomb', 'shoot'),
             ('tidal_warhead', 'shoot'),
             ('boulder_strike', 'shoot'),
             ('bomb_sprite', 'spawn'),
             ('shock_overload', 'explode')) expected(name, cast_type)
WHERE magic.name = expected.name;

-- Recipes are exact multisets. Delete only the six owned recipes so a re-run also removes
-- obsolete cards (notably shock_overload's old Explode + Lightning x2 recipe).
DELETE FROM magic_cards
WHERE magic_id IN (SELECT id
                   FROM magics
                   WHERE name IN ('titan_remnant', 'spirit_bomb', 'tidal_warhead',
                                  'boulder_strike', 'bomb_sprite', 'shock_overload'));

WITH recipes(magic_name, card_name, required_count) AS (
    VALUES ('titan_remnant', 'Build', 1),
           ('titan_remnant', 'Rock', 2),
           ('spirit_bomb', 'Shoot', 2),
           ('spirit_bomb', 'Lightning', 1),
           ('spirit_bomb', 'Nature', 1),
           ('tidal_warhead', 'Shoot', 1),
           ('tidal_warhead', 'Explode', 1),
           ('tidal_warhead', 'Water', 1),
           ('boulder_strike', 'Shoot', 1),
           ('boulder_strike', 'Rock', 1),
           ('boulder_strike', 'Wind', 1),
           ('bomb_sprite', 'Spawn', 1),
           ('bomb_sprite', 'Drop', 1),
           ('bomb_sprite', 'Explode', 1),
           ('bomb_sprite', 'Wind', 1),
           ('shock_overload', 'Explode', 2),
           ('shock_overload', 'Lightning', 1)
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT magic.id, card.id
FROM recipes recipe
         JOIN magics magic ON magic.name = recipe.magic_name
         JOIN cards card ON card.name = recipe.card_name
         CROSS JOIN LATERAL generate_series(1, recipe.required_count);

-- Existing accounts otherwise receive DEFAULT magics only after their next initialization.
-- Grant the five new entries immediately; shock_overload ownership is already preserved.
INSERT INTO user_magics(user_id, magic_id)
SELECT app_user.id, magic.id
FROM users app_user
         CROSS JOIN magics magic
WHERE magic.name IN ('titan_remnant', 'spirit_bomb', 'tidal_warhead',
                     'boulder_strike', 'bomb_sprite')
ON CONFLICT (user_id, magic_id) DO NOTHING;

-- ----------------------------------------------------------------------------- objects
INSERT INTO game_objects(name)
VALUES ('titan_remnant'),
       ('titan_fist'),
       ('spirit_bomb'),
       ('tidal_warhead'),
       ('ground_tidal_warhead'),
       ('boulder_strike'),
       ('bomb_sprite'),
       ('bomb_sprite_bomb')
ON CONFLICT (name) DO NOTHING;

INSERT INTO parameters(name)
VALUES ('mass'), ('radius'), ('hp'),
       ('speed'), ('damage'), ('attack_interval'), ('attack_range'), ('duration'),
       ('sub_damage'), ('push_force'), ('quantity')
ON CONFLICT (name) DO NOTHING;

-- Cast cost and placement range stay on the cast-type family rows (build, shoot and spawn).
-- The main client derives the line shape from cast_type and has no aim_shape reader. Adding
-- per-magic rows for those names would be dead data because GameParameterResolver resolves the
-- family row first. Every value below is read by one of the new prefab initializers.
-- V053 multiplied every hp and damage parameter already present by 10. This migration runs after
-- V053, so the authored pre-scale hp and damage values are multiplied here as well; speed, radius,
-- duration, mass, force and count values stay in their original units.
WITH configured(game_object_name, parameter_name, value) AS (
    VALUES ('titan_remnant', 'mass', 1000.0),
           ('titan_remnant', 'radius', 1.0),
           ('titan_remnant', 'hp', 400.0),
           ('titan_remnant', 'attack_interval', 2.0),
           ('titan_remnant', 'attack_range', 4.0),
           ('titan_remnant', 'duration', 60.0),
           ('titan_fist', 'radius', 1.25),
           ('titan_fist', 'damage', 120.0),
           ('titan_fist', 'duration', 0.8),
           ('tidal_warhead', 'damage', 240.0),
           ('tidal_warhead', 'speed', 7.0),
           ('tidal_warhead', 'radius', 2.5),
           ('boulder_strike', 'damage', 140.0),
           ('boulder_strike', 'speed', 9.0),
           ('boulder_strike', 'sub_damage', 200.0),
           ('boulder_strike', 'push_force', 7.0),
           ('boulder_strike', 'radius', 0.45),
           ('bomb_sprite', 'mass', 1.0),
           ('bomb_sprite', 'radius', 0.5),
           ('bomb_sprite', 'hp', 200.0),
           ('bomb_sprite', 'speed', 1.5),
           ('bomb_sprite', 'attack_interval', 2.5),
           ('bomb_sprite', 'attack_range', 6.0),
           ('bomb_sprite', 'quantity', 1.0),
           ('bomb_sprite_bomb', 'damage', 180.0),
           ('bomb_sprite_bomb', 'speed', 6.0),
           ('bomb_sprite_bomb', 'radius', 2.0)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, configured.value
FROM configured
         JOIN game_objects game_object ON game_object.name = configured.game_object_name
         JOIN parameters parameter ON parameter.name = configured.parameter_name
ON CONFLICT (parameter_id, game_object_id)
    DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- ----------------------------------------------------------------------- counter tags
WITH mapping(game_object_name, tag_name) AS (
    VALUES ('titan_remnant', 'TYPE_Unit'),
           ('titan_remnant', 'CAT_Building'),
           ('titan_remnant', 'CAT_Ranged'),
           ('titan_remnant', 'CAT_AoE'),
           ('titan_fist', 'TYPE_Data'),
           ('titan_fist', 'CAT_AoE'),
           ('spirit_bomb', 'TYPE_Data'),
           ('spirit_bomb', 'CAT_Ranged'),
           ('tidal_warhead', 'TYPE_Unit'),
           ('tidal_warhead', 'CAT_Ranged'),
           ('tidal_warhead', 'CAT_AoE'),
           ('ground_tidal_warhead', 'TYPE_Unit'),
           ('ground_tidal_warhead', 'CAT_Ranged'),
           ('ground_tidal_warhead', 'CAT_AoE'),
           ('boulder_strike', 'TYPE_Unit'),
           ('boulder_strike', 'CAT_Ranged'),
           ('boulder_strike', 'CAT_CC'),
           ('bomb_sprite', 'TYPE_Unit'),
           ('bomb_sprite', 'CAT_Flying'),
           ('bomb_sprite', 'CAT_Ranged'),
           ('bomb_sprite', 'CAT_AoE'),
           ('bomb_sprite_bomb', 'TYPE_Data'),
           ('bomb_sprite_bomb', 'CAT_AoE')
), required_tags(name) AS (
    SELECT DISTINCT tag_name FROM mapping
), inserted_tags AS (
    INSERT INTO tags(name)
    SELECT required.name
    FROM required_tags required
    WHERE NOT EXISTS (SELECT 1 FROM tags existing WHERE existing.name = required.name)
    RETURNING id, name
), target_tags AS (
    SELECT id, name FROM inserted_tags
    UNION ALL
    SELECT existing.id, existing.name
    FROM tags existing
             JOIN required_tags required ON required.name = existing.name
)
INSERT INTO game_object_tags(game_object_id, tag_id)
SELECT game_object.id, tag.id
FROM mapping
         JOIN game_objects game_object ON game_object.name = mapping.game_object_name
         JOIN target_tags tag ON tag.name = mapping.tag_name
WHERE NOT EXISTS (SELECT 1
                  FROM game_object_tags existing
                  WHERE existing.game_object_id = game_object.id
                    AND existing.tag_id = tag.id);

SELECT sync_magic_tags_from_game_objects();

-- --------------------------------------------------------------------------- assertions
DO
$$
DECLARE
    missing_magic       TEXT;
    wrong_recipe       TEXT;
    colliding_recipes  TEXT;
    missing_parameter  TEXT;
    unowned_user_count INTEGER;
BEGIN
    SELECT expected.name
    INTO missing_magic
    FROM (VALUES ('titan_remnant', 'build'), ('spirit_bomb', 'shoot'),
                 ('tidal_warhead', 'shoot'), ('boulder_strike', 'shoot'),
                 ('bomb_sprite', 'spawn'), ('shock_overload', 'explode')) expected(name, cast_type)
    WHERE NOT EXISTS (SELECT 1
                      FROM magics magic
                      WHERE magic.name = expected.name
                        AND magic.cast_type = expected.cast_type)
    LIMIT 1;

    IF missing_magic IS NOT NULL THEN
        RAISE EXCEPTION 'magic % is missing or has incomplete runtime metadata', missing_magic;
    END IF;

    WITH expected(magic_name, recipe) AS (
        VALUES ('titan_remnant', ARRAY['Build', 'Rock', 'Rock']::TEXT[]),
               ('spirit_bomb', ARRAY['Lightning', 'Nature', 'Shoot', 'Shoot']::TEXT[]),
               ('tidal_warhead', ARRAY['Explode', 'Shoot', 'Water']::TEXT[]),
               ('boulder_strike', ARRAY['Rock', 'Shoot', 'Wind']::TEXT[]),
               ('bomb_sprite', ARRAY['Drop', 'Explode', 'Spawn', 'Wind']::TEXT[]),
               ('shock_overload', ARRAY['Explode', 'Explode', 'Lightning']::TEXT[])
    ), actual AS (
        SELECT magic.name, ARRAY_AGG(card.name::TEXT ORDER BY card.name) AS recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name IN (SELECT magic_name FROM expected)
        GROUP BY magic.name
    )
    SELECT expected.magic_name
    INTO wrong_recipe
    FROM expected
             LEFT JOIN actual ON actual.name = expected.magic_name
    WHERE actual.recipe IS DISTINCT FROM expected.recipe
    LIMIT 1;

    IF wrong_recipe IS NOT NULL THEN
        RAISE EXCEPTION 'magic % does not have its exact expected recipe', wrong_recipe;
    END IF;

    WITH recipes AS (
        SELECT magic.name, ARRAY_AGG(card.name::TEXT ORDER BY card.name) AS recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        GROUP BY magic.name
    )
    SELECT STRING_AGG(left_recipe.name || ' = ' || right_recipe.name, ', ')
    INTO colliding_recipes
    FROM recipes left_recipe
             JOIN recipes right_recipe
                  ON right_recipe.recipe = left_recipe.recipe
                      AND right_recipe.name > left_recipe.name
    WHERE left_recipe.name IN ('titan_remnant', 'spirit_bomb', 'tidal_warhead',
                               'boulder_strike', 'bomb_sprite', 'shock_overload')
       OR right_recipe.name IN ('titan_remnant', 'spirit_bomb', 'tidal_warhead',
                               'boulder_strike', 'bomb_sprite', 'shock_overload');

    IF colliding_recipes IS NOT NULL THEN
        RAISE EXCEPTION 'composite magic recipe collision(s): %', colliding_recipes;
    END IF;

    SELECT required.game_object_name || '.' || required.parameter_name
    INTO missing_parameter
    FROM (VALUES ('titan_remnant', 'hp'), ('titan_fist', 'damage'),
                 ('tidal_warhead', 'damage'), ('boulder_strike', 'sub_damage'),
                 ('bomb_sprite', 'hp'), ('bomb_sprite_bomb', 'damage'),
                 ('bomb_sprite_bomb', 'radius')) required(game_object_name, parameter_name)
    WHERE NOT EXISTS (SELECT 1
                      FROM parameter_values parameter_value
                               JOIN game_objects game_object
                                    ON game_object.id = parameter_value.game_object_id
                               JOIN parameters parameter
                                    ON parameter.id = parameter_value.parameter_id
                      WHERE game_object.name = required.game_object_name
                        AND parameter.name = required.parameter_name
                        AND parameter_value.value IS NOT NULL)
    LIMIT 1;

    IF missing_parameter IS NOT NULL THEN
        RAISE EXCEPTION 'required parameter % is missing', missing_parameter;
    END IF;

    SELECT COUNT(*)
    INTO unowned_user_count
    FROM users app_user
             CROSS JOIN magics magic
    WHERE magic.name IN ('titan_remnant', 'spirit_bomb', 'tidal_warhead',
                         'boulder_strike', 'bomb_sprite')
      AND NOT EXISTS (SELECT 1
                      FROM user_magics owned
                      WHERE owned.user_id = app_user.id
                        AND owned.magic_id = magic.id);

    IF unowned_user_count > 0 THEN
        RAISE EXCEPTION '% existing user/new magic ownership rows are missing', unowned_user_count;
    END IF;
END
$$;
