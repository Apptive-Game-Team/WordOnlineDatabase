-- Points every magic_id parameter row at the magic its game object actually belongs to.
--
-- A magic_id row in parameter_values is how a game object says which magic owns it. The client
-- reads it first when it looks up a magic's numbers (GameParameterResolver.GetObjectNamesForMagic:
-- objects whose magic_id matches, and only if there are none, an object with the magic's name), and
-- the admin spreadsheet pairs objects with magics through the same value. Eleven rows name a
-- different magic, all of them literals V032 wrote into the dev backfill:
--
--   chicken_commando 64, crater 63, razor_gale 66, bubble_generator 67, electric_tower 68,
--   fire_lord_spirit 69, dimension_toad 70, towerback 71, bubble_spirit 73
--     Nine objects that share their name with a magic and carry another magic's id. The magic
--     whose id they carry then resolves to the wrong object and reads its numbers: magic
--     electric_tower (63) reads crater's body (0.75) and finds no attack_range, magic seed_nest
--     (70) reads dimension_toad's. The early return above makes this total - one wrong row hides
--     the right object completely.
--
--   thunder_bird 31
--     thunder_bird is the unit thunder_bird_swarm (47) summons, not thunder_spirit (31). Mirroring
--     a magic's id onto the unit object is the established shape: mini_rock carries
--     mini_rock_swarm's, ground_cannon carries cannon's, ground_tower carries tower's.
--
--   slime 1
--     slime belongs to no magic. It is the generic body the old slime objects were built from
--     (radius 0.2, quantity 10) and magic_game_object_aliases says ember_spirit_swarm's unit is
--     ember_spirit. While this row stands, ember_spirit_swarm resolves to slime and shows 0.2
--     where its spirits are 0.5. The row is deleted, and because that would leave the three swarm
--     magics with nothing to read, ember_spirit, water_slime and seed_spirit get the mirror row
--     their sibling mini_rock already has.
--
-- Nothing here is written as an id literal. V032's literals are exactly how these rows went wrong -
-- ids differ between databases - so every value below is resolved by name at migration time.
--
-- One thing this shape cannot express: a game object holds one magic_id, so an object two magics
-- alias to (vine_toss is aliased by nature_shot, rock_rolling by rock_shot) cannot name both.
-- Those rows are left alone.

-- ------------------------------------------------------- objects named after their own magic
UPDATE parameter_values parameter_value
SET value      = magic.id,
    updated_at = NOW()
FROM game_objects game_object,
     parameters parameter,
     magics magic
WHERE parameter_value.game_object_id = game_object.id
  AND parameter_value.parameter_id = parameter.id
  AND parameter.name = 'magic_id'
  AND magic.name = game_object.name
  AND parameter_value.value IS DISTINCT FROM magic.id;

-- --------------------------------------------------- unit objects a magic is aliased onto
--
-- Only objects that are not a magic's name themselves, and that exactly one magic aliases, so the
-- statement cannot pick between two owners.
UPDATE parameter_values parameter_value
SET value      = owner.magic_id,
    updated_at = NOW()
FROM game_objects game_object,
     parameters parameter,
     (SELECT alias.game_object_name AS object_name,
             MIN(magic.id)          AS magic_id
      FROM magic_game_object_aliases alias
               JOIN magics magic ON magic.name = alias.magic_name
      WHERE NOT EXISTS (SELECT 1 FROM magics named WHERE named.name = alias.game_object_name)
      GROUP BY alias.game_object_name
      HAVING COUNT(*) = 1) AS owner
WHERE parameter_value.game_object_id = game_object.id
  AND parameter_value.parameter_id = parameter.id
  AND parameter.name = 'magic_id'
  AND game_object.name = owner.object_name
  AND parameter_value.value IS DISTINCT FROM owner.magic_id;

-- ----------------------------------------------------------------- the row that owns nothing
DELETE
FROM parameter_values parameter_value
    USING game_objects game_object, parameters parameter
WHERE parameter_value.game_object_id = game_object.id
  AND parameter_value.parameter_id = parameter.id
  AND parameter.name = 'magic_id'
  AND game_object.name = 'slime'
  AND NOT EXISTS (SELECT 1 FROM magics magic WHERE magic.name = game_object.name)
  AND NOT EXISTS (SELECT 1
                  FROM magic_game_object_aliases alias
                  WHERE alias.game_object_name = game_object.name);

-- ------------------------------------------------- the mirrors the deleted row was standing in for
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, magic.id
FROM (VALUES ('ember_spirit_swarm', 'ember_spirit'),
             ('water_slime_swarm', 'water_slime'),
             ('seed_spirit_swarm', 'seed_spirit')) AS pairing(magic_name, object_name)
         JOIN magics magic ON magic.name = pairing.magic_name
         JOIN game_objects game_object ON game_object.name = pairing.object_name
         JOIN parameters parameter ON parameter.name = 'magic_id'
ON CONFLICT (parameter_id, game_object_id)
    DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- --------------------------------------------------------------------------- assertions
DO
$$
    DECLARE
        stray_rows    TEXT;
        pointed_count INTEGER;
        null_count    INTEGER;
    BEGIN
        -- After this file every magic_id row names either the magic the object is called after, or
        -- the magic that magic_game_object_aliases hands that object to. A row outside both is the
        -- fault this migration exists to remove, so it fails here rather than showing up as a magic
        -- quietly reading another magic's numbers.
        SELECT COALESCE(STRING_AGG(game_object.name || ' -> ' || COALESCE(magic.name, '(no magic)'),
                                   ', ' ORDER BY game_object.name), '')
        INTO stray_rows
        FROM parameter_values parameter_value
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 LEFT JOIN magics magic ON magic.id = parameter_value.value
        WHERE parameter.name = 'magic_id'
          AND parameter_value.value IS NOT NULL
          AND magic.name IS DISTINCT FROM game_object.name
          AND NOT EXISTS (SELECT 1
                          FROM magic_game_object_aliases alias
                          WHERE alias.game_object_name = game_object.name
                            AND alias.magic_name = magic.name);

        IF stray_rows <> '' THEN
            RAISE EXCEPTION 'these magic_id rows name a magic that does not own the object: %', stray_rows;
        END IF;

        SELECT COUNT(*) FILTER (WHERE parameter_value.value IS NOT NULL),
               COUNT(*) FILTER (WHERE parameter_value.value IS NULL)
        INTO pointed_count, null_count
        FROM parameter_values parameter_value
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE parameter.name = 'magic_id';

        RAISE NOTICE '% magic_id rows name the magic that owns their object, % hold no value',
            pointed_count, null_count;
    END
$$;
