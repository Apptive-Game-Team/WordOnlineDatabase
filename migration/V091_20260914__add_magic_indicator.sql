-- This is the main-track twin of WordOnlineDatabase PR #138 (magic-card track, migration
-- V090). The two tracks are deliberately not merged into each other, so the same
-- client-drawn indicator feature is built here against this chain's own data model, which
-- differs from magic-card's in the ways that matter below.
--
-- On this chain magics has no aim_shape column at all: that column was introduced by V084 on
-- the magic-card track only. Today's client instead decides the aim shape straight from
-- magics.cast_type at draw time (cast_type = 'shoot' draws a lane, everything else draws a
-- circle), so there is no aim_shape value to migrate and nothing to delete here.
--
-- Document contract (version 1), fixed by the client that reads it and not to be changed here:
--
--   {"version": 1, "layers": [<layer>, ...]}
--
-- Every layer below references the magic's own parameters rather than inlining numbers, so a
-- later balance change to radius/attack_range/attack_offset keeps matching the drawn
-- indicator without touching this table again.

-- ---------------------------------------------------------------------------- the column
ALTER TABLE magics
    ADD COLUMN IF NOT EXISTS indicator jsonb;

-- --------------------------------------------------------------------------- the backfill
--
-- A magic's own parameters are found the way the rest of this repository finds them:
-- magics.name = game_objects.name, then parameter_values joined to parameters by name. On
-- the magic-card track that join is guaranteed to hit because V084 seeds a game_objects row
-- for every magic; that migration does not exist on this chain. Here a game_objects row
-- keyed by the magic's own name exists only for magics that a registration migration (or the
-- V032 dev backfill) gave one explicitly - V010 (rock_drop), V006 (leafair), V012
-- (lightning_explosion), V019 (shock_overload), V033 (vine_world) and V035 (seed_nest) are
-- examples of magics with no such row at all. Roughly 50 more magics exist only in the
-- operational database per README.md and cannot be checked from these files either. The join
-- below is a LEFT JOIN on purpose: a magic with no matching game_objects row must still get a
-- base layer, or the SET NOT NULL two statements down would abort the whole migration with a
-- null-values error the moment it hit the first such magic. A magic with nothing of its own
-- also has no attack_range value to find, so it correctly gets the base layer only.
--
-- The base layer needs no game_objects join at all: cast_type already lives directly on the
-- magics row on this chain (added by V047), so it reads straight off magic.cast_type. The
-- check constraint added there restricts cast_type to 'spawn', 'drop', 'explode', 'build' and
-- 'shoot' (lower case) and has been NOT NULL ever since, so every magic on this chain
-- resolves to exactly one of the two base shapes below - there is no null or unmapped case to
-- handle.
--
--   cast_type = 'shoot'      -> a lane from the caster to the aim point, half width the
--                                magic's own radius parameter (today's client draws exactly
--                                this for a Shoot cast).
--   any other cast_type      -> a filled circle at the aim point, radius the magic's own
--                                radius parameter (today's client draws exactly this for
--                                everything else).
--
-- attack_layer is additional: a magic whose own game_objects row also carries an attack_range
-- parameter value gets a second layer showing where the built object will actually strike.
-- Checked against this chain: of the six magics V077-V082 registered, only dragon_tower and
-- firework_tower carry attack_range at all (wall_golem, shock_trap, repair_totem and
-- grass_generator carry neither); firework_tower is also the only magic on this chain that
-- carries attack_offset, so its parameter row already exists and every other magic falls back
-- to 0. dragon_tower is the one exception to the generic ring shape: the client special-cases
-- it by name today to fire forward down a lane instead of striking a circle, which is exactly
-- the hack this feature exists to remove, so it gets a lane attack layer instead of the
-- generic one. The 0.4 half width on that lane is a bare number on purpose - it is only a
-- visual hint for the lane's direction and no parameter carries it; the true value would be
-- the projectile's explosion radius, which the client has no way to read.
WITH magic_object AS (SELECT magic.id          AS magic_id,
                             magic.name        AS magic_name,
                             magic.cast_type   AS cast_type,
                             game_object.id    AS game_object_id
                      FROM magics magic
                               LEFT JOIN game_objects game_object ON game_object.name = magic.name),
     base_layer AS (SELECT magic_id,
                           1 AS layer_order,
                           CASE
                               WHEN cast_type = 'shoot' THEN
                                   jsonb_build_object('shape', 'lane',
                                                       'origin', 'caster',
                                                       'end', 'target',
                                                       'halfWidth', jsonb_build_object('parameter', 'radius'))
                               ELSE
                                   jsonb_build_object('shape', 'circle',
                                                       'origin', 'target',
                                                       'radius', jsonb_build_object('parameter', 'radius'))
                               END AS layer
                    FROM magic_object),
     attack_layer AS (SELECT magic_object.magic_id,
                             2 AS layer_order,
                             CASE
                                 WHEN magic_object.magic_name = 'dragon_tower' THEN
                                     jsonb_build_object('shape', 'lane',
                                                         'origin', 'target',
                                                         'end', 'forward',
                                                         'length', jsonb_build_object('parameter', 'attack_range'),
                                                         'halfWidth', 0.4)
                                 ELSE
                                     jsonb_build_object('shape', 'circle',
                                                         'origin', 'target',
                                                         'forwardOffset',
                                                         jsonb_build_object('parameter', 'attack_offset', 'fallback',
                                                                             0),
                                                         'radius', jsonb_build_object('parameter', 'attack_range'),
                                                         'edgeWidth', 0.08)
                                 END AS layer
                      FROM magic_object
                               JOIN parameters attack_range_parameter ON attack_range_parameter.name = 'attack_range'
                               JOIN parameter_values attack_range_value
                                    ON attack_range_value.game_object_id = magic_object.game_object_id
                                        AND attack_range_value.parameter_id = attack_range_parameter.id
                                        AND attack_range_value.value IS NOT NULL),
     layer_row AS (SELECT * FROM base_layer
                   UNION ALL
                   SELECT * FROM attack_layer),
     magic_indicator AS (SELECT magic_id,
                                jsonb_agg(layer ORDER BY layer_order) AS layers
                         FROM layer_row
                         GROUP BY magic_id)
