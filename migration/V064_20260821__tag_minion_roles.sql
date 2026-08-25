-- Gives the swarm minions the role tag their behaviour already says they have.
--
-- Before this file only five game objects carried CAT_Melee, so the rule
-- ('CAT_Ranged', 'CAT_Melee', 1.5) seeded by V056 almost never matched anything: the units
-- a player actually walks into a ranged answer -- the slime family, ember_spirit,
-- seed_spirit, mini_rock -- had a size tag and nothing else. The bot could not tell a melee
-- swarm from an artillery piece.
--
-- Each role below is read off the prefab initializer on the game server rather than
-- guessed:
--
--   Slime (fire/rock/leaf/wind/electric), mini_rock  -> Slime extends MeleeAttackMob
--   ember_spirit, seed_spirit                        -> extend FireSlime/LeafSlime
--   water_slime                                      -> WaterSlimeRangeAttackMob
--   wind_spirit                                      -> SelfDestructMob, closes then blasts
--   pve_vine_witch                                   -> SimplePveBossInitializer, speed 0
--
-- dimension_toad is left with no role on purpose. It runs NonAttackingCowardMob: it never
-- attacks, so none of the attacker roles describe it, and CAT_Large already exposes it to
-- the CC rule.

WITH required_tags(tag_name) AS (
    VALUES ('CAT_Melee'),
           ('CAT_Ranged'),
           ('CAT_AoE'),
           ('CAT_Building')
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
        -- MeleeAttackMob bodies.
        ('slime', 'CAT_Melee'),
        ('fire_slime', 'CAT_Melee'),
        ('rock_slime', 'CAT_Melee'),
        ('leaf_slime', 'CAT_Melee'),
        ('wind_slime', 'CAT_Melee'),
        ('electric_slime', 'CAT_Melee'),
        ('mini_rock', 'CAT_Melee'),
        ('ember_spirit', 'CAT_Melee'),
        ('seed_spirit', 'CAT_Melee'),

        -- The one slime that shoots. It shares the family's parameters and its size tag,
        -- which is why it looked like the rest until the mob class was checked.
        ('water_slime', 'CAT_Ranged'),

        -- Walks into contact, then damages everything inside explosionRange.
        ('wind_spirit', 'CAT_Melee'),
        ('wind_spirit', 'CAT_AoE'),

        -- Boss with speed 0. It cannot step out of an area magic, which is what CAT_Building
        -- means in tag_counter_rules; the two nest bosses next to it already carry it. This
        -- is also why it has no size tag: size is for bodies that move.
        ('pve_vine_witch', 'CAT_Building')
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

-- water_slime_swarm and the other swarm magics do not share a name with the object they
-- spawn, so this call does not reach them; V065 adds the alias that does.
SELECT sync_magic_tags_from_game_objects();

DO
$$
    DECLARE
        missing_role_name TEXT;
        melee_count       INTEGER;
    BEGIN
        SELECT go.name
        INTO missing_role_name
        FROM game_objects go
        WHERE go.name IN ('slime', 'fire_slime', 'rock_slime', 'leaf_slime', 'wind_slime',
                          'electric_slime', 'mini_rock', 'ember_spirit', 'seed_spirit',
                          'water_slime', 'wind_spirit', 'pve_vine_witch')
          AND NOT EXISTS (SELECT 1
                          FROM game_object_tags got
                                   JOIN tags t ON t.id = got.tag_id
                          WHERE got.game_object_id = go.id
                            AND t.name IN ('CAT_Melee', 'CAT_Ranged', 'CAT_Building',
                                           'CAT_Tank', 'CAT_AoE', 'CAT_CC'))
        LIMIT 1;

        IF missing_role_name IS NOT NULL THEN
            RAISE EXCEPTION 'game object % still has no role tag', missing_role_name;
        END IF;

        SELECT COUNT(*)
        INTO melee_count
        FROM game_object_tags got
                 JOIN tags t ON t.id = got.tag_id
        WHERE t.name = 'CAT_Melee';

        IF melee_count < 15 THEN
            RAISE EXCEPTION 'CAT_Melee covers only % objects; the melee rule stays unreachable',
                melee_count;
        END IF;
    END
$$;
