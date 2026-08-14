# Agent Instructions

This repository holds the Flyway migrations for the shared game database. Read
[`README.md`](README.md) for ownership boundaries, the migration rules, and what CI validates.

- **Workflow Doc**: [`.agents/docs/workflow.md`](.agents/docs/workflow.md) — issue first, branch
  naming, stacked pull requests, and the assignee and label rules for issues and pull requests.

Run the static migration checks before opening a pull request:

```bash
scripts/ci/validate-migrations.sh
```
