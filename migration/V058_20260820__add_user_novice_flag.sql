-- The novice flag decides whether a practice match goes to the hospitality bot instead of
-- the ordinary bot pool. The lobby reads it when the player queues; the game server clears
-- it when that session ends.
--
-- The default is TRUE so that a newly created account is a novice without the account
-- creation path having to know this column exists. Every row that exists right now is
-- backfilled to FALSE: those players have already played, and leaving them at the default
-- would route the entire existing player base to the hospitality bot.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_novice BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE users
SET is_novice = FALSE
WHERE is_novice = TRUE;

-- Bots are never novices. They do not queue for practice, but the flag would be misleading
-- in admin views and in any future query that filters on it.
UPDATE users
SET is_novice = FALSE
WHERE id < 0
  AND is_novice = TRUE;

CREATE INDEX IF NOT EXISTS idx_users_is_novice
    ON users (is_novice)
    WHERE is_novice;

DO
$$
    DECLARE
        remaining_novice_count INTEGER;
    BEGIN
        SELECT COUNT(*) INTO remaining_novice_count FROM users WHERE is_novice;
        IF remaining_novice_count > 0 THEN
            RAISE EXCEPTION 'is_novice backfill left % existing users marked as novices; they would all be routed to the hospitality bot',
                remaining_novice_count;
        END IF;
    END
$$;
