-- The single hospitality bot: the opponent a new player meets at the end of the tutorial.
--
-- Its deck is the mechanism behind "low-grade summons only". Spawn is the one Magic-type
-- card in it, so no recipe the bot can assemble is anything but a summon -- there is no
-- shot, drop, or explosion available to it at all. The element cards are the four with the
-- cheapest early summons. Recipe length is capped separately by the game server, because a
-- deck constrains which cards are drawn, not how many of them end up in one recipe.
--
-- counter_aggression is -1.0: among the summons it can afford, the bot prefers the one the
-- player's board answers best. It loses to what is already on the field, which is the point,
-- while still putting a real unit down every time.

DO
$$
    DECLARE
        hospitality_user_id BIGINT;
        hospitality_deck_id BIGINT;
        seeded_card_count   INTEGER;
    BEGIN
        IF EXISTS (SELECT 1 FROM bot_personas WHERE hospitality) THEN
            RAISE NOTICE 'A hospitality bot already exists; skipping the seed';
            RETURN;
        END IF;

        hospitality_user_id := allocate_bot_user_id();

        INSERT INTO users(id, mmr, status, is_novice)
        VALUES (hospitality_user_id, 600, 'Online', FALSE);

        INSERT INTO decks(name, user_id)
        VALUES ('Warm Welcome', hospitality_user_id)
        RETURNING id INTO hospitality_deck_id;

        UPDATE users
        SET selected_deck_id = hospitality_deck_id
        WHERE id = hospitality_user_id;

        INSERT INTO deck_cards(deck_id, card_id, count)
        SELECT hospitality_deck_id, card.id, 3
        FROM cards card
        WHERE card.name IN ('Spawn', 'Fire', 'Water', 'Nature', 'Rock');

        GET DIAGNOSTICS seeded_card_count = ROW_COUNT;
        IF seeded_card_count <> 5 THEN
            RAISE EXCEPTION 'Hospitality deck expected 5 card entries but got %', seeded_card_count;
        END IF;

        INSERT INTO bot_personas(user_id, name, tier, thinking_time_ms, reaction_interval_frames,
                                 counter_aggression, enabled, hospitality)
        VALUES (hospitality_user_id, 'Warm Welcome', 'HOSPITALITY', 1200, 30, -1.0, TRUE, TRUE);

        RAISE NOTICE 'Seeded hospitality bot as user %', hospitality_user_id;
    END
$$;

DO
$$
    DECLARE
        hospitality_count   INTEGER;
        offensive_card_count INTEGER;
    BEGIN
        SELECT COUNT(*) INTO hospitality_count FROM bot_personas WHERE hospitality;
        IF hospitality_count <> 1 THEN
            RAISE EXCEPTION 'Expected exactly one hospitality bot persona, found %', hospitality_count;
        END IF;

        -- The whole "summons only" guarantee rests on the deck holding no other Magic card.
        SELECT COUNT(*)
        INTO offensive_card_count
        FROM bot_personas persona
                 JOIN decks deck ON deck.user_id = persona.user_id
                 JOIN deck_cards deck_card ON deck_card.deck_id = deck.id
                 JOIN cards card ON card.id = deck_card.card_id
        WHERE persona.hospitality
          AND card.card_type = 'Magic'
          AND card.name <> 'Spawn';

        IF offensive_card_count > 0 THEN
            RAISE EXCEPTION 'Hospitality deck holds % non-Spawn magic cards; it could cast attacks', offensive_card_count;
        END IF;
    END
$$;
