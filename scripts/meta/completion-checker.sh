#!/bin/bash
# completion-checker.sh — Polyagent template pre-commit verification.
#
# Single-project template version. Delegates to verify-template.sh for
# the heavy template integrity checks, then writes the per-branch marker
# that pre-commit-gate.sh reads to allow git commit.
#
# For the multi-project ROOT version (which iterates products/* and
# performs cross-repo checks), see the consuming workspace's own
# scripts/meta/completion-checker.sh.
set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}}"
VERIFY="$PROJECT_DIR/.devcontainer/verify-template.sh"

tracked_worktree_hash() {
    root=$1
    (
        cd "$root"
        git ls-files -z |
            LC_ALL=C sort -z |
            while IFS= read -r -d '' rel; do
                [ -n "$rel" ] || continue
                if [ ! -e "$rel" ] && [ ! -L "$rel" ]; then
                    printf '%s\0missing\0' "$rel"
                elif [ -L "$rel" ]; then
                    printf '%s\0symlink\0' "$rel"
                    readlink -z -- "$rel"
                elif [ -f "$rel" ]; then
                    printf '%s\0file\0' "$rel"
                    sha256sum < "$rel" | cut -d ' ' -f 1 | tr '\n' '\0'
                else
                    printf '%s\0other\0' "$rel"
                fi
            done
    ) | sha256sum | cut -d ' ' -f 1
}

if [ ! -x "$VERIFY" ] && [ ! -f "$VERIFY" ]; then
    echo "ERROR: $VERIFY not found." >&2
    echo "Polyagent template completion-checker requires .devcontainer/verify-template.sh." >&2
    exit 2
fi

RC=0
PROJECT_DIR="$PROJECT_DIR" bash "$VERIFY" || RC=$?

# Marker write follows the active vendor's pre-commit gate.
if [ "$RC" -eq 0 ]; then
    BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
        STATE_DIR="$PROJECT_DIR/.claude"
        MARKER="$STATE_DIR/.last-verification.$BRANCH_SAFE"
    elif [ -n "${CODEX_PROJECT_DIR:-}" ] || [ "${CODEX_CI:-}" = "1" ] || [ -n "${CODEX_THREAD_ID:-}" ] || [ "${AGENT_VENDOR:-}" = "codex" ]; then
        STATE_DIR="$PROJECT_DIR/.codex/state"
        MARKER="$STATE_DIR/last-verification.$BRANCH_SAFE"
    else
        STATE_DIR="$PROJECT_DIR/.claude"
        MARKER="$STATE_DIR/.last-verification.$BRANCH_SAFE"
    fi
    mkdir -p "$STATE_DIR"
    STAGED_TREE=$(git -C "$PROJECT_DIR" write-tree)
    TRACKED_WORKTREE=$(tracked_worktree_hash "$PROJECT_DIR")
    HEAD_OID=$(git -C "$PROJECT_DIR" rev-parse --verify HEAD 2>/dev/null || echo "unborn")
    TIMESTAMP_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    {
        echo "checker=polyagent-devcontainer completion-checker v1"
        echo "branch=$BRANCH"
        echo "head=$HEAD_OID"
        echo "staged_tree=$STAGED_TREE"
        echo "tracked_worktree=$TRACKED_WORKTREE"
        echo "timestamp_utc=$TIMESTAMP_UTC"
    } > "$MARKER"
fi

exit $RC
