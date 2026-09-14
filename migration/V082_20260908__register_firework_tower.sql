-- Registers firework_tower and firework_shell: the Build + Drop + Fire tower that keeps dropping
-- explosions at a fixed point 3 in front of where it was placed.
--
-- Recipe. {Build, Drop, Fire}. DatabaseMagicParser keys magics on the SORTED MULTISET of card
-- names and its init() is a plain map.put, so a duplicate key silently shadows whichever magic was
-- parsed first with nothing logged. The nearest neighbours are crater (Build + Fire + Rock),
-- rallying_torch (Drop + Fire) and frenzy_totem (Drop + Fire + Nature). The assertion at the foot
-- rechecks uniqueness against the live database rather than trusting a reconstruction of it from
-- these files. The insert uses the generate_series form from V069 so that card counts stay
-- expressible.
--
-- magics.cast_type has been NOT NULL with a CHECK since V047, so the magic row carries 'build'.
--
-- Two objects. The magic is firework_tower and the explosion it drops is firework_shell, so only
-- firework_tower is reached by the name join in sync_magic_tags_from_game_objects().
-- firework_shell is not a magic, so it needs no magic_game_object_aliases row; it is tagged
-- directly like any other field object.
--
-- Values. hp and damage are derived with subqueries rather than written as literals. This
-- repository's V032 backfill and the live database disagree on the hp and damage scale -- V053
-- multiplied every hp and %damage% row by 10 and later live balance passes moved some of them
-- again -- so literals written from these files would be off by an order of magnitude.
--
--   firework_tower.hp     = crater.hp x 1.0        The other Build structure that bombards a
--                                                  fixed spot rather than aiming at a target.
--   firework_shell.damage = crater_ember.damage x 1.0
--                                                  crater_ember is the same thing: an untargeted
--                                                  repeating explosion, so its per-hit damage is
--                                                  the right low number to copy.
--
-- Expected values at the time of writing, from V032 seeds scaled by V053: crater hp 150 and
-- crater_ember damage 30, so firework_tower gets hp 150 and firework_shell damage 30. That
-- reconstruction is an estimate, not a claim -- magma_spirit's live hp is 2000 where the same
-- arithmetic predicts 2500 -- which is why both are subqueries.
--
-- attack_interval, attack_range, attack_offset, radius, duration and mass are literals in world
-- units and seconds, which no migration has rescaled. attack_interval 1.0 is far above crater's
-- 0.25, which V037 lowered it to; the shells land once a second, not four times. duration 20.0 on
-- the tower matches electric_tower rather than crater's 40, keeping a new building in the common
-- band. duration 1.0 on the shell is the explosion's own life. mass 1000000.0 is the building mass
-- V073 gave every CAT_Building object, so evil_ent's pull_mass_limit of 5.0 cannot drag the tower;
-- V073 already ran, so a new building has to carry that value itself. firework_shell gets no mass:
-- it is an explosion, not a body that anything pushes.
--
-- Indicator contract. The client draws the placement point and the point that gets hit together,
-- and both values live on the tower's own game object.
--
--   attack_range  = 1.5  the radius of the explosion
--   attack_offset = 3.0  how far in front of the placement point the shells land
--
-- The name 'range' must not be used here. GameParameterResolver.TryGetMagicParameter looks up
-- 'range' under the cast type family name 'build' before it falls back to the magic name, so a
-- range row on the tower would never be read: build.range wins, and build.range is the placement
-- distance and has to stay as it is. No other parameter name has that fallback, so attack_range
-- and attack_offset resolve against the magic name directly. The assertion at the foot fails if a
-- range row ever appears on firework_tower.
--
-- firework_tower.attack_range and firework_shell.radius are the same number by contract: the first
-- is what the indicator draws, the second is what actually explodes. Changing one alone leaves the
-- client drawing a circle that does not match the blast, with no error anywhere, so the assertion
-- at the foot compares the two rows in the database rather than trusting that both literals above
-- were edited together.
--
-- Tags. firework_tower gets TYPE_Unit, CAT_Building and CAT_Ranged -- it reaches a point away from
-- itself. firework_shell gets TYPE_Unit and CAT_AoE for the blast radius.

-- firework_tower's hp and firework_shell's damage are meaningless without their siblings'. Fail
-- before writing NULLs.
DO
$$
    DECLARE
        missing_sibling TEXT;
    BEGIN
        SELECT expected.object_name || '.' || expected.parameter_name
        INTO missing_sibling
        FROM (VALUES ('crater', 'hp'),
                     ('crater_ember', 'damage')) AS expected(object_name, parameter_name)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = expected.object_name
                            AND parameter.name = expected.parameter_name
                            AND parameter_value.value IS NOT NULL)
        LIMIT 1;

        IF missing_sibling IS NOT NULL THEN
            RAISE EXCEPTION '% is missing; firework_tower and firework_shell derive their hp and damage from it',
                missing_sibling;
        END IF;
    END
