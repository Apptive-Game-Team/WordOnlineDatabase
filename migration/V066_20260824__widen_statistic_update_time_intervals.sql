-- min_interval_ns and max_interval_ns hold nanoseconds, but V000 declared them INTEGER.
-- INTEGER tops out at 2,147,483,647 ns, so any interval past ~2.147 seconds fails the
-- INSERT with "integer out of range". The game server writes these rows inside the same
-- transaction as the game, card and magic statistics, so one over-long frame interval
-- rolls back that game's entire statistics -- the balance data included. The value that
-- triggers it is exactly the stalled frame someone was trying to measure.
--
-- INTEGER -> BIGINT is a widening conversion: every existing value is representable and
-- no row is rewritten in a way that can lose data. The game server already passes these
-- as Java long (WordOnlineServer#384), so this migration alone closes the overflow.
-- Deploy it before the next game server release, per migration rule 4.

ALTER TABLE public.statistic_update_time
    ALTER COLUMN min_interval_ns TYPE BIGINT,
    ALTER COLUMN max_interval_ns TYPE BIGINT;

DO
$$
    BEGIN
        IF EXISTS (SELECT 1
                   FROM information_schema.columns
                   WHERE table_schema = 'public'
                     AND table_name = 'statistic_update_time'
                     AND column_name IN ('min_interval_ns', 'max_interval_ns')
                     AND data_type <> 'bigint') THEN
            RAISE EXCEPTION 'statistic_update_time interval columns are not bigint';
        END IF;
    END
$$;
