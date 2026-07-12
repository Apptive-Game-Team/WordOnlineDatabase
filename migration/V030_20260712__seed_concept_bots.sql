CREATE TEMP TABLE concept_bot_seed (
    user_id BIGINT PRIMARY KEY,
    concept_name VARCHAR(31) NOT NULL,
    tier bot_tier NOT NULL,
    bot_name VARCHAR(50) NOT NULL,
    deck_name VARCHAR(31) NOT NULL,
    thinking_time_ms INTEGER NOT NULL,
    reaction_interval_frames INTEGER NOT NULL,
    counter_aggression DOUBLE PRECISION NOT NULL,
    mmr SMALLINT NOT NULL,
    card_names VARCHAR(10)[] NOT NULL
) ON COMMIT DROP;

-- Preserve existing bot identities and decks for admin inspection, but remove them from matchmaking.
UPDATE bot_personas
SET enabled = FALSE,
    updated_at = CURRENT_TIMESTAMP
WHERE enabled = TRUE;

WITH concepts(concept_order, concept_name, deck_name, card_names, tier_names) AS (
    VALUES
        (1, 'Emperor of the Skies', 'Skies', ARRAY['Wind', 'Lightning', 'Shoot', 'Spawn', 'Drop']::VARCHAR(10)[], ARRAY['Sky Hatchling', 'Cloud Cadet', 'Storm Captain', 'Tempest Regent', 'Celestial Emperor']::VARCHAR(50)[]),
        (2, 'Magma Maniac', 'Magma', ARRAY['Fire', 'Rock', 'Build', 'Explode', 'Drop']::VARCHAR(10)[], ARRAY['Ember Tinkerer', 'Lava Enthusiast', 'Magma Addict', 'Caldera Fanatic', 'Volcanic Maniac']::VARCHAR(50)[]),
        (3, 'Face Hunter', 'Face', ARRAY['Fire', 'Lightning', 'Shoot', 'Explode', 'Drop']::VARCHAR(10)[], ARRAY['Reckless Rookie', 'Face Rusher', 'Relentless Striker', 'Lethal Hunter', 'Facebreaker']::VARCHAR(50)[]),
        (4, 'Minion Master', 'Minions', ARRAY['Lightning', 'Nature', 'Spawn', 'Drop', 'Build']::VARCHAR(10)[], ARRAY['Tiny Wrangler', 'Swarm Keeper', 'Minion Tactician', 'Horde Commander', 'Minion Master']::VARCHAR(50)[]),
        (5, 'Grass Gym Leader', 'Grass', ARRAY['Nature', 'Wind', 'Spawn', 'Explode', 'Drop']::VARCHAR(10)[], ARRAY['Sprout Scout', 'Vine Trainer', 'Grove Keeper', 'Verdant Captain', 'Grass Gym Leader']::VARCHAR(50)[]),
        (6, 'Shock Supreme', 'Shock', ARRAY['Lightning', 'Water', 'Shoot', 'Build', 'Explode']::VARCHAR(10)[], ARRAY['Static Spark', 'Volt Rookie', 'Thunder Charger', 'Lightning Ace', 'Shock Supreme']::VARCHAR(50)[]),
        (7, 'Water Bomb Maniac', 'Water Bomb', ARRAY['Water', 'Wind', 'Build', 'Explode', 'Drop']::VARCHAR(10)[], ARRAY['Splash Rookie', 'Bubble Bomber', 'Torrent Blaster', 'Tidal Demolitionist', 'Water Bomb Maniac']::VARCHAR(50)[]),
        (8, 'Summoner', 'Summoner', ARRAY['Lightning', 'Nature', 'Spawn', 'Build', 'Drop']::VARCHAR(10)[], ARRAY['Novice Caller', 'Familiar Keeper', 'Spirit Invoker', 'Rift Conjurer', 'Grand Summoner']::VARCHAR(50)[]),
        (9, 'Golem Summoner', 'Golems', ARRAY['Rock', 'Fire', 'Spawn', 'Build', 'Drop']::VARCHAR(10)[], ARRAY['Pebble Caller', 'Minirock Keeper', 'Stone Shaper', 'Golem Architect', 'Colossus Summoner']::VARCHAR(50)[])
),
tiers(tier_order, tier, thinking_time_ms, reaction_interval_frames, counter_aggression, mmr) AS (
    VALUES
        (1, 'INTRO'::bot_tier, 1200, 24, 0.10::DOUBLE PRECISION, 600::SMALLINT),
        (2, 'BEGINNER'::bot_tier, 850, 16, 0.25::DOUBLE PRECISION, 800::SMALLINT),
        (3, 'INTERMEDIATE'::bot_tier, 500, 10, 0.50::DOUBLE PRECISION, 1000::SMALLINT),
        (4, 'ADVANCED'::bot_tier, 250, 6, 0.75::DOUBLE PRECISION, 1200::SMALLINT),
        (5, 'ELITE'::bot_tier, 75, 2, 0.95::DOUBLE PRECISION, 1400::SMALLINT)
)
INSERT INTO concept_bot_seed(
    user_id, concept_name, tier, bot_name, deck_name,
    thinking_time_ms, reaction_interval_frames, counter_aggression, mmr, card_names
)
SELECT
    allocate_bot_user_id(),
    concept_name,
    tier,
    tier_names[tier_order],
    deck_name || ' · ' || tier::TEXT,
    thinking_time_ms,
    reaction_interval_frames,
    counter_aggression,
    mmr,
    card_names
