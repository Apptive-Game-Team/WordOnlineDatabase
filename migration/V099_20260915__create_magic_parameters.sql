-- Gives a magic a place to hold the values of its own cast, starting with spawn height.
--
-- Until now every number a magic uses has lived on a game object, because the only numbers it had
-- were the stats of the thing it builds. That stops being true the moment the server builds magics
-- from data (issue #155): the height a summon starts at is a property of the cast, not of the unit,
-- and two magics that build the same prefab should be able to differ. parameter_values cannot hold
-- it - that table is keyed by game object - so magic_parameters is its sibling keyed by magic.
--
-- The table mirrors parameter_values on purpose: same column shape, same unique key, same reuse of
-- the parameters name table. Anything that already reads one can read the other the same way, and a
-- value keeps exactly one home either way.
--
-- What goes in now is spawn_height, and only where a magic differs from its family's default. Those
-- differences are today written into Java constructors, which is what the server change
-- (Apptive-Game-Team/WordOnlineServer#564) can no longer read once the classes are gone:
--
--   3.0   the seven summons that start in the air, from GameConfig.AERIAL_MOB_INIT_HEIGHT.
--   0.0   lightning_drop, the one drop that starts on the ground instead of at
--         GameConfig.DROP_MAGIC_INITIAL_HEIGHT (10).
--   0.0   cannon, tower and dragon_tower, whose classes override run() to plant the building at
--         y = 0 rather than at the height of the aim point.
--
-- A magic with no row keeps its family's default, so this table stays small: the 63 magics that
-- already start where their family says get nothing. quantity stays on the unit object in this
-- migration and moves here next; moving it changes what a cast puts on the field, so it travels on
-- its own.

CREATE TABLE IF NOT EXISTS magic_parameters
(
    id           BIGSERIAL PRIMARY KEY,
    magic_id     BIGINT           NOT NULL REFERENCES magics (id) ON DELETE CASCADE,
    parameter_id BIGINT           NOT NULL REFERENCES parameters (id) ON DELETE RESTRICT,
    value        DOUBLE PRECISION,
    updated_at   TIMESTAMP        NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_magic_parameter UNIQUE (magic_id, parameter_id)
);

CREATE INDEX IF NOT EXISTS idx_magic_parameters_magic ON magic_parameters (magic_id);

-- spawn_height is already a name in the parameters table - chicken_commando reads its fall height
-- from one. Inserted defensively the way the registration migrations do.
INSERT INTO parameters (name)
VALUES ('spawn_height')
ON CONFLICT (name) DO NOTHING;

WITH configured(magic_name, parameter_name, value) AS (VALUES
       ('bomb_sprite', 'spawn_height', 3.0),
       ('bubble_spirit', 'spawn_height', 3.0),
       ('cloud_dragon', 'spawn_height', 3.0),
       ('fire_lord_spirit', 'spawn_height', 3.0),
       ('thunder_bird_swarm', 'spawn_height', 3.0),
       ('thunder_spirit', 'spawn_height', 3.0),
       ('wind_spirit', 'spawn_height', 3.0),
       ('lightning_drop', 'spawn_height', 0.0),
       ('cannon', 'spawn_height', 0.0),
       ('tower', 'spawn_height', 0.0),
       ('dragon_tower', 'spawn_height', 0.0)
)
INSERT INTO magic_parameters(magic_id, parameter_id, value)
SELECT magic.id, parameter.id, configured.value
FROM configured
         JOIN magics magic ON magic.name = configured.magic_name
         JOIN parameters parameter ON parameter.name = configured.parameter_name
ON CONFLICT (magic_id, parameter_id)
    DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

DO
$$
    DECLARE
        missing_magics TEXT;
        written_count  INTEGER;
    BEGIN
        SELECT COALESCE(STRING_AGG(configured.magic_name, ', ' ORDER BY configured.magic_name), '')
        INTO missing_magics
        FROM (VALUES ('bomb_sprite'), ('bubble_spirit'), ('cloud_dragon'), ('fire_lord_spirit'),
                     ('thunder_bird_swarm'), ('thunder_spirit'), ('wind_spirit'), ('lightning_drop'),
                     ('cannon'), ('tower'), ('dragon_tower')) AS configured(magic_name)
        WHERE NOT EXISTS (SELECT 1 FROM magics magic WHERE magic.name = configured.magic_name);

        IF missing_magics <> '' THEN
            RAISE EXCEPTION 'these configured names are not magics: %', missing_magics;
        END IF;

        SELECT COUNT(*) INTO written_count FROM magic_parameters;

        IF written_count <> 11 THEN
            RAISE EXCEPTION 'expected 11 cast parameter rows, found %', written_count;
        END IF;

        RAISE NOTICE '% magics carry a cast parameter of their own', written_count;
    END
$$;
