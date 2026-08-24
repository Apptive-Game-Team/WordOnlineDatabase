---
name: register-game-object
description: Write a Flyway migration that registers a new game object or magic in the shared game database, including the counter tags the bot needs. Use when adding a unit, building, projectile, or magic to `migration/`, or when a client-side skill hands off the server portion of a new magic.
---

# Register Game Object

Use this skill when a new unit, building, projectile, or magic has to exist in the shared
game database.

The client skills `make-magic` and `make-prefab` cover localization, sprites, and prefabs
only; they state that server work is out of their scope. This skill is where that work
lands.

## Why tags are not optional

`BotCounterEvaluator` on the game server scores a play by looking up the tags of the magic
being cast and the tags of the enemy objects on the field, then reading
`tag_counter_rules`. When an object has no tags the lookup returns nothing and the
evaluator returns the neutral score `0.0`.

Nothing fails. No error is logged. The object is simply invisible to every bot's counter
reasoning, in every environment, forever. That is why the rule is enforced on the pull
request instead of relying on a runtime check: there is no runtime symptom to notice.

## Workflow

1. Read `README.md` for the migration rules and the ownership boundaries.
2. Find the highest migration version on `main`, not in your working copy:

   ```bash
   git ls-tree --name-only origin/main migration/ | sort | tail -1
   ```

3. Copy the structure of a nearby registration migration, for example
   `migration/V041_20260809__register_lightning_cloud.sql`. Keep every insert guarded with
   `WHERE NOT EXISTS`, because a data migration must be safe on a database where the rows
   already exist (rule 3).
4. Register the object itself: `game_objects`, its `parameters` and `parameter_values`, and
   the `magics` / `magic_cards` recipe when the object is castable.
5. **Tag the object.** Insert into `game_object_tags` for every axis that applies:
   - `TYPE_Unit` — always, for anything that stands on the field.
   - Size: `CAT_Small`, `CAT_Medium`, `CAT_Large`.
   - Role: `CAT_Melee`, `CAT_Ranged`, `CAT_Building`, `CAT_Tank`, `CAT_AoE`, `CAT_CC`.

   Check the existing vocabulary before inventing a tag:

   ```bash
   grep -rn "INSERT INTO tags" migration/
   ```

   Do not add an element tag. Elements are owned by `ElementalChart` on the game server and
   mirrored by the client's magic book; a copy here would be a second source of truth for
   one rule and would fall behind the next balance pass.
6. **Populate `magic_tags`** when the migration registers a magic. Call the derivation
   function at the end rather than writing tag rows by hand:

   ```sql
   SELECT sync_magic_tags_from_game_objects();
   ```

   It copies each magic's tags from the game object that shares its name, so the two never
   disagree. Write rows by hand only when a magic needs a tag its object does not have, and
   say why in a comment.

   **If the magic is not named after the object it creates, add an alias first.** A swarm
   magic that spawns the singular object, or any magic whose name differs from its game
   object, gets nothing from the name join and fails as silently as an untagged object.
   Twenty magics were in that state until `V065`:

   ```sql
   INSERT INTO magic_game_object_aliases(magic_name, game_object_name, reason)
   VALUES ('ember_spirit_swarm', 'ember_spirit', 'EmberSpiritSwarmMagic spawns PrefabType.EmberSpirit');
   ```

   Write the magic class and the `PrefabType` it constructs into `reason`, so the mapping
   can be rechecked against the game server without rereading the migration. With the alias
   in place the magic follows its object's tags from then on.
7. Close the migration with a `DO $$ ... RAISE EXCEPTION` block that asserts what the file
   was supposed to create, following the pattern in
   `migration/V030_20260712__seed_concept_bots.sql`.
8. Run the static checks:

   ```bash
   scripts/ci/validate-migrations.sh
   ```

## Exceptions

A magic that leaves nothing on the field — a pure buff, a one-shot effect with no object —
has no tags to add. Declare it at the top of the file so the gap is a decision rather than
an omission:

```sql
-- no-tags: rallying_torch applies a timed buff and creates no lasting object
```

`validate-migrations.sh` accepts the migration when that comment is present and rejects it
otherwise. Never add the comment to silence the check on an object that does belong on the
field.

## Related

- `README.md` — migration rules, ownership, and the counter tag contract
- `.agents/docs/workflow.md` — issue-first, branch naming, and stacked pull requests