UPDATE magics
SET indicator = jsonb_build_object('version', 1, 'layers', magic_indicator.layers)
FROM magic_indicator
WHERE magic_indicator.magic_id = magics.id
  AND magics.indicator IS NULL;

-- The default matters as much as the NOT NULL. Registration migrations land on this chain
-- constantly (V077 through V082 alone registered six magics) and none of them names a column
-- that did not exist when it was written. Without a default, the next such migration fails
-- with a null-value-violates-not-null error on this column and the dev database stops
-- migrating. A base circle at the aim point sized by the magic's own radius parameter is what
-- a newly registered magic should draw anyway, and it is exactly what the backfill above
-- writes for every magic with no more specific shape, so the default and the backfill agree.
-- A magic that needs a lane or a strike layer sets indicator explicitly in its own
-- registration migration.
ALTER TABLE magics
    ALTER COLUMN indicator SET DEFAULT
        '{"version": 1, "layers": [{"shape": "circle", "origin": "target", "radius": {"parameter": "radius"}}]}'::jsonb;

ALTER TABLE magics
    ALTER COLUMN indicator SET NOT NULL;

-- --------------------------------------------------------------------------- assertions
DO
$$
    DECLARE
        magic_count         INTEGER;
        uncovered_names     TEXT;
        malformed_names     TEXT;
        lane_count          INTEGER;
        circle_count        INTEGER;
        attack_layer_count  INTEGER;
    BEGIN
        SELECT COUNT(*) INTO magic_count FROM magics;

        SELECT COALESCE(STRING_AGG(magic.name, ', ' ORDER BY magic.name), '')
        INTO uncovered_names
        FROM magics magic
        WHERE magic.indicator IS NULL
           OR magic.indicator -> 'layers' IS NULL
           OR jsonb_array_length(magic.indicator -> 'layers') = 0;

        IF uncovered_names <> '' THEN
            RAISE EXCEPTION 'these magics have a null or empty indicator: %', uncovered_names;
        END IF;

        SELECT COALESCE(STRING_AGG(magic.name, ', ' ORDER BY magic.name), '')
        INTO malformed_names
        FROM magics magic
        WHERE (magic.indicator ->> 'version') IS DISTINCT FROM '1'
           OR jsonb_typeof(magic.indicator -> 'layers') IS DISTINCT FROM 'array';

        IF malformed_names <> '' THEN
            RAISE EXCEPTION 'these magics do not carry version 1 with a layers array: %', malformed_names;
        END IF;

        SELECT COUNT(*) FILTER (WHERE layer ->> 'shape' = 'lane'),
               COUNT(*) FILTER (WHERE layer ->> 'shape' = 'circle' AND layer -> 'edgeWidth' IS NULL),
               COUNT(*) FILTER (WHERE layer -> 'edgeWidth' IS NOT NULL OR
                                      (layer ->> 'shape' = 'lane' AND layer ->> 'origin' = 'target'))
        INTO lane_count, circle_count, attack_layer_count
        FROM magics magic,
             jsonb_array_elements(magic.indicator -> 'layers') AS layer;

        RAISE NOTICE '% magics carry a non-empty version-1 indicator', magic_count;
        RAISE NOTICE '% layers across all magics are a lane (shoot base layer, or dragon_tower attack layer)', lane_count;
        RAISE NOTICE '% layers across all magics are a base circle', circle_count;
        RAISE NOTICE '% magics additionally carry an attack_range strike layer (ring or lane)', attack_layer_count;
    END
$$;
