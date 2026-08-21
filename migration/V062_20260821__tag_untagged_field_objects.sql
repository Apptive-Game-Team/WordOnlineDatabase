-- Fills the game_object_tags gaps that a full audit of V000..V061 turned up.
--
-- Rebuilding the whole chain on a scratch PostgreSQL and listing every game object with no
-- tag row produced five entries that stand on the field during a real match. Two of them
-- have no game_objects row at all, so V026's tag rows for them joined to nothing and were
-- dropped without a word -- the exact silent failure the counter tag contract exists to
-- prevent.
--
-- No parameter rows are added. rock_remnant reads MINI_ROCK's parameters and
-- pve_vine_colony reads vine_colony's, both by name from the prefab initializer, so a
-- dedicated parameter set would be unread data.

-- pve_vine_colony and rock_remnant: registered so they can carry tags at all.
INSERT INTO game_objects(name)
SELECT missing.name
FROM (VALUES ('pve_vine_colony'), ('rock_remnant')) AS missing(name)
WHERE NOT EXISTS (SELECT 1 FROM game_objects existing WHERE existing.name = missing.name);

WITH required_tags(tag_name) AS (
    VALUES ('TYPE_Unit'),
           ('CAT_AoE'),
           ('CAT_Building'),
           ('CAT_Ranged')
),
inserted_tags AS (
    INSERT INTO tags(name)
        SELECT rt.tag_name
        FROM required_tags rt
        WHERE NOT EXISTS (SELECT 1 FROM tags t WHERE t.name = rt.tag_name)
        RETURNING id, name
),
target_tags AS (
    SELECT id, name FROM inserted_tags
    UNION ALL
    SELECT t.id, t.name
    FROM tags t
             JOIN required_tags rt ON rt.tag_name = t.name
),
mapping(game_object_name, tag_name) AS (
    VALUES
        -- Stationary nature boss that spawns waves. Same shape as pve_nature_slime_nest and
        -- pve_water_slime_nest, and the same three tags V026 already intended for it.
        ('pve_vine_colony', 'TYPE_Unit'),
        ('pve_vine_colony', 'CAT_Building'),
        ('pve_vine_colony', 'CAT_Ranged'),

        -- Rubble left by a dead rock body: a collider with no hp, no attack, and a 20 second
        -- life. TYPE_Unit because it occupies the field, and deliberately no CAT_* tag --
        -- every CAT_* on a target is something an attacker converts output against, and
        -- teaching the bot that its area magic pays off on rubble would waste the cast.
        ('rock_remnant', 'TYPE_Unit'),

        -- Buff drop: falls, triggers once inside attackRange, applies Frenzy, destroys
        -- itself. Tagged like rallying_torch/rallying_totem, the existing buff drop, so the
        -- two read the same. The vocabulary has no buff tag and inventing one is out of
        -- scope here.
        ('frenzy_totem', 'TYPE_Unit'),
        ('frenzy_totem', 'CAT_AoE'),

        -- Nature damage drop with a radius, same shape as leaf_drop.
        ('leafair', 'TYPE_Unit'),
        ('leafair', 'CAT_AoE'),

        -- Shoot magic: a line of vines away from the caster. Tagged CAT_Ranged like the
        -- other shoot magics. It does hit more than one target, but adding CAT_AoE would
        -- change what the bot prefers rather than fill a gap, so it stays for a balance pass.
        --
        -- The vine_toss game object is what magic_tags derives from, through the shared
        -- name. At runtime VineTossMagic spawns PrefabType.Vine, not PrefabType.VineToss;
        -- these tags describe what the magic puts on the field, which is what the bot scores.
        ('vine_toss', 'TYPE_Unit'),
        ('vine_toss', 'CAT_Ranged')
)
INSERT INTO game_object_tags(game_object_id, tag_id)
SELECT go.id, tt.id
FROM mapping m
         JOIN game_objects go ON go.name = m.game_object_name
         JOIN target_tags tt ON tt.name = m.tag_name
WHERE NOT EXISTS (SELECT 1
                  FROM game_object_tags existing
                  WHERE existing.game_object_id = go.id
                    AND existing.tag_id = tt.id);

-- frenzy_totem, leafair and vine_toss are magics under the same names, so the tags added
-- above become their magic tags.
SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        untagged_name TEXT;
    BEGIN
        SELECT go.name
        INTO untagged_name
        FROM game_objects go
        WHERE go.name IN
              ('pve_vine_colony', 'rock_remnant', 'frenzy_totem', 'leafair', 'vine_toss')
          AND NOT EXISTS (SELECT 1 FROM game_object_tags got WHERE got.game_object_id = go.id)
        LIMIT 1;

        IF untagged_name IS NOT NULL THEN
            RAISE EXCEPTION 'game object % still has no tags', untagged_name;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM game_objects WHERE name = 'pve_vine_colony')
            OR NOT EXISTS (SELECT 1 FROM game_objects WHERE name = 'rock_remnant') THEN
            RAISE EXCEPTION 'pve_vine_colony or rock_remnant was not registered';
        END IF;
    END
$$;
