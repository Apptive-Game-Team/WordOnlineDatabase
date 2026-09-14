-- Raises magma_spirit to a five-card recipe and lowers its hp to 1750.
--
-- Recipe. V032 backfilled magma_spirit as Explode + Fire x2 + Rock + Spawn; V043 deleted the
-- second Fire and left a four-card magic. This file puts that Fire back, so the recipe becomes
-- {Explode, Fire, Fire, Rock, Spawn}. PlayerData.MAX_CARD_NUM is 6, so five cards are castable,
-- and PlayerData sums each card's mana_cost parameter, so the price rises on its own and no
-- per-magic price row exists to update. fire_lord_spirit is the precedent for two Fire cards;
-- evil_ent (V069) and sea_serpent (V070) are the five-card precedents.
--
-- DatabaseMagicParser keys magics on the SORTED MULTISET of card names and init() is a plain
-- map.put, so a shared recipe silently shadows whichever magic was parsed first, with nothing
-- logged. Card counts are part of that key, which a WHERE name IN (...) cannot express, so the
-- insert below uses the generate_series form from V069. The assertion at the foot rechecks
-- uniqueness against the live database rather than trusting a reconstruction of it from these
-- files.
--
-- hp. MagmaSpiritPrefabInitializer reads magma_spirit's hp and hands it to SummonerMob;
-- magma_fist carries no hp row. 1750 is a target the balance pass chose, so it is a literal
-- rather than a multiple of a sibling object. The value it replaces is 2000: this repository's
-- V032 seeds 250 and V053 multiplied every hp row by 10, which would predict 2500, so the
-- reconstruction is off by 500 here and the pre-check below reports what it actually finds
-- instead of asserting the baseline.

DO
$$
    DECLARE
        current_hp DOUBLE PRECISION;
    BEGIN
        SELECT parameter_value.value
        INTO current_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'magma_spirit'
          AND parameter.name = 'hp';

        IF current_hp IS NULL THEN
            RAISE EXCEPTION 'magma_spirit has no hp value to lower';
        END IF;

        IF current_hp <> 2000 AND current_hp <> 1750 THEN
            RAISE WARNING 'magma_spirit hp was %, not the 2000 this migration was written against; 1750 was chosen from a 2000 baseline',
                current_hp;
        END IF;
    END
$$;

WITH target_magic AS (
    SELECT id
    FROM magics
    WHERE name = 'magma_spirit'
),
recipe_cards(card_name, required_count) AS (
    VALUES
        ('Explode', 1),
        ('Fire', 2),
        ('Rock', 1),
        ('Spawn', 1)
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

UPDATE parameter_values pv
SET value = updates.value
FROM game_objects go
JOIN (
    VALUES
        ('magma_spirit', 'hp', 1750)
) AS updates(game_object_name, parameter_name, value)
    ON updates.game_object_name = go.name
JOIN parameters p
    ON p.name = updates.parameter_name
WHERE pv.game_object_id = go.id
  AND pv.parameter_id = p.id;

DO
$$
    DECLARE
        recipe          TEXT[];
        colliding_magic TEXT;
        current_hp      DOUBLE PRECISION;
    BEGIN
        SELECT ARRAY_AGG(card.name::TEXT ORDER BY card.name)
        INTO recipe
        FROM magics magic
                 JOIN magic_cards magic_card ON magic_card.magic_id = magic.id
                 JOIN cards card ON card.id = magic_card.card_id
        WHERE magic.name = 'magma_spirit';

        IF recipe IS DISTINCT FROM ARRAY ['Explode', 'Fire', 'Fire', 'Rock', 'Spawn'] THEN
            RAISE EXCEPTION 'magma_spirit recipe is %, expected Explode + Fire x2 + Rock + Spawn',
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
        WHERE other.name <> 'magma_spirit'
          AND other.cards = recipe
        LIMIT 1;

        IF colliding_magic IS NOT NULL THEN
            RAISE EXCEPTION 'magic % already owns the recipe %; one of the two would be shadowed',
                colliding_magic, ARRAY_TO_STRING(recipe, ' + ');
        END IF;

        SELECT parameter_value.value
        INTO current_hp
        FROM parameter_values parameter_value
                 JOIN game_objects game_object ON game_object.id = parameter_value.game_object_id
                 JOIN parameters parameter ON parameter.id = parameter_value.parameter_id
        WHERE game_object.name = 'magma_spirit'
          AND parameter.name = 'hp';

        IF current_hp IS DISTINCT FROM 1750::DOUBLE PRECISION THEN
            RAISE EXCEPTION 'magma_spirit hp is %, expected 1750',
                COALESCE(current_hp::TEXT, '(none)');
        END IF;
    END
$$;
