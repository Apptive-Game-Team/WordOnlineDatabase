-- Matchmaking queue and match state as a single row per user.
-- Replaces the Redis matching queue and the Redis session recovery store.

CREATE TABLE IF NOT EXISTS match_tickets
(
    user_id       BIGINT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    mmr           BIGINT      NOT NULL DEFAULT 0,
    state         TEXT        NOT NULL CHECK (state IN ('QUEUED', 'MATCHED', 'PLAYING')),
    enqueued_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    session_id    TEXT,
    server_url    TEXT,
    left_user_id  BIGINT,
    right_user_id BIGINT,
    retry_count   INT         NOT NULL DEFAULT 0
);

-- Pairing scans only the queued rows, ordered by mmr.
CREATE INDEX IF NOT EXISTS idx_match_tickets_queued
    ON match_tickets (mmr) WHERE state = 'QUEUED';

-- Expiry, stuck-MATCHED recovery and the session reconciler scan by state and age.
CREATE INDEX IF NOT EXISTS idx_match_tickets_state_updated
    ON match_tickets (state, updated_at);

-- Session id source. Replaces the Redis INCR counter.
CREATE SEQUENCE IF NOT EXISTS match_session_seq;
