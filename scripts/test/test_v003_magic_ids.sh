#!/bin/bash
# V003 renumbers magic ids to the canonical catalog. It has to serve two kinds of
# database: one that already follows the catalog and still needs the renumber,
# and one that assigned its own ids and must be left completely alone -- there,
# renumbering would delete real user_magics and statistic_game_magics rows.
#
# Needs docker. Run from anywhere: scripts/test/test_v003_magic_ids.sh
set -u

MIGRATION="$(cd "$(dirname "$0")/../../migration" && pwd)/V003_20260612__sync_magic_references.sql"
PORT=55432
CONTAINER=v003-magic-id-test
export PGPASSWORD=test
PSQL="psql -h localhost -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
fail=0

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1; }
trap cleanup EXIT

docker rm -f "$CONTAINER" >/dev/null 2>&1
docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=test -p $PORT:5432 postgres:16 >/dev/null
for _ in $(seq 1 30); do docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done

check() {
  if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: expected [$2] got [$3]"; fail=1; fi
}

q() { $PSQL -d "$1" -tAc "$2"; }

setup() { # dbname, then seed SQL on stdin
  $PSQL -d postgres -c "DROP DATABASE IF EXISTS $1" >/dev/null 2>&1
  $PSQL -d postgres -c "CREATE DATABASE $1" >/dev/null
  $PSQL -d "$1" >/dev/null <<'SCHEMA'
CREATE TABLE magics (id BIGSERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL);
CREATE TABLE magic_cards (magic_id BIGINT, card_id BIGINT);
CREATE TABLE user_magics (user_id BIGINT, magic_id BIGINT);
CREATE TABLE statistic_game_magics (user_id BIGINT, statistic_game_id BIGINT, magic_id BIGINT);
SCHEMA
  $PSQL -d "$1" >/dev/null
  # Flyway runs a migration as one transaction; psql autocommits per statement,
  # which would drop the ON COMMIT DROP temp tables too early.
  $PSQL --single-transaction -d "$1" -f "$MIGRATION" >/dev/null
  echo "  migration exit=$?"
}

echo "case canonical: catalog ids are respected, one magic sits on a free wrong id"
setup canonical <<'SEED'
INSERT INTO magics(id, name) VALUES (5,'wind_spirit'), (500,'water_shot'), (9,'chain_lightning');
INSERT INTO user_magics(user_id, magic_id) VALUES (1,500), (1,9), (2,500);
INSERT INTO magic_cards(magic_id, card_id) VALUES (500, 77);
SELECT setval('magics_id_seq', 1000, true);
SEED
check "water_shot moved to canonical id 6" "6"  "$(q canonical "SELECT id FROM magics WHERE name='water_shot'")"
check "user_magics followed the move"      "2"  "$(q canonical "SELECT count(*) FROM user_magics WHERE magic_id=6")"
check "magic_cards followed the move"      "1"  "$(q canonical "SELECT count(*) FROM magic_cards WHERE magic_id=6")"
check "nothing left behind on the old id"  "0"  "$(q canonical "SELECT count(*) FROM user_magics WHERE magic_id=500")"
check "missing catalog rows were seeded"   "67" "$(q canonical "SELECT count(*) FROM magics")"

echo "case hand_numbered: a canonical id is held by a different magic"
setup hand_numbered <<'SEED'
-- canonical id 5 is wind_spirit, but this database put water_shot there
INSERT INTO magics(id, name) VALUES (5,'water_shot'), (6,'wind_spirit'), (90,'chain_lightning');
INSERT INTO user_magics(user_id, magic_id) VALUES (1,5), (1,6), (2,90);
INSERT INTO magic_cards(magic_id, card_id) VALUES (5, 77);
INSERT INTO statistic_game_magics(user_id, statistic_game_id, magic_id) VALUES (1, 1, 5);
SELECT setval('magics_id_seq', 1000, true);
SEED
check "water_shot kept its id"        "5"  "$(q hand_numbered "SELECT id FROM magics WHERE name='water_shot'")"
check "wind_spirit kept its id"       "6"  "$(q hand_numbered "SELECT id FROM magics WHERE name='wind_spirit'")"
check "chain_lightning kept its id"   "90" "$(q hand_numbered "SELECT id FROM magics WHERE name='chain_lightning'")"
check "no user_magics row deleted"    "3"  "$(q hand_numbered "SELECT count(*) FROM user_magics")"
check "no magic_cards row deleted"    "1"  "$(q hand_numbered "SELECT count(*) FROM magic_cards")"
check "no statistic row deleted"      "1"  "$(q hand_numbered "SELECT count(*) FROM statistic_game_magics")"
check "no catalog row seeded"         "3"  "$(q hand_numbered "SELECT count(*) FROM magics")"

[ $fail -eq 0 ] && echo "ALL OK" || echo "FAILURES"
exit $fail
