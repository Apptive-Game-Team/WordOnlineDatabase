-- Registers evil_ent: the Nature x3 + Fire + Spawn upper-tier summon.
--
-- Recipe. tree_golem (Nature x2 + Spawn) with a third Nature and a Fire on top.
-- magic_cards has no unique constraint, so a repeated card is a real recipe element rather
-- than a mistake -- fire_lord_spirit (Fire x2) is the precedent -- and PlayerData.MAX_CARD_NUM
-- is 6, so a five-card cast is reachable. DatabaseMagicParser keys magics on the SORTED
-- MULTISET of card names and its init() does a plain map.put, so a duplicate key silently
-- shadows whichever magic was parsed first, with nothing logged. The recipe therefore has to
-- be globally unique, and the count of each card is part of that key: the inserts below use
-- the generate_series form from V018 rather than a WHERE name IN (...) that cannot express a
-- repeat. {Fire, Nature, Nature, Nature, Spawn} is unused against the authoritative set --
-- V032's DELETE-and-reinsert as amended by V033, V035, V037, V038, V043 and V045 -- and the
-- assertion at the foot of this file rechecks that against the live database rather than
-- trusting the reconstruction. The nearest neighbours are tree_golem (Nature + Nature +
-- Spawn) and vine_world (Explode x2 + Nature x2 + Spawn).
--
-- magics.cast_type has been NOT NULL with no default since V047, so the magic row has to
-- carry it: 'spawn', like every other summon.
--
-- Parameters. sub_* are the special ability. sub_attack_interval is its cooldown in seconds.
-- pull_mass_limit is a mass cutoff -- the ent drags targets lighter than it toward itself and
-- cannot move anything heavier. The mass distribution in this database splits into light mobs
-- at 0.75-3, large mobs at 10 and buildings at 1000-999999, so 5.0 puts the cutoff above every
-- light mob and below the golem class and all terrain.
--
-- Tags. TYPE_Unit for a body on the field, CAT_Ranged for the projectile attack, CAT_Large for
-- a 180 hp golem-mass body, CAT_CC because the pull is crowd control -- which is also the tag
-- the ('CAT_CC', 'CAT_Large') and ('CAT_CC', 'CAT_Tank') rules seeded by V056 read. No element
-- tag: ElementalChart on the game server owns that table.
--
-- No magic_game_object_aliases row is needed. The magic and the object are both named
-- evil_ent, so the name join in sync_magic_tags_from_game_objects() reaches it directly; an
-- alias is for the swarm and legacy magics whose names differ from their object's.

WITH inserted_magic AS (
    INSERT INTO magics(name, cast_type)
    SELECT 'evil_ent', 'spawn'
    WHERE NOT EXISTS (
        SELECT 1
        FROM magics
        WHERE name = 'evil_ent'
    )
    RETURNING id
),
target_magic AS (
    SELECT id FROM inserted_magic
    UNION ALL
    SELECT id
    FROM magics
    WHERE name = 'evil_ent'
),
recipe_cards(card_name, required_count) AS (
    VALUES
        ('Nature', 3),
        ('Fire', 1),
        ('Spawn', 1)
),
target_cards AS (
    SELECT c.id, rc.required_count
    FROM cards c
    JOIN recipe_cards rc ON rc.card_name = c.name
),
existing_magic_cards AS (
    SELECT mc.card_id, COUNT(*) AS existing_count
    FROM magic_cards mc
    JOIN target_magic tm ON tm.id = mc.magic_id
    GROUP BY mc.card_id
),
missing_magic_cards AS (
    SELECT tc.id
    FROM target_cards tc
    LEFT JOIN existing_magic_cards emc ON emc.card_id = tc.id
    CROSS JOIN generate_series(1, GREATEST(tc.required_count - COALESCE(emc.existing_count, 0), 0))
)
INSERT INTO magic_cards(magic_id, card_id)
SELECT tm.id, mmc.id
FROM target_magic tm
CROSS JOIN missing_magic_cards mmc;

WITH inserted_game_object AS (
    INSERT INTO game_objects(name)
    SELECT 'evil_ent'
    WHERE NOT EXISTS (
        SELECT 1
        FROM game_objects
        WHERE name = 'evil_ent'
    )
    RETURNING id
),
target_game_object AS (
    SELECT id FROM inserted_game_object
    UNION ALL
    SELECT id
    FROM game_objects
    WHERE name = 'evil_ent'
),
required_parameters(name) AS (
    VALUES
        ('mass'),
        ('radius'),
        ('hp'),
        ('speed'),
        ('damage'),
        ('attack_interval'),
        ('attack_range'),
        ('projectile_speed'),
        ('sub_damage'),
        ('sub_attack_range'),
        ('sub_speed'),
        ('sub_attack_interval'),
        ('pull_mass_limit'),
        ('quantity')
),
inserted_parameters AS (
    INSERT INTO parameters(name)
    SELECT rp.name
    FROM required_parameters rp
    WHERE NOT EXISTS (
        SELECT 1
        FROM parameters p
        WHERE p.name = rp.name
    )
    RETURNING id, name
),
target_parameters AS (
    SELECT id, name FROM inserted_parameters
    UNION ALL
    SELECT p.id, p.name
    FROM parameters p
    JOIN required_parameters rp ON rp.name = p.name
),
evil_ent_values(parameter_name, value) AS (
    VALUES
        ('mass', 10.0),
        ('radius', 1.2),
        ('hp', 180.0),
        ('speed', 0.45),
        ('damage', 9.0),
        ('attack_interval', 1.8),
        ('attack_range', 5.0),
        ('projectile_speed', 14.0),
        ('sub_damage', 28.0),
        ('sub_attack_range', 6.0),
        ('sub_speed', 4.0),
        ('sub_attack_interval', 12.0),
        ('pull_mass_limit', 5.0),
        ('quantity', 1.0)
)
INSERT INTO parameter_values(game_object_id, parameter_id, value)
SELECT tgo.id, tp.id, eev.value
FROM target_game_object tgo
JOIN target_parameters tp ON TRUE
JOIN evil_ent_values eev ON eev.parameter_name = tp.name
ON CONFLICT (parameter_id, game_object_id)
DO UPDATE SET value = EXCLUDED.value;

