-- tags.name has never been unique on a database that predates V026.
--
-- V000 created tags(id bigserial primary key, name varchar(20)) with no constraint on the
-- name. V026 later wrote CREATE TABLE IF NOT EXISTS tags (..., name VARCHAR(20) UNIQUE),
-- which is a no-op against a table that already exists: only databases created from V026
-- onward got the constraint. V032 then worked around the gap in a comment -- "no unique
-- constraint -> anti-join" -- rather than closing it.
--
-- Nothing fails when two tags share a name. The game server's TagRepository.getCounterWeight
-- joins tag_counter_rules to tags by *name* and SUMs the weights, so a duplicated name adds
-- its rules twice and that one matchup is scored at double weight, with no error anywhere.
-- The admin server can create the duplicate in the first place: /admin/tag's TagService.addTag
-- does not check the name. And the admin counter-rule screen keys rules by tag-name pair, so
-- a duplicate turns its scalar subquery into `more than one row returned by a subquery`.
--
-- This migration collapses each name onto one surviving tag row, repoints every reference,
-- and then adds the constraint so the situation cannot come back.

-- The whole rewrite is driven by one mapping, materialised once so that every statement
-- below agrees on the same survivor even as rows are deleted.
--
-- The survivor is the lowest id of each name. It is deterministic, so a re-run or a second
-- environment picks the same row, and it is the oldest row, so the references that were
-- never duplicated -- the ones written before someone added the second tag -- are the ones
-- that stay put. Tags that are already unique map to themselves, which is what makes every
-- statement below a no-op on a database with no duplicates.
CREATE TEMP TABLE tag_canonical AS
SELECT tag.id                                AS tag_id,
       COALESCE(survivor.survivor_tag_id, tag.id) AS canonical_tag_id
FROM tags tag
         LEFT JOIN (SELECT name, MIN(id) AS survivor_tag_id
                    FROM tags
                    -- A NULL name is not a duplicate of another NULL name: PostgreSQL's
                    -- UNIQUE treats NULLs as distinct, so those rows are left alone.
                    WHERE name IS NOT NULL
                    GROUP BY name) survivor ON survivor.name = tag.name;

-- Every table that references tags(id), confirmed against the catalog rather than assumed.
-- A table added later would be repointed by nothing and its rows would be destroyed by the
-- tags delete below -- silently, in magic_tags' case, because that foreign key cascades.
-- Failing here costs a rewritten migration; not failing costs data nobody notices is gone.
DO
$$
    DECLARE
        unhandled_references TEXT;
    BEGIN
        SELECT string_agg(format('%s.%s', referencing_table.relname, referencing_column.attname), ', ')
        INTO unhandled_references
        FROM pg_constraint foreign_key
                 JOIN pg_class referencing_table ON referencing_table.oid = foreign_key.conrelid
                 JOIN pg_attribute referencing_column
                      ON referencing_column.attrelid = foreign_key.conrelid
                          AND referencing_column.attnum = ANY (foreign_key.conkey)
        WHERE foreign_key.contype = 'f'
          AND foreign_key.confrelid = 'tags'::regclass
          AND (referencing_table.relname, referencing_column.attname) NOT IN
              (('game_object_tags', 'tag_id'),
               ('magic_tags', 'tag_id'),
               ('tag_counter_rules', 'attacker_tag_id'),
               ('tag_counter_rules', 'target_tag_id'));

        IF unhandled_references IS NOT NULL THEN
            RAISE EXCEPTION 'These columns reference tags(id) and this migration does not repoint them: %', unhandled_references;
        END IF;
    END
$$;

-- Collisions are removed before each repoint, never after. Each of these tables has its own
-- uniqueness over a pair that includes the tag, so moving two rows of one name onto the
-- survivor would violate it, and a failed UPDATE aborts the entire migration instead of
-- dropping one row. The row deleted here and the row that survives are identical in meaning
-- once both point at the survivor, so nothing is lost.

-- uq_game_object_id_tag_id: (game_object_id, tag_id).
--
-- Ordering by tag_id keeps the survivor's own row whenever the object already carries it,
-- because the survivor holds the lowest id in its name group. Where the object only ever
-- got the duplicates, the lowest of those wins and is repointed by the next statement.
DELETE
FROM game_object_tags losing
    USING tag_canonical losing_canonical
WHERE losing_canonical.tag_id = losing.tag_id
  AND losing_canonical.canonical_tag_id <> losing.tag_id
  AND EXISTS (SELECT 1
              FROM game_object_tags keeping
                       JOIN tag_canonical keeping_canonical ON keeping_canonical.tag_id = keeping.tag_id
              WHERE keeping.game_object_id = losing.game_object_id
                AND keeping_canonical.canonical_tag_id = losing_canonical.canonical_tag_id
                AND keeping.tag_id < losing.tag_id);

UPDATE game_object_tags game_object_tag
SET tag_id = canonical.canonical_tag_id
FROM tag_canonical canonical
WHERE canonical.tag_id = game_object_tag.tag_id
  AND canonical.canonical_tag_id <> game_object_tag.tag_id;

-- magic_tags primary key: (magic_id, tag_id). Same shape as above; the table has no
-- surrogate key, so the tie is broken on tag_id directly.
DELETE
FROM magic_tags losing
    USING tag_canonical losing_canonical
