# 2026-07-12 — Normalize Bot Seed MMR

- Date: 2026-07-12
- GitHub Issue: #16
- Owning repository: database
- Status: Complete

## Goal

Normalize every bot user to MMR 1000 after the existing V030 seed runs.

## Acceptance Criteria

- Every concept bot created by V030 is updated to `users.mmr = 1000` by V031.
- Every existing user referenced by `bot_personas` is updated to MMR 1000.
- Existing manual and archived bot creation SQL remains at 1000.
- Legacy persona migration continues preserving existing MMR.

## Non-goals

- Changing bot tier behavior parameters.
- Rewriting MMR of non-bot users.
- Changing legacy migration semantics.

## Context / Constraints

- Production SQL is owned by the database module.
- V030 is already merged and must remain byte-for-byte unchanged to preserve its Flyway checksum.
- V031 normalizes every user referenced by `bot_personas`, including bots created by V030.

## Affected Repositories and Contracts

- `database`: follow-up bot-user MMR data migration only.
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
- Expected results: all users referenced by `bot_personas` have MMR 1000 after V031; non-bot users remain unchanged.

## Risks & Rollback

- Risk: resetting bot MMR changes current bot matchmaking placement.
- Rollback: MMR values before V031 are not recoverable from schema state; restore from backup or apply an explicit compensating migration.

## Release Order

- Publish database module only.

## Open Questions

- None.
