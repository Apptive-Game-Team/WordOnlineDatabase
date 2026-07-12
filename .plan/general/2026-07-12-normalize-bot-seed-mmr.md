# 2026-07-12 — Normalize Bot Seed MMR

- Date: 2026-07-12
- GitHub Issue: #16
- Owning repository: database
- Status: Complete

## Goal

Initialize every newly seeded bot user with MMR 1000 and normalize existing bot users to the same value.

## Acceptance Criteria

- Every concept-bot tier seeds `users.mmr` as 1000.
- Every existing user referenced by `bot_personas` is updated to MMR 1000.
- Existing manual and archived bot creation SQL remains at 1000.
- Legacy persona migration continues preserving existing MMR.

## Non-goals

- Changing bot tier behavior parameters.
- Rewriting MMR of non-bot users.
- Changing legacy migration semantics.

## Context / Constraints

- Production SQL is owned by the database module.
- Applied Flyway migrations must not be edited after deployment; V030 is currently the requested seed source and this change assumes it has not been promoted.

## Affected Repositories and Contracts

- `database`: concept-bot seed data and existing bot-user MMR normalization.
- No service or API contract changes.

## Approach

- [x] Recon
- [x] Implementation
- [x] Focused validation
- [x] Compatibility and regression validation
- [x] Release order and rollback check

## Validation

- Commands: `rg -n -i --glob '*.sql' '(bot|mmr)' migration scripts archive/lobby`
- Manual checks: inspect every bot-user `INSERT INTO users` source.
- Expected results: all newly created and existing bot users receive MMR 1000; non-bot users remain unchanged.

## Risks & Rollback

- Risk: editing an already-applied Flyway migration causes checksum mismatch.
- Rollback: revert this seed-only change before deployment; if V030 is already applied anywhere, use a follow-up migration instead.

## Release Order

- Publish database module only.

## Open Questions

- Whether V030 has already run in a shared environment; current task assumes no.
