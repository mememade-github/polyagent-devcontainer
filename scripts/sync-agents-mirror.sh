#!/bin/bash
# =============================================================================
# sync-agents-mirror.sh — one-way generated mirror of .claude/ into .agents/
# =============================================================================
# `.claude/` is ground truth; `.agents/` is an exact generated mirror — do not
# edit by hand. Source additions/edits are copied and destination-only entries
# are pruned recursively. Vendor-coupled text must be made vendor-neutral at the
# source; the sync copies verbatim and rejects bare `$CLAUDE_PROJECT_DIR`
# expansions that would break under Codex.
#
# Usage:
#   bash scripts/sync-agents-mirror.sh         # update mirror
#   bash scripts/sync-agents-mirror.sh --dry   # show pending changes only
#
# Mapping:
#   .claude/rules/        → .agents/rules/        (directory copy)
#   .claude/skills/       → .agents/skills/       (directory copy)
#   .claude/agents/<X>.md → .agents/skills/<X>/SKILL.md  (file → skill directory)
#
# Excluded: .claude/hooks/ (Codex uses .codex/hooks/), .claude/settings.json.
# Vendor losses: frontmatter tools/model/color — Codex ignores; body preserved.
# =============================================================================
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PROJECT_ROOT/.claude"
DST="$PROJECT_ROOT/.agents"
DRY_RUN=0
if [ "$#" -gt 1 ]; then
    echo "Usage: bash scripts/sync-agents-mirror.sh [--dry]" >&2
    exit 2
fi
case "${1:-}" in
    "") ;;
    "--dry") DRY_RUN=1 ;;
    *)
        echo "Usage: bash scripts/sync-agents-mirror.sh [--dry]" >&2
        exit 2
        ;;
esac

if [ ! -d "$SRC" ]; then
    echo "ERROR: $SRC not found. .claude/ ground truth required." >&2
    exit 1
fi

EXPECTED_ROOT=$(mktemp -d)
trap 'rm -r "$EXPECTED_ROOT"' EXIT
EXPECTED="$EXPECTED_ROOT/.agents"
mkdir -p "$EXPECTED/rules" "$EXPECTED/skills"

SOURCE_LINK=$(find "$SRC/rules" "$SRC/skills" "$SRC/agents" -type l -print -quit 2>/dev/null || true)
DEST_LINK=$(find "$DST" -type l -print -quit 2>/dev/null || true)
if [ -n "$SOURCE_LINK" ] || [ -n "$DEST_LINK" ]; then
    echo "ERROR: generated mirror does not permit symlinks." >&2
    [ -n "$SOURCE_LINK" ] && echo "  source: $SOURCE_LINK" >&2
    [ -n "$DEST_LINK" ] && echo "  destination: $DEST_LINK" >&2
    exit 1
fi

# --- 1. Build the complete expected mirror in a temporary tree. ---
for SUB in rules skills; do
    if [ -d "$SRC/$SUB" ]; then
        chmod --reference="$SRC/$SUB" "$EXPECTED/$SUB"
        cp -R --preserve=mode "$SRC/$SUB"/. "$EXPECTED/$SUB"/
    fi
done

if [ -d "$SRC/agents" ]; then
    for AGENT in "$SRC/agents"/*.md; do
        [ -f "$AGENT" ] || continue
        NAME=$(basename "$AGENT" .md)
        case "$NAME" in _*) continue ;; esac
        mkdir -p "$EXPECTED/skills/$NAME"
        cp --preserve=mode "$AGENT" "$EXPECTED/skills/$NAME/SKILL.md"
    done
fi

# --- 2. Coupling guard (fatal and pre-mutation). ---
LEAKS=$(grep -rnE '\$CLAUDE_PROJECT_DIR([^A-Za-z0-9_`]|$)|\$\{CLAUDE_PROJECT_DIR\}' "$EXPECTED" 2>/dev/null || true)
if [ -n "$LEAKS" ]; then
    echo "ERROR: bare \$CLAUDE_PROJECT_DIR expansion in generated mirror:" >&2
    echo "$LEAKS" >&2
    exit 1
fi

# --- 3. Compare or reconcile the complete tree, including nested orphans. ---
if [ -d "$DST" ]; then
    DIFF_OUTPUT=$(diff -rq "$EXPECTED" "$DST" 2>/dev/null || true)
    MODE_DIFF=""
    while IFS=$'\t' read -r rel expected_mode; do
        [ -e "$DST/$rel" ] || continue
        actual_mode=$(stat -c '%a' "$DST/$rel" 2>/dev/null || echo missing)
        if [ "$expected_mode" != "$actual_mode" ]; then
            MODE_DIFF="${MODE_DIFF}Mode differs: $DST/$rel ($actual_mode != $expected_mode)\n"
        fi
    done < <(find "$EXPECTED" -mindepth 1 -printf '%P\t%m\n' | LC_ALL=C sort)
    if [ -n "$MODE_DIFF" ]; then
        [ -z "$DIFF_OUTPUT" ] || DIFF_OUTPUT="${DIFF_OUTPUT}"$'\n'
        DIFF_OUTPUT="${DIFF_OUTPUT}$(printf '%b' "$MODE_DIFF" | sed '/^$/d')"
    fi
else
    DIFF_OUTPUT="Destination missing: $DST"
fi
CHANGED=$(printf '%s\n' "$DIFF_OUTPUT" | sed '/^$/d' | wc -l | tr -d ' ')

if [ "$DRY_RUN" -eq 1 ]; then
    [ -n "$DIFF_OUTPUT" ] && printf '%s\n' "$DIFF_OUTPUT" | sed 's/^/[DRY] /'
else
    if [ -e "$DST" ] && [ ! -d "$DST" ]; then
        rm -f "$DST"
    fi
    mkdir -p "$DST"

    while IFS= read -r -d '' path; do
        if [ -d "$path" ]; then
            rm -r "$path"
        else
            rm -f "$path"
        fi
    done < <(find "$DST" -mindepth 1 -maxdepth 1 -print0)

    while IFS= read -r -d '' path; do
        cp -R --preserve=mode "$path" "$DST"/
    done < <(find "$EXPECTED" -mindepth 1 -maxdepth 1 -print0)
    echo "[SYNC] exact .agents/"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""; echo "Dry run complete. $CHANGED change(s) detected."
else
    echo ""; echo "Sync complete. $CHANGED change(s) applied."
    echo "Note: .agents/ is a generated mirror. Edit .claude/ as ground truth."
fi
