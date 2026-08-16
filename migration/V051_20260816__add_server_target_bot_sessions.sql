-- Let admins set, per game server, how many bot self-play sessions the server keeps running.
--
-- The game server's BotGameScheduler previously read the target only from its static
-- configuration (bot.auto-match.target-games), so changing it required a redeploy and the
-- same value applied to every instance of a deployment. This column stores a per-server
-- override that the scheduler reads on every check tick.
--
-- Ownership of the new column:
--   target_bot_sessions  written by admin,  read by game
--
-- The game server maps this column read-only (insertable = false, updatable = false), so its
-- whole-row heartbeat save never overwrites a value the admin just wrote.
--
-- Idempotent: re-running the migration on a database that already has the column is a no-op.

ALTER TABLE public.servers
    ADD COLUMN IF NOT EXISTS target_bot_sessions INTEGER;

-- Existing rows intentionally keep target_bot_sessions = NULL. NULL means "no admin override";
-- the game server then falls back to its configured bot.auto-match.target-games default.
-- Do not backfill the configured default: it can differ per deployment, and a copied value
-- would freeze a config change made later on the game side.
COMMENT ON COLUMN public.servers.target_bot_sessions IS
    'Admin override for the number of sessions the game server''s bot scheduler tops the server up to. Written by admin; read by game on every scheduler tick. NULL means no override; the game server falls back to its configured bot.auto-match.target-games default.';
