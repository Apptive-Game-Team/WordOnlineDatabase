# Agent Instructions

This repository holds the Flyway migrations for the shared game database. Read
[`README.md`](README.md) for ownership boundaries, the migration rules, and what CI validates.

- **Workflow Doc**: [`.agents/docs/workflow.md`](.agents/docs/workflow.md) — issue first, branch
  naming, stacked pull requests, and the assignee and label rules for issues and pull requests.

Follow [`.agents/skills/register-game-object/SKILL.md`](.agents/skills/register-game-object/SKILL.md)
when a migration registers a game object or a magic. It covers the counter tags those
registrations must carry; a missing tag produces no error at runtime and silently removes
the object from every bot's counter reasoning, so the pull request is the only place it can
be caught.

Run the static migration checks before opening a pull request:

```bash
scripts/ci/validate-migrations.sh
```
