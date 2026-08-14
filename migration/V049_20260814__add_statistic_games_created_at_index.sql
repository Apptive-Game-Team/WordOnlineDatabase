-- Issue #45: give the admin frame timing page a usable access path for its time filter.
--
-- statistic_games is an append-only history table: one row per finished game, and it only
-- grows. WordOnlineAdmin #65 adds a page whose every query narrows on created_at first
-- (default 7 days, selectable up to a year) and then joins statistic_update_time. Opening
-- that page runs four such queries -- the per-name aggregate, the time series, the recent
-- games list and the total count -- so a sequential scan is paid four times per view and
-- gets steadily worse as history accumulates.
--
-- The index is on statistic_games only. statistic_update_time already has an index on
-- statistic_game_id, which is the column the joins use.
--
-- Idempotent: re-running on a database that already has the index is a no-op.

CREATE INDEX IF NOT EXISTS idx_statistic_games_created_at
    ON public.statistic_games (created_at);

COMMENT ON INDEX public.idx_statistic_games_created_at IS
    'Supports the admin statistics and frame timing pages, which filter statistic_games by created_at before joining the per-game statistic tables. Added for WordOnlineAdmin #65.';
