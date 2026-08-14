ALTER TABLE public.statistic_games
    ADD COLUMN server_version varchar(64),
    ADD COLUMN event_schema_version integer;

UPDATE public.statistic_games
SET server_version = 'unknown',
    event_schema_version = 1;

ALTER TABLE public.statistic_games
    ALTER COLUMN server_version SET NOT NULL,
    ALTER COLUMN event_schema_version SET NOT NULL,
    ADD CONSTRAINT chk_statistic_games_event_schema_version
        CHECK (event_schema_version > 0);
