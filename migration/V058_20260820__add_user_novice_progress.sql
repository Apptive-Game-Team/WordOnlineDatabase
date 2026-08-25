-- How far along a player is with the tutorial opponent, from 0.5 to 1.0.
--
-- A boolean would end the tutorial in one step: beat the hospitality bot once and the next
-- practice match is a bot playing to win. This is the same number read two ways. It says how
-- new the player is, and it is the share of the player's board that the hospitality bot is
-- allowed to match. At 0.5 the bot commits half of what the player has standing and loses
-- clearly; at 1.0 it holds nothing back, which is the same thing as no longer being a novice,
-- so graduation needs no separate rule.
--
-- The default is the starting value so that a newly created account begins as a novice without
-- the account creation path having to know this column exists. Every row that exists right now
-- is set to 1.0: those players have already played, and leaving them at the default would put
-- the entire existing player base back in the tutorial.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS novice_progress REAL NOT NULL DEFAULT 0.5;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS chk_users_novice_progress;

ALTER TABLE users
    ADD CONSTRAINT chk_users_novice_progress
        CHECK (novice_progress BETWEEN 0.5 AND 1.0);

UPDATE users
SET novice_progress = 1.0
WHERE novice_progress < 1.0;

CREATE INDEX IF NOT EXISTS idx_users_novice_progress
    ON users (novice_progress)
    WHERE novice_progress < 1.0;

DO
$$
    DECLARE
        remaining_novice_count INTEGER;
    BEGIN
        SELECT COUNT(*) INTO remaining_novice_count FROM users WHERE novice_progress < 1.0;
        IF remaining_novice_count > 0 THEN
            RAISE EXCEPTION 'novice_progress backfill left % existing users mid-tutorial; they would all be routed to the hospitality bot',
                remaining_novice_count;
        END IF;
    END
$$;
