# 2026-07-11 — 교차 DB 동기화 후 봇 ID 충돌 방지

- Date: 2026-07-11
- GitHub Issue: #12
- Status: Draft

## Goal

Deploy/Dev sync가 명시적으로 삽입한 음수 user ID를 allocator가 건너뛰어 이후 Bot 생성 충돌을 방지한다.

## Non-goals

- V028 수정
- 기존 Bot ID 재할당
- Bot schema 변경

## Context / Constraints

- V028은 이미 merge되어 checksum을 변경하면 안 된다.
- DB별 sequence는 다른 DB에서 동기화로 들어온 명시적 ID를 자동 인식하지 못한다.

## Approach (Checklist)

- [x] **Step 0: Recon** (명시적 insert와 sequence 독립성 확인)
- [x] **Step 1: Implementation** (V029에서 allocator를 PL/pgSQL loop로 교체)
- [ ] **Step 2: Tests** (기존 연속 음수 ID skip migration 검증)
- [x] **Step 3: Rollout / Rollback** (함수만 forward replace)

## Validation

- **Commands to run:** Flyway PostgreSQL migration workflow
- **Expected output:** 이미 존재하는 candidate를 건너뛰고 미사용 음수 ID 반환

## Risks & Rollback

- **Risks:** 음수 ID 공간이 극단적으로 조밀하면 loop 횟수가 늘지만 실제 Bot 수 범위에서는 무시 가능하다.
- **Rollback steps:** 후속 migration에서 이전 SQL 함수로 교체 가능

## Open Questions

- 없음
