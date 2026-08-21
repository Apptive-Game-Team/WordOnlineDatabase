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

## Validation

Rules 1 and 2 are enforced on every pull request that touches `migration/`, by the
`validate migrations` workflow. Before this existed, a version clash or an edited
migration only surfaced after the merge to `main`, when the `migrate dev` workflow had
already run against the dev database.

Run the static checks locally before opening a pull request:

```bash
scripts/ci/validate-migrations.sh
```

It reports, without needing a database:

- filenames that Flyway would not parse as migrations, and so would silently never run
- two files claiming the same version, which makes Flyway refuse to run anything
- a new migration numbered at or below the highest on `main`, which applies out of order
  and leaves environments diverged
- a published migration that was modified or deleted (rule 1)

The workflow additionally runs `flyway validate` against the dev database, which compares
checksums against what that database actually applied. Pending migrations are expected on
a pull request and are not treated as a failure.

Neither check applies migrations to a scratch database. `V000` opens with
`create database` and carries a `pg_catalog` dump, so the chain cannot be replayed from
empty; see issue #23.

## Counter Tags

`tags`, `game_object_tags`, and `magic_tags` describe what each object and magic is, and
`tag_counter_rules` states which of those properties beats which. Only the game server's
`BotCounterEvaluator` reads them: they are the bot's counter heuristics, not a gameplay
rule, and no simulation result depends on them.

A missing tag has no runtime symptom. The lookup returns nothing, the evaluator returns the
neutral score `0.0`, and the object is left out of every bot's counter reasoning without an
error anywhere. Coverage therefore has to be enforced when the migration is written.

- Every migration that inserts into `game_objects` must also insert into `game_object_tags`.
- Every migration that inserts into `magics` must populate `magic_tags`, normally by calling
  `sync_magic_tags_from_game_objects()` at the end of the file. The function derives a
  magic's tags from the game object sharing its name, so the two cannot disagree.
- A magic that is not named after the object it creates needs a `magic_game_object_aliases`
  row before that call reaches it. Swarm magics spawn the singular object, and a handful of
  magics predate their object's current name; the name join returns nothing for all of them
  and leaves the magic unscored without an error.
- A registration with genuinely nothing to tag declares why in a `-- no-tags: <reason>`
  comment at the top of the file.

`scripts/ci/validate-migrations.sh` enforces the first, second and fourth of these.

Three kinds of object carry no counter tag on purpose, so an audit that lists them is not
reporting a gap:

- The six rune prefabs and `wall`. They are cast markers and arena terrain, never something
  an opponent answers, and they have no `game_objects` row at all.
- `rock_remnant`. It has `TYPE_Unit` and no `CAT_*`: rubble with no hp and no attack is not
  worth a bot's area magic, and every `CAT_*` on a target is a reason to spend one on it.
- `dimension_toad`. `NonAttackingCowardMob` never attacks, so no attacker role fits;
  `CAT_Large` already exposes it to the crowd control rule.

The legacy `game_objects` rows that duplicate a live object -- `cannon`, `fire_explosion`,
the `_swarm` names and the rest -- stay untagged as well. They never instantiate; the magics
named after them reach the live object through `magic_game_object_aliases`.

Elements are deliberately not tagged. `ElementalChart` on the game server owns the element
multiplier table, real damage is computed from it, and the client's magic book mirrors it.
A copy here would be a second source of truth for one rule, and only the bot's copy would
be missed during a balance pass.

Follow [`.agents/skills/register-game-object/SKILL.md`](.agents/skills/register-game-object/SKILL.md)
when writing a registration migration.

## Layout

- `migration/`: Flyway-managed shared game database changes
- `scripts/ci/`: validation run by CI on pull requests
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

- `bot_personas.hospitality` marks the tutorial opponent. Exactly one persona
  carries it. It is `enabled` like any other bot, but the lobby must exclude it
  from the random practice pool and select it only for a player whose
  `users.is_novice` is still true.
- `bot_personas.counter_aggression` may be negative. A negative value inverts the
  bot's counter scoring, so it prefers the play the enemy board answers best.
  Only the hospitality bot uses this; a negative value on an ordinary bot makes
  it play against itself.

Deploy `V028_20260711__add_bot_user_personas.sql` before application versions
that use this contract.