WHERE losing_canonical.tag_id = losing.tag_id
  AND losing_canonical.canonical_tag_id <> losing.tag_id
  AND EXISTS (SELECT 1
              FROM magic_tags keeping
                       JOIN tag_canonical keeping_canonical ON keeping_canonical.tag_id = keeping.tag_id
              WHERE keeping.magic_id = losing.magic_id
                AND keeping_canonical.canonical_tag_id = losing_canonical.canonical_tag_id
                AND keeping.tag_id < losing.tag_id);

UPDATE magic_tags magic_tag
SET tag_id = canonical.canonical_tag_id
FROM tag_canonical canonical
WHERE canonical.tag_id = magic_tag.tag_id
  AND canonical.canonical_tag_id <> magic_tag.tag_id;

-- uq_tag_counter_rules_pair: (attacker_tag_id, target_tag_id). Both columns reference tags,
-- so the group here is the canonical *pair*, and the tie is broken on the pair as a tuple.
-- The canonical pair is the component-wise minimum, so the already-canonical rule sorts
-- first and is the one kept.
--
-- The weights of the collapsed rules are not added together. Their sum is precisely the bug
-- this migration exists to remove: one matchup scored at double weight because the same rule
-- was reachable through two tags of the same name. The surviving rule keeps its own weight.
DELETE
FROM tag_counter_rules losing
    USING tag_canonical losing_attacker, tag_canonical losing_target
WHERE losing_attacker.tag_id = losing.attacker_tag_id
  AND losing_target.tag_id = losing.target_tag_id
  AND (losing_attacker.canonical_tag_id, losing_target.canonical_tag_id)
    <> (losing.attacker_tag_id, losing.target_tag_id)
  AND EXISTS (SELECT 1
              FROM tag_counter_rules keeping
                       JOIN tag_canonical keeping_attacker ON keeping_attacker.tag_id = keeping.attacker_tag_id
                       JOIN tag_canonical keeping_target ON keeping_target.tag_id = keeping.target_tag_id
              WHERE keeping_attacker.canonical_tag_id = losing_attacker.canonical_tag_id
                AND keeping_target.canonical_tag_id = losing_target.canonical_tag_id
                AND (keeping.attacker_tag_id, keeping.target_tag_id)
                  < (losing.attacker_tag_id, losing.target_tag_id));

UPDATE tag_counter_rules rule
SET attacker_tag_id = canonical_attacker.canonical_tag_id,
    target_tag_id   = canonical_target.canonical_tag_id
FROM tag_canonical canonical_attacker, tag_canonical canonical_target
WHERE canonical_attacker.tag_id = rule.attacker_tag_id
  AND canonical_target.tag_id = rule.target_tag_id
  AND (canonical_attacker.canonical_tag_id, canonical_target.canonical_tag_id)
    <> (rule.attacker_tag_id, rule.target_tag_id);

-- Nothing points at the duplicates any more. If anything still did, game_object_tags' and
-- tag_counter_rules' foreign keys would abort this statement, which is the outcome to want.
DELETE
FROM tags
WHERE id IN (SELECT tag_id FROM tag_canonical WHERE canonical_tag_id <> tag_id);

DROP TABLE tag_canonical;

-- Idempotent because a database created from V026 onward already carries the constraint
-- under the name PostgreSQL generated for the inline UNIQUE, tags_name_key. The check is on
-- the shape -- any unique index over exactly (name) -- rather than on a name we would have
-- to guess.
DO
$$
    BEGIN
        IF EXISTS (SELECT 1
                   FROM pg_index unique_index
                   WHERE unique_index.indrelid = 'tags'::regclass
                     AND unique_index.indisunique
                     AND unique_index.indnatts = 1
                     AND unique_index.indkey[0] = (SELECT attnum
                                                   FROM pg_attribute
                                                   WHERE attrelid = 'tags'::regclass
                                                     AND attname = 'name')) THEN
            RAISE NOTICE 'tags.name is already unique; leaving the existing constraint in place';
        ELSE
            ALTER TABLE tags
                ADD CONSTRAINT uq_tags_name UNIQUE (name);
            RAISE NOTICE 'Added uq_tags_name';
        END IF;
    END
$$;

DO
$$
    DECLARE
        duplicate_name_count INTEGER;
        unique_index_count   INTEGER;
    BEGIN
        -- NULL names are excluded here for the same reason they were excluded from the
        -- mapping: UNIQUE permits any number of them, so counting them as duplicates would
        -- fail a database that the constraint accepts.
        SELECT COUNT(*)
        INTO duplicate_name_count
        FROM (SELECT name FROM tags WHERE name IS NOT NULL GROUP BY name HAVING COUNT(*) > 1) duplicate;

        IF duplicate_name_count > 0 THEN
            RAISE EXCEPTION 'tags still holds % duplicated names after the merge', duplicate_name_count;
        END IF;

        SELECT COUNT(*)
        INTO unique_index_count
        FROM pg_index unique_index
        WHERE unique_index.indrelid = 'tags'::regclass
          AND unique_index.indisunique
          AND unique_index.indnatts = 1
          AND unique_index.indkey[0] = (SELECT attnum
                                        FROM pg_attribute
                                        WHERE attrelid = 'tags'::regclass
                                          AND attname = 'name');

        IF unique_index_count = 0 THEN
            RAISE EXCEPTION 'tags.name carries no unique constraint; duplicates can still be created';
        END IF;
    END
$$;
