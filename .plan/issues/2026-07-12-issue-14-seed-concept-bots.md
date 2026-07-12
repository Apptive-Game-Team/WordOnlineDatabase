# 2026-07-12 — 컨셉별 난이도 봇 45개 구성

- Date: 2026-07-12
- GitHub Issue: #14
- Status: Implemented

## Goal

기존 봇을 비활성화하고, 9개 컨셉마다 5단계 난이도의 서로 다른 영문 이름 봇과 유효한 15장 덱을 추가한다.

## Non-goals

- 기존 봇 user/deck/persona 삭제
- 경기 통계 삭제
- 카드/마법 정의 변경
- 게임 서버 AI 로직 변경

## Context / Constraints

- 봇 identity는 `users.id < 0`, persona는 `bot_personas.user_id` 1:1 관계다.
- 봇 덱은 해당 user가 소유하고 `users.selected_deck_id`로 선택한다.
- 덱은 총 15장, 카드별 최대 3장, Magic 3종 이상, Type 2종 이상이어야 한다.
- Flyway migration은 실패 시 전체가 rollback되어야 한다.

## Approach (Checklist)

- [x] **Step 0: Recon** (봇 identity, 덱 제약, 카드 카탈로그 확인)
- [x] **Step 1: Design** (9개 컨셉 × 5개 난이도별 고유 영문 이름/성격/덱 정의)
- [x] **Step 2: Implementation** (기존 persona 비활성화 후 45개 user/persona/deck 생성)
- [x] **Step 3: Validation** (관계, 개수, 덱 규칙을 migration 내부에서 검증)
- [x] **Step 4: Publish** (commit, push, PR)

## Validation

- **Commands to run:** Flyway PostgreSQL migration workflow, SQL 정적 검사
- **Expected output:** 봇/user/persona/deck 각각 45개, deck_cards 225행, 모든 덱 15장

## Risks & Rollback

- **Risks:** migration 적용 시 기존 활성 봇이 모두 matchmaking 대상에서 제외된다.
- **Mitigation:** 기존 데이터는 보존하므로 admin에서 필요한 봇을 다시 활성화할 수 있고, 검증 실패 시 전체 rollback한다.
- **Rollback steps:** 운영에서는 후속 migration으로 필요한 seed를 재구성한다.

## Open Questions

- 없음
