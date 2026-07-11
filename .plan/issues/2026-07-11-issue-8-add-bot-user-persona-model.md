# 2026-07-11 — 봇 사용자와 페르소나 영속 모델 추가

- Date: 2026-07-11
- GitHub Issue: #8
- Status: Draft

## Goal

음수 `users.id`를 봇의 단일 identity로 사용하고, 해당 user와 1:1로 연결된 `bot_personas` 및 user 소유 deck을 production Flyway schema에 추가한다. 운영용 봇 bootstrap SQL은 반복 실행과 동시 생성에도 기존 데이터 훼손이나 ID 충돌이 없어야 한다.

## Non-goals

- Game server의 persona 조회 로직 구현
- Lobby의 봇 이름 조회 구현
- Admin UI/API 구현
- Account server에 봇 로그인 계정 생성

## Context / Constraints

- `users.id < 0`은 봇, `users.id > 0`은 실제 사용자다.
- 이름과 행동 설정은 `bot_personas`; MMR과 선택 deck은 `users`가 소유한다.
- `decks.user_id`는 bot user ID, `users.selected_deck_id`는 그 user 소유 deck만 가리켜야 한다.
- 기존 `scripts/manual/make_bot.sql`은 `-1`, 실제 user `313`, deck `334`에 의존하고 카드 소유권을 이동하므로 일반화가 필요하다.
- Flyway migration은 버전당 한 번 실행되지만 SQL 자체의 조건부 DDL/backfill도 재실행 안전하게 설계한다.
- Game, lobby, admin 배포 전 schema가 먼저 배포되어야 한다.

## Approach (Checklist)

- [ ] **Step 0: Recon** (`V000`의 FK/delete 규칙, 운영 DB의 기존 음수 user/persona 존재 여부, Flyway 버전/배포 순서 확인)
- [ ] **Step 1: Contract** (`bot_personas.user_id` PK 또는 UNIQUE FK, `name`, 행동 설정, `enabled`, timestamp, CHECK/index 및 삭제 정책 확정)
- [ ] **Step 2: Migration** (새 versioned migration에 idempotent enum/table/constraint/index 생성과 가능한 기존 데이터 backfill 추가)
- [ ] **Step 3: Bot allocation** (동시 admin 요청에도 중복되지 않는 음수 user ID 할당용 DB sequence/function 또는 잠금 기반 전략 구현)
- [ ] **Step 4: Operational SQL** (`make_bot.sql`을 upsert/parameter 기반 bootstrap으로 교체하거나 제거하고 실제 user 카드/deck을 이동하지 않게 수정)
- [ ] **Step 5: Tests** (빈 DB, 기존 schema, 반복 실행, 동시 ID 할당, FK/CHECK/삭제 동작 검증)
- [ ] **Step 6: Rollout / Rollback** (database → game/lobby/admin 순서, expand-first 호환 기간, destructive rollback 금지 원칙 문서화)

## Validation

- **Commands to run:** Flyway `info`, `validate`, 빈 PostgreSQL 대상 `migrate`; migration SQL을 transaction에서 두 번 실행하는 idempotency check; FK/CHECK 및 음수 ID allocator 동시 호출 SQL test
- **Expected output:** migration 1회 적용 성공, 조건부 SQL 재실행 성공, bot마다 고유 음수 user ID와 1개 persona 생성, selected deck 소유자 불일치 거부

## Risks & Rollback

- **Risks:** 현재 game test schema의 `bot_personas.id/deck_id/mmr` 계약과 새 schema 불일치; 기존 운영 persona 유무 불명; `MIN(id)-1` 방식의 동시성 충돌; user/deck 순환 FK로 삭제 순서 복잡; 구버전 서버와 동시 배포 시 컬럼 호환 문제
- **Rollback steps:** additive schema는 유지하고 애플리케이션을 이전 버전으로 되돌린다. 생성된 bot row 삭제는 별도 검증된 운영 절차로 수행하며 migration undo에서 사용자/deck 데이터를 자동 삭제하지 않는다.

## Open Questions

- 기존 production DB에 별도 수동 `bot_personas` 테이블 또는 음수 user가 이미 존재하는가?
- `bot_personas.user_id`를 primary key로 쓸지 별도 surrogate `id`와 UNIQUE `user_id`를 둘지 결정 필요. 단일 identity 원칙상 `user_id` PK 권장.
- bot 삭제 시 deck/card까지 cascade할지 admin service가 명시적 순서로 삭제할지 결정 필요. 감사와 안전성 때문에 명시적 transaction 권장.
