-- Registers repair_totem: the Build x2 + Nature building that freezes the lifetime countdown of
-- nearby friendly buildings.
--
-- Recipe. {Build, Build, Nature}. DatabaseMagicParser keys magics on the SORTED MULTISET of card
-- name and its init() is a plain map.put, so a duplicate key silently shadows whichever magic was
-- parsed first with nothing logged. Card counts are part of that key, which a WHERE name IN (...)
-- cannot express, so the insert below uses the generate_series form from V069. The precedents for
-- two of one card are dimension_toad (Spawn x2), fire_lord_spirit (Spawn x2) and shock_overload
-- (Lightning x2); the nearest recipe neighbours are life_tree (Build + Nature) and vine_colony
-- (Build + Nature x2). The assertion at the foot rechecks uniqueness against the live database
-- rather than trusting a reconstruction of it from these files.
--
-- magics.cast_type has been NOT NULL with a CHECK since V047, so the magic row carries 'build'.
--
-- Values. hp is derived from life_tree with a subquery rather than written as a literal. This
-- repository's V032 backfill and the live database disagree on the hp scale -- V053 multiplied
-- every hp row by 10 and later live balance passes moved some of them again -- so a literal
-- written from these files would be off by an order of magnitude.
--
--   hp = life_tree.hp x 1.0   The other Nature support building, and the body this one matches.
--
-- Expected value at the time of writing, from the V032 seed of 10 scaled by V053: life_tree hp
-- 100, so repair_totem gets 100. That reconstruction is an estimate, not a claim --
-- magma_spirit's live hp is 2000 where the same arithmetic predicts 2500 -- which is why hp is a
-- subquery.
--
-- radius, duration and mass are literals in world units and seconds, which no migration has
-- rescaled. radius 4.0 is the range within which friendly buildings stop ageing. duration 6.0 is
-- shorter than both life_tree's 8 and electric_tower's 20: a building that suspends other
-- buildings' lifetimes makes them effectively permanent for as long as it stands, so it has to
-- expire before either of them would have. mass 1000000.0 is the building mass V073 gave every
-- CAT_Building object, so evil_ent's pull_mass_limit of 5.0 cannot drag the totem; V073 already
-- ran, so a new building has to carry that value itself.
--
-- Tags. TYPE_Unit for a body on the field and CAT_Building for what it is. No CAT_Ranged or
-- CAT_AoE: the totem has no attack and its effect lands on friendly buildings, not on enemies, so
-- neither role tag describes something an opponent answers.
--
-- No magic_game_object_aliases row is needed: the magic and the object are both named
-- repair_totem.

-- repair_totem's hp is meaningless without life_tree's. Fail before writing a NULL.
DO
$$
    BEGIN
        IF NOT EXISTS (SELECT 1
                       FROM parameter_values parameter_value
                                JOIN game_objects game_object
                                     ON game_object.id = parameter_value.game_object_id
                                JOIN parameters parameter
                                     ON parameter.id = parameter_value.parameter_id
                       WHERE game_object.name = 'life_tree'
                         AND parameter.name = 'hp'
                         AND parameter_value.value IS NOT NULL) THEN
            RAISE EXCEPTION 'life_tree has no hp value; repair_totem derives its hp from it';
        END IF;
    END
$$;

