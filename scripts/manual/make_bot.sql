DO $$
DECLARE
    bot_name CONSTANT VARCHAR(50) := 'Default Bot';
    bot_user_id BIGINT;
    bot_deck_id BIGINT;
BEGIN
    SELECT user_id INTO bot_user_id
    FROM bot_personas
    WHERE name = bot_name
    ORDER BY user_id
    LIMIT 1;

    IF bot_user_id IS NOT NULL THEN
        RAISE NOTICE 'Bot % already exists with user id %', bot_name, bot_user_id;
        RETURN;
    END IF;

    bot_user_id := allocate_bot_user_id();

    INSERT INTO users(id, mmr, status)
    VALUES (bot_user_id, 1000, 'Online');

    INSERT INTO decks(name, user_id)
    VALUES ('Default Bot Deck', bot_user_id)
    RETURNING id INTO bot_deck_id;

    UPDATE users
    SET selected_deck_id = bot_deck_id
    WHERE id = bot_user_id;

    INSERT INTO bot_personas(
        user_id, name, tier, thinking_time_ms, reaction_interval_frames,
        counter_aggression, enabled
    )
    VALUES (
        bot_user_id, bot_name, 'BEGINNER', 250, 8, 0.25, TRUE
    );
END
$$;