WITH required_tags(name) AS (
    VALUES
        ('TYPE_Unit'),
        ('CAT_Ranged'),
        ('CAT_Large'),
        ('CAT_CC')
),
inserted_tags AS (
    INSERT INTO tags(name)
    SELECT rt.name
    FROM required_tags rt
    WHERE NOT EXISTS (
        SELECT 1
        FROM tags t
        WHERE t.name = rt.name
    )
    RETURNING id, name
),
target_tags AS (
    SELECT id, name FROM inserted_tags
    UNION ALL
    SELECT t.id, t.name
    FROM tags t
    JOIN required_tags rt ON rt.name = t.name
),
target_game_object AS (
    SELECT id
    FROM game_objects
    WHERE name = 'evil_ent'
)
INSERT INTO game_object_tags(game_object_id, tag_id)
SELECT tgo.id, tt.id
FROM target_game_object tgo
JOIN target_tags tt ON TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM game_object_tags got
    WHERE got.game_object_id = tgo.id
      AND got.tag_id = tt.id
);

-- Derives magic_tags from the game object tags above, through the shared name.
SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        recipe            TEXT[];
        colliding_magic   TEXT;
        parameter_count   INTEGER;
        missing_parameter TEXT;
        tag_count         INTEGER;
        magic_tag_count   INTEGER;
    BEGIN
        SELECT ARRAY_AGG(card.name::TEXT ORDER BY card.name)
        INTO recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name = 'evil_ent';

        IF recipe IS DISTINCT FROM ARRAY ['Fire', 'Nature', 'Nature', 'Nature', 'Spawn'] THEN
            RAISE EXCEPTION 'evil_ent recipe is %, expected Fire + Nature x3 + Spawn',
                COALESCE(ARRAY_TO_STRING(recipe, ' + '), '(none)');
        END IF;

        -- DatabaseMagicParser.init() keys on the sorted multiset and overwrites on collision
        -- without logging, so a shared recipe silently disables one of the two magics.
        SELECT other.name
        INTO colliding_magic
        FROM (SELECT magic.name, ARRAY_AGG(card.name::TEXT ORDER BY card.name) AS cards
              FROM magics magic
                       JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                       JOIN cards card ON card.id = magic_card.card_id
              GROUP BY magic.name) other
        WHERE other.name <> 'evil_ent'
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
        WHERE game_object.name = 'evil_ent';

        IF parameter_count <> 14 THEN
            RAISE EXCEPTION 'evil_ent has % parameter values, expected 14', parameter_count;
        END IF;

        SELECT expected.name
        INTO missing_parameter
        FROM (VALUES ('mass', 10.0), ('radius', 1.2), ('hp', 180.0), ('speed', 0.45),
                     ('damage', 9.0), ('attack_interval', 1.8), ('attack_range', 5.0),
                     ('projectile_speed', 14.0), ('sub_damage', 28.0), ('sub_attack_range', 6.0),
                     ('sub_speed', 4.0), ('sub_attack_interval', 12.0), ('pull_mass_limit', 5.0),
                     ('quantity', 1.0)) AS expected(name, value)
        WHERE NOT EXISTS (SELECT 1
                          FROM parameter_values parameter_value
                                   JOIN game_objects game_object
                                        ON game_object.id = parameter_value.game_object_id
                                   JOIN parameters parameter
                                        ON parameter.id = parameter_value.parameter_id
                          WHERE game_object.name = 'evil_ent'
                            AND parameter.name = expected.name
                            AND parameter_value.value = expected.value)
        LIMIT 1;

        IF missing_parameter IS NOT NULL THEN
            RAISE EXCEPTION 'evil_ent parameter % is missing or holds the wrong value',
                missing_parameter;
        END IF;

        SELECT COUNT(*)
        INTO tag_count
        FROM game_object_tags game_object_tag
                 JOIN game_objects game_object ON game_object.id = game_object_tag.game_object_id
                 JOIN tags tag ON tag.id = game_object_tag.tag_id
        WHERE game_object.name = 'evil_ent'
          AND tag.name IN ('TYPE_Unit', 'CAT_Ranged', 'CAT_Large', 'CAT_CC');

        IF tag_count <> 4 THEN
            RAISE EXCEPTION 'evil_ent carries % of its 4 counter tags', tag_count;
        END IF;

        -- Without this the bot scores evil_ent at the neutral 0.0 and nothing reports it.
        SELECT COUNT(*)
        INTO magic_tag_count
        FROM magic_tags magic_tag
                 JOIN magics magic ON magic.id = magic_tag.magic_id
        WHERE magic.name = 'evil_ent';

        IF magic_tag_count < 4 THEN
            RAISE EXCEPTION 'magic evil_ent carries only % tags; the name sync did not reach it',
                magic_tag_count;
        END IF;
    END
$$;
