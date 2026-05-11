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

insert into public.parameter_profiles (id, name, description, is_default)
values (1, 'Default', 'Canonical live parameter profile', true);

select setval(
    pg_get_serial_sequence('public.parameter_profiles', 'id'),
    (select max(id) from public.parameter_profiles),
    true
);

alter table public.parameter_values
    add column parameter_profile_id bigint default 1 not null;

alter table public.parameter_values
    add constraint fk_parameter_values_parameter_profile
        foreign key (parameter_profile_id)
            references public.parameter_profiles,
    drop constraint if exists uq_parameter_game_object,
    add constraint uq_parameter_values_profile_parameter_game_object
        unique (parameter_profile_id, parameter_id, game_object_id);

create index idx_parameter_values_parameter_profile_id
    on public.parameter_values (parameter_profile_id);

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
