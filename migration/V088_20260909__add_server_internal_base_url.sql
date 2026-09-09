-- Issue #132: let lobby and admin call game and account servers over the docker network
-- `net` instead of the public internet when both sides are on it.
--
-- lobby -> game and admin -> account both currently go through the public address stored
-- as protocol/domain/port (for example https://blue.game.ac.theevilent.com:443), even
-- though all 15 host containers sit on the same docker network and can reach each other
-- by name. This column lets the server that owns a `public.servers` row report an
-- internal address the reading side can prefer.
--
-- Ownership of the new column:
--   internal_base_url  written by the server that owns the row (game, account),
--                       read by lobby and admin
--
-- protocol, domain, and port stay untouched: they are the address a client connects to
-- and must keep meaning that. A single nullable base URL is enough for the reading side,
-- which only needs one WebClient base URL; splitting internal scheme/host/port into three
-- more nullable columns would allow six combinations that mean nothing.
--
-- Idempotent: re-running the migration on a database that already has the column is a
-- no-op.

ALTER TABLE public.servers
    ADD COLUMN IF NOT EXISTS internal_base_url VARCHAR(255);

-- Existing rows intentionally keep internal_base_url = NULL. NULL means "this server has
-- not reported an internal address yet"; lobby and admin must then fall back to the
-- public address (protocol://domain:port). Do not backfill a guessed value: a fabricated
-- internal address would send lobby and admin requests to a host they cannot reach.
COMMENT ON COLUMN public.servers.internal_base_url IS
    'Internal base URL (scheme, host, and port; no trailing /) reachable on the docker network `net`, e.g. http://ac-game-blue:8080. Written by the server that owns the row (game, account); read by lobby and admin. NULL means no internal address has been reported; the reader must then fall back to the public address protocol://domain:port.';
