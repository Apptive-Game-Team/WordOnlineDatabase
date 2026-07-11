# Word Online Database

This repository is the source of truth for the shared game PostgreSQL database
used by the game, lobby, and admin servers.

## Ownership

- Add production schema and data changes as versioned Flyway files in
  `migration/`.
- Keep manual, operator-triggered queries in `scripts/manual/`. Flyway does not
  execute these files.
- Keep historical repository-local SQL in `archive/` for traceability only.
- Keep AccountServer database SQL in the AccountServer repository. It uses a
  separate database.
- Keep H2 and other test-only fixtures in the owning application repository.

## Migration Rules

1. Never edit an applied migration.
2. Add a new file named `V<next>_<YYYYMMDD>__<description>.sql`.
3. Make data migrations safe for databases where the intended rows may already
   exist.
4. Deploy database migrations before application code that requires them.
5. Use a forward-fix migration for rollback after a migration has been applied.

## Layout

- `migration/`: Flyway-managed shared game database changes
- `scripts/manual/`: reviewed SQL that operators run explicitly
- `archive/`: old SQL moved from application repositories; never executed

## Bot Identity Contract

- `users.id < 0` identifies bots; positive IDs remain reserved for real users.
- `bot_personas.user_id` is both the persona primary key and a foreign key to
  `users.id`.
- `bot_personas` owns display name and AI behavior settings.
- `users` owns MMR, status, and `selected_deck_id`.
- Bot decks use the same ownership model as real-user decks:
  `decks.user_id = bot_personas.user_id`.
- Applications allocate new bot IDs with `allocate_bot_user_id()` inside the
  same transaction that creates the user, deck, and persona.

Deploy `V028_20260711__add_bot_user_personas.sql` before application versions
that use this contract.
