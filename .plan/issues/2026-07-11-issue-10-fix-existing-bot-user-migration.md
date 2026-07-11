# 2026-07-11 — V028 기존 봇 사용자 충돌 수정

- Date: 2026-07-11
- GitHub Issue: #10
- Status: Draft

## Goal

Legacy persona ID에 대응하는 음수 bot user가 이미 존재해도 V028 migration이 기존 user와 deck을 안전하게 재사용하도록 한다.

## Non-goals

- Bot schema 또는 application contract 변경
- 실제 사용자 deck 소유권 변경

## Context / Constraints

- PR #9 merge 후 PostgreSQL 14 migration에서 persona `1`과 user `-1` 충돌이 확인됐다.
- Migration transaction은 rollback되어 V028은 아직 적용되지 않았다.
- 기존 음수 user 데이터는 덮어쓰지 않는다.

## Approach (Checklist)

- [x] **Step 0: Recon** (CI 오류와 legacy migration 분기 확인)
- [x] **Step 1: Implementation** (기존 user 재사용, deck 소유자별 재사용/복제)
- [ ] **Step 2: Tests** (Flyway PostgreSQL 14 workflow 확인)
- [x] **Step 3: Rollout / Rollback** (V028 transaction rollback 유지)

## Validation

- **Commands to run:** Database migration GitHub Actions workflow
- **Expected output:** 기존 persona `1`과 user `-1`이 함께 있어도 V028 적용 성공

## Risks & Rollback

- **Risks:** Legacy persona가 존재하지 않는 deck을 가리키면 migration은 계속 명시적으로 실패한다.
- **Rollback steps:** Flyway transaction rollback. 추가 데이터 변경 없음.

## Open Questions

- 없음
