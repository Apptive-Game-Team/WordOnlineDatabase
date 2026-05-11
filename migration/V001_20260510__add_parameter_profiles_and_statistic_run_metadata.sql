create table public.parameter_profiles
(
    id          bigserial
        primary key,
    name        varchar(63)                       not null
        unique,
    parent_profile_id bigint
        constraint fk_parameter_profiles_parent
            references public.parameter_profiles,
    description varchar(255),
    is_default  boolean default false             not null,
    created_at  timestamp default now()          not null,
    updated_at  timestamp default now()          not null
);

alter table public.parameter_profiles
    owner to wordonline;

create table public.parameter_profile_values
(
    id                   bigserial
        primary key,
    parameter_profile_id bigint                             not null
        constraint fk_parameter_profile_values_profile
            references public.parameter_profiles
                on delete cascade,
    parameter_id         bigint                             not null
        constraint fk_parameter_profile_values_parameter
            references public.parameters,
    game_object_id       bigint                             not null
        constraint fk_parameter_profile_values_game_object
            references public.game_objects,
    value                double precision,
    updated_at           timestamp default now()           not null,
    constraint uq_parameter_profile_values_profile_parameter_game_object
        unique (parameter_profile_id, parameter_id, game_object_id)
);

alter table public.parameter_profile_values
    owner to wordonline;

create index idx_parameter_profile_values_updated_at
    on public.parameter_profile_values (updated_at);

insert into public.parameter_profiles (id, name, description, is_default)
values (1, 'Default', 'Falls back to canonical parameter_values', true);

select setval(
    pg_get_serial_sequence('public.parameter_profiles', 'id'),
    (select max(id) from public.parameter_profiles),
    true
);

alter table public.statistic_games
    add column run_type varchar(32) default 'LIVE' not null,
    add column parameter_profile_id bigint default 1 not null,
    add column simulation_batch_id uuid;

alter table public.statistic_games
    add constraint fk_statistic_games_parameter_profile
        foreign key (parameter_profile_id)
            references public.parameter_profiles,
    add constraint chk_statistic_games_run_type
        check (run_type in ('LIVE', 'DEBUG', 'SIMULATION')),
    add constraint chk_statistic_games_simulation_batch
        check (
            (run_type in ('LIVE', 'DEBUG') and simulation_batch_id is null) or
            (run_type = 'SIMULATION' and simulation_batch_id is not null)
        );

create index idx_statistic_games_run_type
    on public.statistic_games (run_type);

create index idx_statistic_games_parameter_profile_id
    on public.statistic_games (parameter_profile_id);

create index idx_statistic_games_simulation_batch_id
    on public.statistic_games (simulation_batch_id);
