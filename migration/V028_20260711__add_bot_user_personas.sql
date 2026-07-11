DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'bot_tier') THEN
        CREATE TYPE bot_tier AS ENUM ('INTRO', 'BEGINNER', 'INTERMEDIATE', 'ADVANCED', 'ELITE');
    END IF;
END
$$;

CREATE SEQUENCE IF NOT EXISTS bot_user_id_seq
    AS BIGINT
    INCREMENT BY -1
    MINVALUE -9223372036854775808
    MAXVALUE -1
    START WITH -1
    NO CYCLE;

CREATE OR REPLACE FUNCTION allocate_bot_user_id()
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    candidate BIGINT;
BEGIN
    LOOP
        candidate := nextval('bot_user_id_seq');
        EXIT WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = candidate);
    END LOOP;
    RETURN candidate;
END;
$$;

DO $$
DECLARE
    persona RECORD;
    bot_user_id BIGINT;
    copied_deck_id BIGINT;
    legacy_deck_owner_id BIGINT;
BEGIN
    IF to_regclass('public.bot_personas') IS NOT NULL
       AND EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'bot_personas'
              AND column_name = 'id'
       ) THEN
        ALTER TABLE bot_personas RENAME TO bot_personas_legacy_20260711;

        CREATE TABLE bot_personas (
            user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            name VARCHAR(50) NOT NULL,
            tier bot_tier NOT NULL DEFAULT 'BEGINNER',
            thinking_time_ms INTEGER NOT NULL DEFAULT 250 CHECK (thinking_time_ms >= 0),
            reaction_interval_frames INTEGER NOT NULL DEFAULT 8 CHECK (reaction_interval_frames >= 1),
            counter_aggression DOUBLE PRECISION NOT NULL DEFAULT 0.25
                CHECK (counter_aggression BETWEEN 0.0 AND 1.0),
            enabled BOOLEAN NOT NULL DEFAULT TRUE,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT chk_bot_personas_negative_user_id CHECK (user_id < 0)
        );

        FOR persona IN
            SELECT * FROM bot_personas_legacy_20260711 ORDER BY id
        LOOP
            bot_user_id := -ABS(persona.id);

            IF NOT EXISTS (SELECT 1 FROM users WHERE id = bot_user_id) THEN
                INSERT INTO users(id, mmr, status)
                VALUES (bot_user_id, persona.mmr, 'Online');
            END IF;

            IF persona.deck_id IS NOT NULL THEN
                copied_deck_id := NULL;
                legacy_deck_owner_id := NULL;

                SELECT user_id
                INTO legacy_deck_owner_id
                FROM decks
                WHERE id = persona.deck_id;

                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Cannot migrate bot persona %, deck % does not exist', persona.id, persona.deck_id;
                END IF;

                IF legacy_deck_owner_id = bot_user_id THEN
                    copied_deck_id := persona.deck_id;
                ELSE
                    INSERT INTO decks(name, user_id)
                    SELECT COALESCE(name, 'Bot Deck'), bot_user_id
                    FROM decks
                    WHERE id = persona.deck_id
                    RETURNING id INTO copied_deck_id;

                    INSERT INTO deck_cards(deck_id, card_id, count)
                    SELECT copied_deck_id, card_id, count
                    FROM deck_cards
                    WHERE deck_id = persona.deck_id;
                END IF;

                UPDATE users
                SET selected_deck_id = copied_deck_id
                WHERE id = bot_user_id;
            END IF;

            INSERT INTO bot_personas(
                user_id, name, tier, thinking_time_ms, reaction_interval_frames,
                counter_aggression, enabled, created_at, updated_at
            )
            VALUES (
                bot_user_id, persona.name, persona.tier::TEXT::bot_tier,
                persona.thinking_time_ms, persona.reaction_interval_frames,
                persona.counter_aggression, persona.enabled,
                COALESCE(persona.created_at, CURRENT_TIMESTAMP),
                COALESCE(persona.updated_at, CURRENT_TIMESTAMP)
            );
        END LOOP;
    ELSE
        CREATE TABLE IF NOT EXISTS bot_personas (
            user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            name VARCHAR(50) NOT NULL,
            tier bot_tier NOT NULL DEFAULT 'BEGINNER',
            thinking_time_ms INTEGER NOT NULL DEFAULT 250 CHECK (thinking_time_ms >= 0),
            reaction_interval_frames INTEGER NOT NULL DEFAULT 8 CHECK (reaction_interval_frames >= 1),
            counter_aggression DOUBLE PRECISION NOT NULL DEFAULT 0.25
                CHECK (counter_aggression BETWEEN 0.0 AND 1.0),
            enabled BOOLEAN NOT NULL DEFAULT TRUE,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT chk_bot_personas_negative_user_id CHECK (user_id < 0)
        );
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_bot_personas_enabled
    ON bot_personas(enabled, user_id);

SELECT setval(
    'bot_user_id_seq',
    LEAST(COALESCE((SELECT MIN(id) FROM users WHERE id < 0), 0) - 1, -1),
    FALSE
);
