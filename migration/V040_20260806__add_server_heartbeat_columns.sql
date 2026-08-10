-- Issue #31: replace lobby's HTTP polling health check with a DB heartbeat.
--
-- The game server already writes to public.servers through JPA (ServerStatusService),
-- so a DB-backed heartbeat needs no new outbound HTTP client or service token on the
-- game side. The lobby reads these columns instead of polling each game server.
--
-- Ownership of the new columns:
--   last_heartbeat_at  written by game,  read by lobby
--   session_count      written by game,  read by lobby
--   max_sessions       written by game (from its own configured capacity), read by lobby
--
-- Idempotent: re-running the migration on a database that already has the columns
-- or the index is a no-op.

ALTER TABLE public.servers
    ADD COLUMN IF NOT EXISTS last_heartbeat_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS session_count     INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS max_sessions      INTEGER NOT NULL DEFAULT 100;

-- Existing rows intentionally keep last_heartbeat_at = NULL. NULL means "no heartbeat
-- reported yet"; the game server fills it in on startup and on every heartbeat tick.
-- Do not backfill an arbitrary timestamp: a fabricated value would make the lobby treat
-- a server that has never reported as freshly alive.
COMMENT ON COLUMN public.servers.last_heartbeat_at IS
    'Last heartbeat reported by the game server (UTC). Written by game; read by lobby to judge liveness. NULL means no heartbeat has ever been reported.';

COMMENT ON COLUMN public.servers.session_count IS
    'Game sessions currently hosted by this server. Written by game on each heartbeat; read by lobby for load balancing.';

COMMENT ON COLUMN public.servers.max_sessions IS
    'Maximum concurrent game sessions this server accepts. Written by game from its configured capacity; read by lobby to judge remaining headroom.';

-- public.servers had no index other than the primary key. The lobby's discovery query
-- (ServerRepository.findAllByTypeAndState) filters on exactly this column pair, and the
-- DB heartbeat makes that query run far more often than the previous hourly reload.
CREATE INDEX IF NOT EXISTS idx_servers_type_state
    ON public.servers (type, state);