$$;

WITH inserted_magic AS (
    INSERT INTO magics(name, cast_type)
    SELECT 'firework_tower', 'build'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'firework_tower'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'firework_tower'
),
recipe_cards(card_name, required_count) AS (
    VALUES
        ('Build', 1),
        ('Drop', 1),
        ('Fire', 1)
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

-- attack_offset is a new name in the parameters table; the rest already exist.
INSERT INTO parameters(name)
SELECT required.name
FROM (VALUES ('hp'),
             ('damage'),
             ('radius'),
             ('attack_interval'),
             ('attack_range'),
             ('attack_offset'),
             ('duration'),
             ('mass')) AS required(name)
WHERE NOT EXISTS (
    SELECT 1
    FROM parameters parameter
    WHERE parameter.name = required.name
);

INSERT INTO game_objects(name)
SELECT required.name
FROM (VALUES ('firework_tower'), ('firework_shell')) AS required(name)
WHERE NOT EXISTS (
    SELECT 1
    FROM game_objects game_object
    WHERE game_object.name = required.name
);

WITH crater_parameters(name, value) AS (
    SELECT parameter.name, parameter_value.value
    FROM parameter_values parameter_value
    JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
    JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
    WHERE game_object.name = 'crater'
),
crater_ember_parameters(name, value) AS (
    SELECT parameter.name, parameter_value.value
    FROM parameter_values parameter_value
    JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
    JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
    WHERE game_object.name = 'crater_ember'
),
firework_values(game_object_name, parameter_name, value) AS (
    SELECT 'firework_tower'::TEXT, 'hp'::TEXT,
           (SELECT value FROM crater_parameters WHERE name = 'hp') * 1.0
    UNION ALL
    SELECT 'firework_tower'::TEXT, 'attack_interval'::TEXT, 1.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'firework_tower'::TEXT, 'attack_range'::TEXT, 1.5::DOUBLE PRECISION
    UNION ALL
    SELECT 'firework_tower'::TEXT, 'attack_offset'::TEXT, 3.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'firework_tower'::TEXT, 'duration'::TEXT, 20.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'firework_tower'::TEXT, 'mass'::TEXT, 1000000.0::DOUBLE PRECISION
    UNION ALL
    SELECT 'firework_shell'::TEXT, 'damage'::TEXT,
           (SELECT value FROM crater_ember_parameters WHERE name = 'damage') * 1.0
    UNION ALL
    SELECT 'firework_shell'::TEXT, 'radius'::TEXT, 1.5::DOUBLE PRECISION
    UNION ALL
    SELECT 'firework_shell'::TEXT, 'duration'::TEXT, 1.0::DOUBLE PRECISION
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT game_object.id, parameter.id, seed.value
FROM firework_values seed
JOIN game_objects game_object ON game_object.name = seed.game_object_name
JOIN parameters parameter ON parameter.name = seed.parameter_name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(game_object_name, tag_name) AS (
    VALUES
        ('firework_tower', 'TYPE_Unit'),
        ('firework_tower', 'CAT_Building'),
        ('firework_tower', 'CAT_Ranged'),
        ('firework_shell', 'TYPE_Unit'),
        ('firework_shell', 'CAT_AoE')
),
inserted_tags AS (
    INSERT INTO tags(name)
    SELECT DISTINCT required.tag_name
    FROM required_tags required
    WHERE NOT EXISTS (
        SELECT 1
        FROM tags tag
        WHERE tag.name = required.tag_name
    )
    RETURNING id, name
)
INSERT INTO game_object_tags(game_object_id, tag_id)
SELECT game_object.id, tag.id
FROM required_tags required
JOIN game_objects game_object ON game_object.name = required.game_object_name
JOIN (
    SELECT id, name FROM inserted_tags
    UNION ALL
    SELECT id, name FROM tags
) tag ON tag.name = required.tag_name
WHERE NOT EXISTS (
    SELECT 1
    FROM game_object_tags existing
    WHERE existing.game_object_id = game_object.id
      AND existing.tag_id = tag.id
);

-- Without this the bot scores firework_tower at the neutral 0.0 and nothing reports it.
SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        recipe             TEXT[];
        colliding_magic    TEXT;
        parameter_count    INTEGER;
        missing_parameter  TEXT;
        tower_hp           DOUBLE PRECISION;
        crater_hp          DOUBLE PRECISION;
        shell_damage       DOUBLE PRECISION;
        ember_damage       DOUBLE PRECISION;
        indicator_range    DOUBLE PRECISION;
        blast_radius       DOUBLE PRECISION;
        tag_count          INTEGER;
        magic_tag_count    INTEGER;
    BEGIN
        SELECT ARRAY_AGG(card.name::TEXT ORDER BY card.name)
        INTO recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name = 'firework_tower';

        IF recipe IS DISTINCT FROM ARRAY ['Build', 'Drop', 'Fire'] THEN
            RAISE EXCEPTION 'firework_tower recipe is %, expected Build + Drop + Fire',
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
        WHERE other.name <> 'firework_tower'
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
        WHERE game_object.name = 'firework_tower';

        IF parameter_count <> 6 THEN
            RAISE EXCEPTION 'firework_tower has % parameter values, expected 6', parameter_count;
        END IF;

        SELECT COUNT(*)
        INTO parameter_count
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
        WHERE game_object.name = 'firework_shell';

        IF parameter_count <> 3 THEN
            RAISE EXCEPTION 'firework_shell has % parameter values, expected 3', parameter_count;
        END IF;

        SELECT expected.game_object_name || '.' || expected.parameter_name
        INTO missing_parameter
        FROM (VALUES ('firework_tower', 'attack_interval', 1.0),
                     ('firework_tower', 'attack_range', 1.5),
                     ('firework_tower', 'attack_offset', 3.0),
                     ('firework_tower', 'duration', 20.0),
                     ('firework_tower', 'mass', 1000000.0),
                     ('firework_shell', 'radius', 1.5),
                     ('firework_shell', 'duration', 1.0))
                 AS expected(game_object_name, parameter_name, value)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = expected.game_object_name
                            AND parameter.name = expected.parameter_name
                            AND parameter_value.value = expected.value)
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'parameter % is missing or holds the wrong value', missing_parameter;
        END IF;

        -- GameParameterResolver.TryGetMagicParameter resolves 'range' against the cast type family
        -- 'build' first, so a range row here would be read as the placement distance instead of
        -- the blast radius, and the indicator would draw the wrong circle.
        IF EXISTS (SELECT 1
                   FROM parameter_values parameter_value
                            JOIN game_objects game_object
                                 ON game_object.id = parameter_value.game_object_id
                            JOIN parameters parameter
                                 ON parameter.id = parameter_value.parameter_id
                   WHERE game_object.name = 'firework_tower'
                     AND parameter.name = 'range') THEN
            RAISE EXCEPTION 'firework_tower carries a range parameter; build.range shadows it, use attack_range and attack_offset';
        END IF;

        -- The indicator circle and the real blast are two rows that must hold one number.
        SELECT parameter_value.value
        INTO indicator_range
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'firework_tower'
          AND parameter.name = 'attack_range';

        SELECT parameter_value.value
        INTO blast_radius
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'firework_shell'
          AND parameter.name = 'radius';

        IF indicator_range IS NULL OR blast_radius IS NULL
            OR indicator_range <> blast_radius THEN
            RAISE EXCEPTION 'firework_tower attack_range is % but firework_shell radius is %; the client indicator would not match the blast',
                COALESCE(indicator_range::TEXT, '(none)'), COALESCE(blast_radius::TEXT, '(none)');
        END IF;

        SELECT parameter_value.value
        INTO tower_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'firework_tower'
          AND parameter.name = 'hp';

        SELECT parameter_value.value
        INTO crater_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'crater'
          AND parameter.name = 'hp';

        IF tower_hp IS NULL OR crater_hp IS NULL OR ABS(tower_hp - crater_hp) >= 1e-6 THEN
            RAISE EXCEPTION 'firework_tower hp is % but crater hp is %; they were meant to match',
                COALESCE(tower_hp::TEXT, '(none)'), COALESCE(crater_hp::TEXT, '(none)');
        END IF;

        SELECT parameter_value.value
        INTO shell_damage
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'firework_shell'
          AND parameter.name = 'damage';

        SELECT parameter_value.value
        INTO ember_damage
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'crater_ember'
          AND parameter.name = 'damage';

        IF shell_damage IS NULL OR ember_damage IS NULL
            OR ABS(shell_damage - ember_damage) >= 1e-6 THEN
            RAISE EXCEPTION 'firework_shell damage is % but crater_ember damage is %; they were meant to match',
                COALESCE(shell_damage::TEXT, '(none)'), COALESCE(ember_damage::TEXT, '(none)');
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'firework_tower'
          AND tag.name IN ('TYPE_Unit', 'CAT_Building', 'CAT_Ranged');

        IF tag_count <> 3 THEN
            RAISE EXCEPTION 'firework_tower carries % of its 3 counter tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'firework_shell'
          AND tag.name IN ('TYPE_Unit', 'CAT_AoE');

        IF tag_count <> 2 THEN
            RAISE EXCEPTION 'firework_shell carries % of its 2 counter tags', tag_count;
        END IF;

        SELECT COUNT(*)
        INTO magic_tag_count
        FROM magic_tags magic_tag
                 JOIN magics magic ON magic.id = magic_tag.magic_id
        WHERE magic.name = 'firework_tower';

        IF magic_tag_count < 3 THEN
            RAISE EXCEPTION 'magic firework_tower carries only % tags; the name sync did not reach it',
                magic_tag_count;
        END IF;
    END
$$;
