# Agent Instructions

This repository holds the Flyway migrations for the shared game database. Read
[`README.md`](README.md) for ownership boundaries, the migration rules, and what CI validates.

- **Workflow Doc**: [`.agents/docs/workflow.md`](.agents/docs/workflow.md) — issue first, branch
  naming, stacked pull requests, and the assignee and label rules for issues and pull requests.

## Project Skills

This repository keeps its own skills under `.agents/skills/`. Read the one that covers the task
before starting. An agent that only auto-loads skills from its own home directory does not see
these, so open the file by path.

- `.agents/skills/register-game-object/SKILL.md` — write a Flyway migration that registers a new
  game object or magic in the shared game database, including the counter tags the bot needs; use
  when adding a unit, building, projectile, or magic to `migration/`, or when a client-side skill
  hands off the server portion of a new magic.

Follow [`.agents/skills/register-game-object/SKILL.md`](.agents/skills/register-game-object/SKILL.md)
when a migration registers a game object or a magic. It covers the counter tags those
registrations must carry; a missing tag produces no error at runtime and silently removes
the object from every bot's counter reasoning, so the pull request is the only place it can
be caught.

Run the static migration checks before opening a pull request:

```bash
scripts/ci/validate-migrations.sh
```
