-- Game session lifecycle tracking.
--
-- Until now the only durable trace of a match was the statistic_games row inserted
-- when its game loop terminated, so a session whose loop deadlocked or whose server
-- crashed left no record anywhere. The game server now inserts a lifecycle row at
-- session start and resolves it at session end, and a loop watchdog resolves stuck
-- sessions as ABANDONED. A row still IN_PROGRESS long after started_at therefore
-- means the hosting process died without cleaning up.

-- The game server's SessionType has had PVE since scenarios shipped, but the enum
-- was never extended, so every finished PVE match failed its statistics insert.
ALTER TYPE game_type ADD VALUE IF NOT EXISTS 'PVE';

-- statistic_games grows an outcome so draws and watchdog-abandoned matches can be
-- recorded with their card/magic/frame-timing data. Winner columns only make sense
-- for decisive games, so they become nullable with a guard.
ALTER TABLE public.statistic_games
    ALTER COLUMN win_user_id DROP NOT NULL,
    ALTER COLUMN loss_user_id DROP NOT NULL,
    ADD COLUMN outcome varchar(16) NOT NULL DEFAULT 'WIN',
    ADD CONSTRAINT statistic_games_outcome_check
        CHECK (outcome IN ('WIN', 'DRAW', 'ABANDONED')),
    ADD CONSTRAINT statistic_games_win_outcome_check
        CHECK (outcome <> 'WIN' OR (win_user_id IS NOT NULL AND loss_user_id IS NOT NULL));

CREATE TABLE IF NOT EXISTS public.statistic_game_sessions (
    id bigserial PRIMARY KEY,
    -- Not unique: a session id could in principle be re-registered after a server
    -- restart, and each attempt deserves its own lifecycle row.
    session_id varchar(128) NOT NULL,
    left_user_id bigint NOT NULL,
    right_user_id bigint NOT NULL,
    game_type game_type NOT NULL,
    -- domain + port identify the deployment across restarts; the instance id
    -- identifies the exact process, so a booting server can mark rows left
    -- IN_PROGRESS by its predecessor as ABANDONED (SERVER_RESTART).
    server_domain varchar(255) NOT NULL,
    server_port integer NOT NULL,
    server_instance_id varchar(64) NOT NULL,
    server_version varchar(64) NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'IN_PROGRESS'
        CONSTRAINT statistic_game_sessions_status_check
        CHECK (status IN ('IN_PROGRESS', 'COMPLETED', 'DRAW', 'ABANDONED')),
    end_reason varchar(32),
    -- Free-form diagnostic evidence for abnormal ends, e.g. the stack trace of a
    -- stalled loop thread captured by the watchdog at reap time.
    end_detail text,
    statistic_game_id bigint REFERENCES public.statistic_games (id) ON DELETE SET NULL,
    started_at timestamptz NOT NULL DEFAULT now(),
    ended_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_statistic_game_sessions_status_started_at
    ON public.statistic_game_sessions (status, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_statistic_game_sessions_started_at
    ON public.statistic_game_sessions (started_at DESC);
