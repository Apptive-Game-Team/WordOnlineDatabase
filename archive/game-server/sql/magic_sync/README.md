# Magic Sync Order

Run these in order for existing deploy DBs that already have magic rows:

1. `03_migrate_magic_references.sql`
2. `01_magic_game_objects.sql`
3. `02_magic_id_parameter.sql`

`03_migrate_magic_references.sql` rewrites `magic_cards`, `user_magics`, and `statistic_game_magics` to the canonical ids, then removes stale magic rows.
`00_magic_catalog.sql` is read-only reference data for checking the canonical id/name list.
