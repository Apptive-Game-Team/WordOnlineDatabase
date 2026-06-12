# Split seed order

This directory is a split version of `src/main/resources/sql/data.sql`.

Execution order:

1. `01_cards.sql`
2. `02_game_objects.sql`
3. `03_parameters.sql`
4. `04_parameter_values.sql`
5. `05_magics.sql`
6. `06_user_cards.sql`
7. `07_pve_scenarios.sql`
8. `../magic_sync/00_magic_catalog.sql`
9. `../magic_sync/01_magic_game_objects.sql`
10. `../magic_sync/02_magic_id_parameter.sql`

The app still points at `sql/data.sql`, so these files are for the split seed set until the loader is switched.
