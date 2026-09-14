#!/usr/bin/env bash
#
# Static checks over migration/ that do not need a database.
#
# Flyway only reports these problems at apply time, which for this repository means after
# a merge to main has already pushed the change at the dev database. Everything here is
# decidable from the files alone, so it runs on the pull request instead.
#
# Usage: scripts/ci/validate-migrations.sh [base-ref]
#   base-ref defaults to origin/main. Checks that compare against already-published
#   migrations are skipped when the ref is not available (e.g. a shallow clone).

set -euo pipefail

MIGRATION_DIR="migration"
BASE_REF="${1:-origin/main}"
NAME_PATTERN='^V([0-9]{3})_([0-9]{8})__[a-z0-9]+(_[a-z0-9]+)*\.sql$'

failures=0

fail() {
    printf 'FAIL  %s\n' "$1" >&2
    failures=$((failures + 1))
}

pass() {
    printf 'ok    %s\n' "$1"
}

if [ ! -d "$MIGRATION_DIR" ]; then
    fail "$MIGRATION_DIR/ not found - run this from the repository root"
    exit 1
fi

mapfile -t migrations < <(find "$MIGRATION_DIR" -maxdepth 1 -name '*.sql' -printf '%f\n' | sort)

if [ "${#migrations[@]}" -eq 0 ]; then
    fail "no migrations found in $MIGRATION_DIR/"
    exit 1
fi

# ---------------------------------------------------------------- naming
# Flyway derives the version from the filename. A name it cannot parse is silently not a
# migration, so a typo means the file never runs rather than failing loudly.

for file in "${migrations[@]}"; do
    if ! [[ "$file" =~ $NAME_PATTERN ]]; then
        fail "$file does not match V<NNN>_<YYYYMMDD>__<snake_case>.sql"
    fi
done
[ "$failures" -eq 0 ] && pass "all ${#migrations[@]} filenames match the naming rule"

# ------------------------------------------------------------ duplicates
# Two files claiming one version make Flyway refuse to run at all - including migrations
# unrelated to the change that introduced the clash.

duplicates=$(printf '%s\n' "${migrations[@]}" | sed -n 's/^V\([0-9]\{3\}\)_.*/\1/p' | sort | uniq -d)
if [ -n "$duplicates" ]; then
    while read -r version; do
        [ -z "$version" ] && continue
        fail "version V$version is claimed by more than one file:"
        printf '%s\n' "${migrations[@]}" | grep "^V${version}_" | sed 's/^/        /' >&2
    done <<< "$duplicates"
else
    pass "no duplicate version numbers"
fi

# -------------------------------------------------- comparisons vs base
# Everything below needs the published history to compare against.

if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
    printf 'skip  %s is not available - skipping ordering and immutability checks\n' "$BASE_REF"
    [ "$failures" -eq 0 ] && exit 0 || exit 1
fi

mapfile -t base_migrations < <(git ls-tree -r --name-only "$BASE_REF" -- "$MIGRATION_DIR" | sed "s|^$MIGRATION_DIR/||" | grep '\.sql$' | sort || true)

highest_base_version=$(printf '%s\n' "${base_migrations[@]}" | sed -n 's/^V\([0-9]\{3\}\)_.*/\1/p' | sort -n | tail -1)

# A version claimed by two files on the base branch is one Flyway can never apply: it
# refuses to run anything while the clash stands, so neither file reaches a database.
# Removing one of them is the only repair, and the immutability check below must not
# report that as a rule 1 violation. Rule 1 protects migrations a database has run.
base_duplicates=$(printf '%s\n' "${base_migrations[@]}" | sed -n 's/^V\([0-9]\{3\}\)_.*/\1/p' | sort | uniq -d)

# ------------------------------------------------------------- ordering
# Flyway applies versions in order. A new migration numbered below what the target
# database has already reached is an out-of-order migration: it is skipped on databases
# that are ahead and applied on ones that are behind, so environments silently diverge.

if [ -n "$highest_base_version" ]; then
    out_of_order=0
    for file in "${migrations[@]}"; do
        if printf '%s\n' "${base_migrations[@]}" | grep -qx "$file"; then
            continue
        fi
        version=$(printf '%s' "$file" | sed -n 's/^V\([0-9]\{3\}\)_.*/\1/p')
        [ -z "$version" ] && continue
        if [ "$((10#$version))" -le "$((10#$highest_base_version))" ]; then
            fail "$file is numbered at or below V$highest_base_version, the highest on $BASE_REF - use V$(printf '%03d' $((10#$highest_base_version + 1))) or later"
            out_of_order=1
        fi
    done
    [ "$out_of_order" -eq 0 ] && pass "new migrations are numbered above V$highest_base_version"
