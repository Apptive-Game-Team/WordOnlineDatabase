-- Schema for the hospitality bot, separated from its seed because PostgreSQL refuses to
-- use a new enum value in the same transaction that added it, and Flyway wraps each
-- migration in one transaction. The seed lands in the next migration.

ALTER TYPE bot_tier ADD VALUE IF NOT EXISTS 'HOSPITALITY';

-- Marks a persona that only the hospitality path may select. enabled is deliberately not
-- reused for this: the bot is enabled -- it plays real sessions -- and showing it as
-- disabled in the admin view would invite someone to "fix" it back into the random pool.
ALTER TABLE bot_personas
    ADD COLUMN IF NOT EXISTS hospitality BOOLEAN NOT NULL DEFAULT FALSE;

-- counter_aggression scales the bot's counter score. At 0.0..1.0 it could only ever say
-- "prefer the play that beats what is on the field". A negative value inverts the term, so
-- the bot prefers the play the enemy board answers best -- which is what a bot that is
-- meant to lose convincingly needs. It picks a real unit and puts it in a losing matchup,
-- rather than standing still or casting nothing, which reads as being humoured.
ALTER TABLE bot_personas
    DROP CONSTRAINT IF EXISTS bot_personas_counter_aggression_check;

ALTER TABLE bot_personas
    ADD CONSTRAINT bot_personas_counter_aggression_check
        CHECK (counter_aggression BETWEEN -1.0 AND 1.0);

CREATE INDEX IF NOT EXISTS idx_bot_personas_hospitality
    ON bot_personas (hospitality, enabled)
    WHERE hospitality;

DO
$$
    BEGIN
        IF NOT EXISTS (SELECT 1
                       FROM information_schema.columns
                       WHERE table_name = 'bot_personas'
                         AND column_name = 'hospitality') THEN
            RAISE EXCEPTION 'bot_personas.hospitality was not created';
        END IF;
    END
$$;
