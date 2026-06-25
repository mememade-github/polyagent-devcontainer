#!/bin/bash
# =============================================================================
# sync-agents-mirror.sh — one-way generated mirror of .claude/ into .agents/
# =============================================================================
# `.claude/` is ground truth; `.agents/` is a generated mirror — do not edit by
# hand. The mirror is EXACT: source additions/edits are copied, and entries
# whose source was deleted are pruned (deletion propagation — §3). Vendor-coupled
# text (paths, env vars, isolation claims) must be made vendor-neutral AT THE
# SOURCE in .claude/ — the sync copies verbatim and does NOT translate; a
# post-sync coupling guard (§4) warns if a Codex-breaking `$CLAUDE_PROJECT_DIR`
# (used outside a `${CLAUDE_PROJECT_DIR:-...}` fallback) reaches the mirror.
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
[ "${1:-}" = "--dry" ] && DRY_RUN=1

if [ ! -d "$SRC" ]; then
    echo "ERROR: $SRC not found. .claude/ ground truth required." >&2
    exit 1
fi
mkdir -p "$DST"

CHANGED=0

# --- 1. Overlay rules + skills (content copy) ---
for SUB in rules skills; do
    SRC_SUB="$SRC/$SUB"; DST_SUB="$DST/$SUB"
    [ -d "$SRC_SUB" ] || continue
    if [ "$DRY_RUN" -eq 1 ]; then
        if [ ! -d "$DST_SUB" ]; then
            echo "[DRY] would create: $SUB/"; CHANGED=$((CHANGED + 1))
        else
            DIFF=$(diff -rq "$SRC_SUB" "$DST_SUB" 2>/dev/null | grep -v "^Only in $DST_SUB" | wc -l)
            [ "$DIFF" -gt 0 ] && echo "[DRY] would update: $SUB/ ($DIFF item(s))" && CHANGED=$((CHANGED + 1))
        fi
    else
        # 9p/WSL2 rejects attribute preserve — plain -R (content only; git tracks mode).
        mkdir -p "$DST_SUB"
        cp -R "$SRC_SUB"/. "$DST_SUB"/
        echo "[SYNC] $SUB/"
        CHANGED=$((CHANGED + 1))
    fi
done

# --- 2. agents/<X>.md → skills/<X>/SKILL.md conversion ---
if [ -d "$SRC/agents" ]; then
    for AGENT in "$SRC/agents"/*.md; do
        [ -f "$AGENT" ] || continue
        NAME=$(basename "$AGENT" .md)
        case "$NAME" in _*) continue ;; esac
        DST_SKILL_DIR="$DST/skills/$NAME"; DST_SKILL="$DST_SKILL_DIR/SKILL.md"
        if [ "$DRY_RUN" -eq 1 ]; then
            if [ ! -f "$DST_SKILL" ] || ! cmp -s "$AGENT" "$DST_SKILL"; then
                echo "[DRY] would convert: agents/${NAME}.md → skills/${NAME}/SKILL.md"; CHANGED=$((CHANGED + 1))
            fi
        else
            mkdir -p "$DST_SKILL_DIR"; cp "$AGENT" "$DST_SKILL"
            echo "[CONVERT] agents/${NAME}.md → skills/${NAME}/SKILL.md"; CHANGED=$((CHANGED + 1))
        fi
    done
fi

# --- 3. Deletion propagation (orphan prune) ---
# A .agents/rules/<f> is legitimate iff .claude/rules/<f> exists.
# A .agents/skills/<X> is legitimate iff .claude/skills/<X>/ OR .claude/agents/<X>.md
# exists (dual source — the agent→skill conversions have no .claude/skills/ peer).
# Anything else is an orphan from a deleted source and is pruned: this is what
# makes the mirror track deletions, not just additions.
prune() {  # $1=path  $2=label
    if [ "$DRY_RUN" -eq 1 ]; then echo "[DRY] would prune: $2 (source gone)"
    else echo "[PRUNE] $2 (source gone)"; rm -rf "$1"; fi
    CHANGED=$((CHANGED + 1))
}
if [ -d "$DST/rules" ]; then
    for f in "$DST/rules"/*; do
        [ -e "$f" ] || continue
        [ -e "$SRC/rules/$(basename "$f")" ] || prune "$f" "rules/$(basename "$f")"
    done
fi
if [ -d "$DST/skills" ]; then
    for d in "$DST/skills"/*/; do
        [ -d "$d" ] || continue
        B=$(basename "$d")
        if [ ! -d "$SRC/skills/$B" ] && [ ! -f "$SRC/agents/$B.md" ]; then
            prune "${d%/}" "skills/$B"
        fi
    done
fi

# --- 4. Coupling guard (post-sync, non-fatal) ---
# A bare $CLAUDE_PROJECT_DIR in a mirror is unset under Codex → runtime break.
# Match only real shell expansions: $CLAUDE_PROJECT_DIR followed by a path/quote,
# or ${CLAUDE_PROJECT_DIR} without a :- fallback. Prose mentions in backticks and
# ${CLAUDE_PROJECT_DIR:-...} fallbacks are correctly skipped (no cry-wolf).
if [ "$DRY_RUN" -eq 0 ]; then
    LEAKS=$(grep -rnE '\$CLAUDE_PROJECT_DIR["/]|\$\{CLAUDE_PROJECT_DIR\}' "$DST" 2>/dev/null || true)
    if [ -n "$LEAKS" ]; then
        echo "[WARN] coupling guard: bare \$CLAUDE_PROJECT_DIR expansion in mirror (breaks under Codex):" >&2
        echo "$LEAKS" >&2
    fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""; echo "Dry run complete. $CHANGED change(s) detected."
else
    echo ""; echo "Sync complete. $CHANGED change(s) applied."
    echo "Note: .agents/ is a generated mirror. Edit .claude/ as ground truth."
fi