FROM concepts
CROSS JOIN tiers
ORDER BY concept_order, tier_order;

INSERT INTO users(id, mmr, status)
SELECT user_id, mmr, 'Online'
FROM concept_bot_seed;

INSERT INTO decks(name, user_id)
SELECT deck_name, user_id
FROM concept_bot_seed;

UPDATE users bot_user
SET selected_deck_id = bot_deck.id
FROM decks bot_deck
WHERE bot_user.id = bot_deck.user_id
  AND bot_user.id IN (SELECT user_id FROM concept_bot_seed);

INSERT INTO bot_personas(
    user_id, name, tier, thinking_time_ms, reaction_interval_frames,
    counter_aggression, enabled
)
SELECT
    user_id, bot_name, tier, thinking_time_ms, reaction_interval_frames,
    counter_aggression, TRUE
FROM concept_bot_seed;

INSERT INTO deck_cards(deck_id, card_id, count)
SELECT bot_deck.id, card.id, 3
FROM concept_bot_seed seed
JOIN decks bot_deck ON bot_deck.user_id = seed.user_id
CROSS JOIN LATERAL unnest(seed.card_names) AS requested_card(name)
JOIN cards card ON card.name = requested_card.name;

DO $$
DECLARE
    invalid_deck_count INTEGER;
BEGIN
    IF (SELECT COUNT(*) FROM concept_bot_seed) <> 45 THEN
        RAISE EXCEPTION 'Expected 45 concept bots in seed';
    END IF;

    IF (SELECT COUNT(*) FROM users WHERE id IN (SELECT user_id FROM concept_bot_seed)) <> 45
       OR (SELECT COUNT(*) FROM bot_personas WHERE user_id IN (SELECT user_id FROM concept_bot_seed)) <> 45
       OR (SELECT COUNT(*) FROM decks WHERE user_id IN (SELECT user_id FROM concept_bot_seed)) <> 45 THEN
        RAISE EXCEPTION 'Concept bot user, persona, or deck count is incomplete';
    END IF;

    SELECT COUNT(*)
    INTO invalid_deck_count
    FROM (
        SELECT
            deck.id,
            SUM(deck_card.count) AS total_cards,
            MAX(deck_card.count) AS max_copies,
            COUNT(DISTINCT deck_card.card_id) FILTER (WHERE card.card_type = 'Magic') AS magic_types,
            COUNT(DISTINCT deck_card.card_id) FILTER (WHERE card.card_type = 'Type') AS element_types
        FROM decks deck
        JOIN deck_cards deck_card ON deck_card.deck_id = deck.id
        JOIN cards card ON card.id = deck_card.card_id
        WHERE deck.user_id IN (SELECT user_id FROM concept_bot_seed)
        GROUP BY deck.id
        HAVING SUM(deck_card.count) <> 15
            OR MAX(deck_card.count) > 3
            OR COUNT(DISTINCT deck_card.card_id) FILTER (WHERE card.card_type = 'Magic') < 3
            OR COUNT(DISTINCT deck_card.card_id) FILTER (WHERE card.card_type = 'Type') < 2
    ) invalid_decks;

    IF invalid_deck_count <> 0
       OR (SELECT COUNT(*) FROM deck_cards
           WHERE deck_id IN (
               SELECT id FROM decks WHERE user_id IN (SELECT user_id FROM concept_bot_seed)
           )) <> 225 THEN
        RAISE EXCEPTION 'One or more concept bot decks violate deck construction rules';
    END IF;
END
$$;