fi

# ---------------------------------------------------------- immutability
# Migration rule 1: never edit an applied migration. Flyway stores a checksum, so an edit
# makes `validate` fail on every database that already ran the file, and the change never
# reaches the ones that did.
#
# A migration that failed is the exception. PostgreSQL runs each migration in a transaction,
# so a failure rolls the flyway_schema_history row back with the changes: no database holds a
# checksum for that file, every database stops at the version below it, and a forward-fix
# migration placed after it never runs. Editing the failed file is the only repair. The edit
# declares itself by adding a `-- never-applied: <reason>` line in the same change, so the
# claim is written down next to the SQL and reviewed with it. A line already present on the
# base branch does not count, which keeps the exception to the one pull request that repairs
# the file. The `dev database checksums` job is the backstop: `flyway validate` ignores a
# pending migration but not an applied one, so a wrong claim fails there against the record
# of what the dev database actually ran.

changed=0
for file in "${base_migrations[@]}"; do
    [ -z "$file" ] && continue
    if [ ! -f "$MIGRATION_DIR/$file" ]; then
        version=$(printf '%s' "$file" | sed -n 's/^V\([0-9]\{3\}\)_.*/\1/p')
        if [ -n "$version" ] && printf '%s\n' "$base_duplicates" | grep -qx "$version"; then
            pass "$file was removed - V$version is claimed twice on $BASE_REF, so no database ran it"
            continue
        fi
        fail "$file was deleted - published migrations must stay (rule 1); use a forward-fix migration"
        changed=1
        continue
    fi
    if ! git diff --quiet "$BASE_REF" -- "$MIGRATION_DIR/$file"; then
        if git diff "$BASE_REF" -- "$MIGRATION_DIR/$file" | grep -qiE '^\+[[:space:]]*--[[:space:]]*never-applied:'; then
            pass "$file was modified and declares a never-applied reason - no database holds its checksum"
            continue
        fi
        fail "$file was modified - published migrations are immutable (rule 1); use a forward-fix migration, or declare '-- never-applied: <reason>' if the migration failed and no database ran it"
        changed=1
    fi
done
[ "$changed" -eq 0 ] && pass "no published migration was modified or deleted"

# ---------------------------------------------------------- tag coverage
# Bot counter scoring reads game_object_tags and magic_tags. A missing tag is not an error
# at runtime: BotCounterEvaluator returns the neutral score 0.0, so a unit registered
# without tags is simply never scored and nothing reports it. That failure is invisible in
# every environment, which makes the pull request the only place it can be caught.
#
# A registration that genuinely has no tags to add declares why, so the exception is
# written down instead of being indistinguishable from an omission.

tag_gaps=0
for file in "${migrations[@]}"; do
    if printf '%s\n' "${base_migrations[@]}" | grep -qx "$file"; then
        continue
    fi
    path="$MIGRATION_DIR/$file"
    [ -f "$path" ] || continue

    if grep -qi 'no-tags:' "$path"; then
        pass "$file declares a no-tags exception"
        continue
    fi

    if grep -qiE 'insert[[:space:]]+into[[:space:]]+game_objects\b' "$path" \
        && ! grep -qiE 'insert[[:space:]]+into[[:space:]]+game_object_tags\b' "$path"; then
        fail "$file registers a game object but adds no game_object_tags - the bot would never score it; add tags or a '-- no-tags: <reason>' comment"
        tag_gaps=$((tag_gaps + 1))
    fi

    if grep -qiE 'insert[[:space:]]+into[[:space:]]+magics\b' "$path" \
        && ! grep -qiE 'insert[[:space:]]+into[[:space:]]+magic_tags\b|sync_magic_tags_from_game_objects' "$path"; then
        fail "$file registers a magic but does not populate magic_tags - call sync_magic_tags_from_game_objects() at the end, or add a '-- no-tags: <reason>' comment"
        tag_gaps=$((tag_gaps + 1))
    fi
done
[ "$tag_gaps" -eq 0 ] && pass "new registrations carry counter tags"

# ----------------------------------------------------------------------

if [ "$failures" -gt 0 ]; then
    printf '\n%d check(s) failed\n' "$failures" >&2
    exit 1
fi

printf '\nall checks passed\n'
