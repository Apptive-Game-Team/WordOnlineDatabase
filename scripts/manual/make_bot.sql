DO $$
    DECLARE
        new_bot_id int := -1;
        last_user_id int := 313;
        selected_deck_id int := 334;
    BEGIN

        INSERT INTO users(id, selected_deck_id, mmr, status)
        VALUES (new_bot_id, selected_deck_id, 1000, 'Online');

        UPDATE decks
        SET user_id = new_bot_id
        WHERE id = selected_deck_id;

        UPDATE user_cards
        SET user_id = new_bot_id
        WHERE user_id = last_user_id;

    END $$;