WITH inserted_magic AS (
    INSERT INTO magics(name, cast_type)
    SELECT 'repair_totem', 'build'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'repair_totem'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'repair_totem'
),
recipe_cards(card_name, required_count) AS (
    VALUES
        ('Build', 2),
        ('Nature', 1)
),
target_cards AS (
    SELECT card.id, recipe.required_count
    FROM cards card
    JOIN recipe_cards recipe ON recipe.card_name = card.name
),
existing_magic_cards AS (
    SELECT magic_card.card_id, COUNT(*) AS existing_count
    FROM magic_cards magic_card
    JOIN target_magic magic ON magic.id = magic_card.magic_id
    GROUP BY magic_card.card_id
),
missing_magic_cards AS (
    SELECT target.id
    FROM target_cards target
    LEFT JOIN existing_magic_cards existing ON existing.card_id = target.id
    CROSS JOIN generate_series(
        1,
        GREATEST(target.required_count - COALESCE(existing.existing_count, 0), 0)
    )
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT magic.id, missing.id
FROM target_magic magic
CROSS JOIN missing_magic_cards missing;

WITH inserted_game_object AS (
    INSERT INTO game_objects(name)
    SELECT 'repair_totem'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'repair_totem'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'repair_totem'
),
required_parameters(name) AS (
    VALUES
        ('hp'),
        ('radius'),
        ('duration'),
        ('mass')
),
inserted_parameters AS (
    INSERT INTO parameters(name)
    SELECT required.name
    FROM required_parameters required
    WHERE NOT EXISTS (
        SELECT 1
        FROM parameters parameter
        WHERE parameter.name = required.name
    )
    RETURNING id, name
),
target_parameters AS (
    SELECT id, name FROM inserted_parameters
    UNION ALL
    SELECT parameter.id, parameter.name
    FROM parameters parameter
    JOIN required_parameters required ON required.name = parameter.name
),
life_tree_parameters(name, value) AS (
    SELECT parameter.name, parameter_value.value
    FROM parameter_values parameter_value
    JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
    JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
    WHERE game_object.name = 'life_tree'
),
repair_totem_values(parameter_name, value) AS (
    SELECT 'hp'::TEXT,
           (SELECT value FROM life_tree_parameters WHERE name = 'hp') * 1.0
    UNION ALL
    SELECT 'radius'::TEXT, 4.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'duration'::TEXT, 6.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'mass'::TEXT, 1000000.0::DOUBLE PRECISION
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, seed.value
FROM target_game_object game_object
JOIN target_parameters parameter ON TRUE
JOIN repair_totem_values seed ON seed.parameter_name = parameter.name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(name) AS (
    VALUES
        ('TYPE_Unit'),
        ('CAT_Building')
),
inserted_tags AS (
    INSERT INTO tags(name)
    SELECT required.name
    FROM required_tags required
    WHERE NOT EXISTS (
        SELECT 1
        FROM tags tag
        WHERE tag.name = required.name
    )
    RETURNING id, name
),
target_tags AS (
    SELECT id, name FROM inserted_tags
    UNION ALL
    SELECT tag.id, tag.name
    FROM tags tag
    JOIN required_tags required ON required.name = tag.name
),
target_game_object AS (
    SELECT id
    FROM game_objects
    WHERE name = 'repair_totem'
)
INSERT INTO game_object_tags(game_object_id, tag_id)
SELECT game_object.id, tag.id
FROM target_game_object game_object
JOIN target_tags tag ON TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM game_object_tags existing
    WHERE existing.game_object_id = game_object.id
      AND existing.tag_id = tag.id
);

-- Without this the bot scores repair_totem at the neutral 0.0 and nothing reports it.
SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        recipe            TEXT[];
        colliding_magic   TEXT;
        parameter_count   INTEGER;
        missing_parameter TEXT;
        totem_hp          DOUBLE PRECISION;
        tree_hp           DOUBLE PRECISION;
        totem_duration    DOUBLE PRECISION;
        tree_duration     DOUBLE PRECISION;
        tag_count         INTEGER;
        magic_tag_count   INTEGER;
    BEGIN
        SELECT ARRAY_AGG(card.name::TEXT ORDER BY card.name)
        INTO recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name = 'repair_totem';

        IF recipe IS DISTINCT FROM ARRAY ['Build', 'Build', 'Nature'] THEN
            RAISE EXCEPTION 'repair_totem recipe is %, expected Build x2 + Nature',
                COALESCE(ARRAY_TO_STRING(recipe, ' + '), '(none)');
        END IF;

        -- DatabaseMagicParser.init() keys on the sorted multiset and overwrites on collision
        -- without logging, so a shared recipe silently disables one of the two magics.
        SELECT other.name
        INTO colliding_magic
        FROM (SELECT magic.name,
                     ARRAY_AGG(card.name::TEXT ORDER BY card.name) AS cards
              FROM magics magic
                       JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                       JOIN cards card ON card.id = magic_card.card_id
              GROUP BY magic.name) other
        WHERE other.name <> 'repair_totem'
          AND other.cards = recipe
        LIMIT 1;

        IF colliding_magic IS NOT NULL THEN
            RAISE EXCEPTION 'magic % already owns the recipe %; one of the two would be shadowed',
                colliding_magic, ARRAY_TO_STRING(recipe, ' + ');
        END IF;

        SELECT COUNT(*)
        INTO parameter_count
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
        WHERE game_object.name = 'repair_totem';

        IF parameter_count <> 4 THEN
            RAISE EXCEPTION 'repair_totem has % parameter values, expected 4', parameter_count;
        END IF;

        SELECT expected.name
        INTO missing_parameter
        FROM (VALUES ('radius', 4.0), ('duration', 6.0),
                     ('mass', 1000000.0)) AS expected(name, value)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = 'repair_totem'
                            AND parameter.name = expected.name
                            AND parameter_value.value = expected.value)
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'repair_totem parameter % is missing or holds the wrong value',
                missing_parameter;
        END IF;

        SELECT parameter_value.value
        INTO totem_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'repair_totem'
          AND parameter.name = 'hp';

        SELECT parameter_value.value
        INTO tree_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'life_tree'
          AND parameter.name = 'hp';

        IF totem_hp IS NULL OR tree_hp IS NULL OR ABS(totem_hp - tree_hp) >= 1e-6 THEN
            RAISE EXCEPTION 'repair_totem hp is % but life_tree hp is %; they were meant to match',
                COALESCE(totem_hp::TEXT, '(none)'), COALESCE(tree_hp::TEXT, '(none)');
        END IF;

        -- The totem holds other buildings alive, so outliving the ones it protects defeats it.
        SELECT parameter_value.value
        INTO totem_duration
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'repair_totem'
          AND parameter.name = 'duration';

        SELECT parameter_value.value
        INTO tree_duration
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'life_tree'
          AND parameter.name = 'duration';

        IF tree_duration IS NOT NULL AND totem_duration >= tree_duration THEN
            RAISE EXCEPTION 'repair_totem duration % is not shorter than life_tree duration %',
                totem_duration, tree_duration;
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'repair_totem'
          AND tag.name IN ('TYPE_Unit', 'CAT_Building');

        IF tag_count <> 2 THEN
            RAISE EXCEPTION 'repair_totem carries % of its 2 counter tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO magic_tag_count
        FROM magic_tags magic_tag
                 JOIN magics magic ON magic.id = magic_tag.magic_id
        WHERE magic.name = 'repair_totem';

        IF magic_tag_count < 2 THEN
            RAISE EXCEPTION 'magic repair_totem carries only % tags; the name sync did not reach it',
                magic_tag_count;
        END IF;
    END
$$;
