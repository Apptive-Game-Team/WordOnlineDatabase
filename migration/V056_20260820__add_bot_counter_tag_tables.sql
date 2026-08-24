-- Bot counter scoring has never run in production.
--
-- The game server's BotCounterEvaluator reads magic_tags and tag_counter_rules through
-- TagRepository, but both tables only ever existed in the game server's H2 test schema.
-- Against the real database the query throws, the evaluator catches it and returns the
-- neutral score 0.0, so every bot has been playing without any counter awareness and
-- nothing ever failed loudly. This migration creates the two tables and seeds them.
--
-- Elemental counters are deliberately absent. ElementalChart on the game server already
-- owns the element multiplier table, real damage is computed from it, and the client's
-- magic book mirrors it. Restating those relationships here would make two sources of
-- truth for one rule, and the bot's copy would silently fall behind the next balance pass.
-- tag_counter_rules covers only what elements cannot express: structural matchups.

CREATE TABLE IF NOT EXISTS magic_tags
(
    magic_id BIGINT NOT NULL REFERENCES magics (id) ON DELETE CASCADE,
    tag_id   BIGINT NOT NULL REFERENCES tags (id) ON DELETE CASCADE,
    PRIMARY KEY (magic_id, tag_id)
);

CREATE TABLE IF NOT EXISTS tag_counter_rules
(
    id              BIGSERIAL PRIMARY KEY,
    attacker_tag_id BIGINT           NOT NULL REFERENCES tags (id),
    target_tag_id   BIGINT           NOT NULL REFERENCES tags (id),
    weight          DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    CONSTRAINT uq_tag_counter_rules_pair UNIQUE (attacker_tag_id, target_tag_id)
);

CREATE INDEX IF NOT EXISTS idx_magic_tags_magic_id
    ON magic_tags (magic_id);

-- A magic is tagged with the properties of the object it puts on the field. Both tables
-- use one name space -- 'bubble_spirit' is a magic and the game object it creates -- so the
-- tags are derived from game_object_tags rather than hand-listed. A hand-listed copy is
-- exactly the kind of data that goes stale the first time a unit is re-categorised.
INSERT INTO magic_tags(magic_id, tag_id)
SELECT magic.id, game_object_tag.tag_id
FROM magics magic
         JOIN game_objects game_object ON game_object.name = magic.name
         JOIN game_object_tags game_object_tag ON game_object_tag.game_object_id = game_object.id
WHERE NOT EXISTS (SELECT 1
                  FROM magic_tags existing
                  WHERE existing.magic_id = magic.id
                    AND existing.tag_id = game_object_tag.tag_id);

-- Structural matchups only. Each rule states "an attacker carrying this tag converts more
-- of its output against a target carrying that tag", and the weight is the bot's score
-- bonus, not a damage multiplier -- nothing in the simulation reads this table.
--
-- Flying is not represented. CAT_Flying exists as a descriptive tag, but the word "flying"
-- appears nowhere in the game server: ground units hit airborne ones normally, so an
-- anti-air rule would teach the bot a matchup the game does not actually have.
WITH rule(attacker_name, target_name, weight) AS (
    VALUES
        -- Small units arrive in groups, so one area hit lands on several of them at once.
        ('CAT_AoE', 'CAT_Small', 2.0),
        -- Buildings do not move out of the area.
        ('CAT_AoE', 'CAT_Building', 1.5),
        -- Range beats a target that has to close the distance first.
        ('CAT_Ranged', 'CAT_Melee', 1.5),
        -- Crowd control buys the time that a slow, high-value body needs to be worth its cost.
        ('CAT_CC', 'CAT_Tank', 1.5),
        ('CAT_CC', 'CAT_Large', 1.5)
)
INSERT
INTO tag_counter_rules(attacker_tag_id, target_tag_id, weight)
SELECT attacker.id, target.id, rule.weight
FROM rule
         JOIN tags attacker ON attacker.name = rule.attacker_name
         JOIN tags target ON target.name = rule.target_name
WHERE NOT EXISTS (SELECT 1
                  FROM tag_counter_rules existing
                  WHERE existing.attacker_tag_id = attacker.id
                    AND existing.target_tag_id = target.id);

DO
$$
    DECLARE
        rule_count           INTEGER;
        tagged_magic_count   INTEGER;
        untagged_magic_count INTEGER;
    BEGIN
        SELECT COUNT(*) INTO rule_count FROM tag_counter_rules;
        IF rule_count < 5 THEN
            RAISE EXCEPTION 'tag_counter_rules seeding is incomplete: % rules', rule_count;
        END IF;

        SELECT COUNT(DISTINCT magic_id) INTO tagged_magic_count FROM magic_tags;
        IF tagged_magic_count = 0 THEN
            RAISE EXCEPTION 'magic_tags is empty; the magics/game_objects name join produced nothing';
        END IF;

        -- Not fatal: a magic that creates no lasting object legitimately has no tags. It is
        -- reported so the gap is visible in the migration log instead of only showing up as
        -- a bot that quietly ignores that magic.
        SELECT COUNT(*)
        INTO untagged_magic_count
        FROM magics magic
        WHERE NOT EXISTS (SELECT 1 FROM magic_tags mt WHERE mt.magic_id = magic.id);

        RAISE NOTICE 'magic_tags covers % magics; % magics have no tags', tagged_magic_count, untagged_magic_count;
    END
$$;
