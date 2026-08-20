-- Rebalance the starter deck template.
--
-- decks.user_id = 0 holds the template that lobby copies into every new user
-- (UserRepository.initUserDeck). It carried 11 Type cards against 4 Magic
-- cards, but almost every recipe in magic_cards spends one Type card together
-- with one Magic card, so a starter hand ran out of Magic cards while Type
-- cards piled up. The new split is 8 Type and 7 Magic, with Spawn at the
-- three-copy cap because it appears in more recipes than any other card.
--
-- Wind leaves the template as well: cards.unlock_condition_type gates it
-- behind WIN_COUNT 5, so a starter deck should not open with it.
--
-- Existing users keep their own copies of the deck; only the template changes.

DO $$
DECLARE
    starter_deck_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO starter_deck_count FROM decks WHERE user_id = 0;

    IF starter_deck_count <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one starter deck template, found %', starter_deck_count;
    END IF;
END
$$;

-- Rewrite rather than patch, so the template lands on the same 15 cards
-- whatever a given environment holds now.
DELETE FROM deck_cards
WHERE deck_id IN (SELECT id FROM decks WHERE user_id = 0);

INSERT INTO deck_cards(deck_id, card_id, count)
SELECT starter_deck.id, card.id, target.count
FROM (
    VALUES
        ('Fire', 2),
        ('Water', 1),
        ('Lightning', 1),
        ('Rock', 2),
        ('Nature', 2),
        ('Spawn', 3),
        ('Shoot', 2),
        ('Build', 1),
        ('Explode', 1)
) AS target(card_name, count)
JOIN cards card ON card.name = target.card_name
CROSS JOIN (SELECT id FROM decks WHERE user_id = 0) AS starter_deck;

-- The lobby rejects a deck that breaks these rules (DeckValidator), and a
-- template that new users cannot edit their way out of would be worse than a
-- failed migration.
DO $$
DECLARE
    total_cards INTEGER;
    max_copies INTEGER;
    type_kinds INTEGER;
    magic_kinds INTEGER;
    gated_cards INTEGER;
BEGIN
    SELECT COALESCE(SUM(deck_cards.count), 0),
           COALESCE(MAX(deck_cards.count), 0),
           COUNT(*) FILTER (WHERE card.card_type = 'Type'),
           COUNT(*) FILTER (WHERE card.card_type = 'Magic'),
           COUNT(*) FILTER (WHERE card.unlock_condition_type IS NOT NULL)
    INTO total_cards, max_copies, type_kinds, magic_kinds, gated_cards
    FROM deck_cards
    JOIN decks ON decks.id = deck_cards.deck_id
    JOIN cards card ON card.id = deck_cards.card_id
    WHERE decks.user_id = 0;

    IF total_cards <> 15 THEN
        RAISE EXCEPTION 'Starter deck must hold 15 cards, holds %', total_cards;
    END IF;

    IF max_copies > 3 THEN
        RAISE EXCEPTION 'Starter deck holds % copies of one card, limit is 3', max_copies;
    END IF;

    IF type_kinds < 2 OR magic_kinds < 3 THEN
        RAISE EXCEPTION 'Starter deck needs 2+ Type kinds and 3+ Magic kinds, has % and %',
            type_kinds, magic_kinds;
    END IF;

    IF gated_cards > 0 THEN
        RAISE EXCEPTION 'Starter deck holds % unlock-gated card(s)', gated_cards;
    END IF;
END
$$;
