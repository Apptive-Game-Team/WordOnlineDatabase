create table public.balance_proposals
(
    id                      bigserial
        primary key,
    status                  varchar(31)              not null,
    simulation_status       varchar(31)              not null,
    analysis_window_days    integer                  not null,
    analysis_from           timestamp,
    analysis_to             timestamp,
    min_matches             integer                  not null,
    target_win_rate_min     double precision         not null,
    target_win_rate_max     double precision         not null,
    simulation_profile_id   bigint
        constraint fk_balance_proposals_simulation_profile
            references public.parameter_profiles,
    simulation_batch_id     varchar(255),
    simulation_summary_json text,
    rejection_reason        text,
    approved_at             timestamp,
    applied_at              timestamp,
    created_at              timestamp default now()  not null,
    updated_at              timestamp default now()  not null,
    constraint chk_balance_proposals_status
        check ((status)::text = any
               ((array ['DRAFT'::character varying, 'APPROVED'::character varying, 'APPLIED'::character varying, 'REJECTED'::character varying])::text[])),
    constraint chk_balance_proposals_simulation_status
        check ((simulation_status)::text = any
               ((array ['PENDING'::character varying, 'SUCCEEDED'::character varying, 'FAILED'::character varying])::text[]))
);

alter table public.balance_proposals
    owner to wordonline;

create index idx_balance_proposals_status
    on public.balance_proposals (status);

create index idx_balance_proposals_simulation_status
    on public.balance_proposals (simulation_status);

create index idx_balance_proposals_simulation_profile_id
    on public.balance_proposals (simulation_profile_id);

create index idx_balance_proposals_created_at
    on public.balance_proposals (created_at);

create table public.balance_proposal_items
(
    id                  bigserial
        primary key,
    proposal_id         bigint not null
        constraint fk_balance_proposal_items_proposal
            references public.balance_proposals
            on delete cascade,
    magic_id            bigint,
    magic_name          varchar(255),
    card_id             bigint,
    card_name           varchar(255),
    game_object_id      bigint,
    game_object_name    varchar(255),
    parameter_value_id  bigint,
    parameter_id        bigint,
    parameter_name      varchar(255),
    current_value       double precision,
    proposed_value      double precision,
    change_rate         double precision,
    reason              varchar(255),
    live_metrics_json   text,
    apply_snapshot_json text
);

alter table public.balance_proposal_items
    owner to wordonline;

create index idx_balance_proposal_items_proposal_id
    on public.balance_proposal_items (proposal_id);

create index idx_balance_proposal_items_parameter_value_id
    on public.balance_proposal_items (parameter_value_id);

create index idx_balance_proposal_items_magic_id
    on public.balance_proposal_items (magic_id);

create index idx_balance_proposal_items_card_id
    on public.balance_proposal_items (card_id);
