#!/bin/bash
# =============================================================================
# sync-agents-mirror.sh — one-way mirror of .claude/ into .agents/
# =============================================================================
# Mirrors Claude Code assets (`.claude/`) into Codex-compatible form (`.agents/`).
# `.claude/` is the ground truth; `.agents/` is generated — do not edit by hand.
#
# Usage:
#   bash scripts/sync-agents-mirror.sh         # update mirror
#   bash scripts/sync-agents-mirror.sh --dry   # show pending changes only
#
# Mapping:
#   .claude/rules/        → .agents/rules/        (directory copy)
#   .claude/skills/       → .agents/skills/       (directory copy)
#   .claude/security/     → .agents/security/     (directory copy)
#   .claude/agents/<X>.md → .agents/skills/<X>/SKILL.md  (file → skill directory)
#
# Excluded from sync:
#   .claude/hooks/         — Codex uses .codex/hooks/ separately
#   .claude/settings.json  — Claude-only
#
# Known vendor losses (frontmatter fields Codex CLI does not honor):
#   tools / model / color — silently ignored; body is preserved verbatim.
#
# Preserve-extras policy:
#   Consumers may add files under .agents/ that have no source counterpart
#   (project-local extensions, additional skills). `cp -a` overlay updates
#   ground-truth files but leaves dest-only files in place, preventing loss.
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
for SUB in rules skills security; do
    SRC_SUB="$SRC/$SUB"
    DST_SUB="$DST/$SUB"
    [ -d "$SRC_SUB" ] || continue

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ ! -d "$DST_SUB" ]; then
            echo "[DRY] would create: $SUB/"
            CHANGED=$((CHANGED + 1))
        else
            # Source-side files differing from dest (preserve-extras: ignore dest-only)
            DIFF=$(diff -rq "$SRC_SUB" "$DST_SUB" 2>/dev/null | grep -v "^Only in $DST_SUB" | wc -l)
            [ "$DIFF" -gt 0 ] && echo "[DRY] would update: $SUB/ ($DIFF item(s))" && CHANGED=$((CHANGED + 1))
        fi
    else
        # Preserve-extras: overlay source onto dest. dest-only files retained.
        # 9p/WSL2 bind mount rejects utime()/permission preservation (Operation not
        # permitted) — so plain -R (no attribute preserve). Mirror parity needs CONTENT
        # only; git tracks mode separately (AUD-2026: 9p sync fix). Overlay keeps extras.
        mkdir -p "$DST_SUB"
        cp -R "$SRC_SUB"/. "$DST_SUB"/
        echo "[SYNC] $SUB/ (preserve-extras)"
        CHANGED=$((CHANGED + 1))
    fi
done

# agents → skills 변환 (단일 파일 → 스킬 디렉토리)
if [ -d "$SRC/agents" ]; then
    for AGENT in "$SRC/agents"/*.md; do
        [ -f "$AGENT" ] || continue
        NAME=$(basename "$AGENT" .md)
        # 메타/스키마 파일 제외
        case "$NAME" in _*) continue ;; esac
        DST_SKILL_DIR="$DST/skills/$NAME"
        DST_SKILL="$DST_SKILL_DIR/SKILL.md"
        if [ "$DRY_RUN" -eq 1 ]; then
            if [ ! -f "$DST_SKILL" ] || ! cmp -s "$AGENT" "$DST_SKILL"; then
                echo "[DRY] would convert: agents/${NAME}.md → skills/${NAME}/SKILL.md"
                CHANGED=$((CHANGED + 1))
            fi
        else
            mkdir -p "$DST_SKILL_DIR"
            cp "$AGENT" "$DST_SKILL"
            echo "[CONVERT] agents/${NAME}.md → skills/${NAME}/SKILL.md"
            CHANGED=$((CHANGED + 1))
        fi
    done
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "Dry run complete. $CHANGED change(s) detected."
else
    echo ""
    echo "Sync complete. $CHANGED change(s) applied."
    echo "Note: .agents/ is a generated mirror. Edit .claude/ as ground truth."
fi
