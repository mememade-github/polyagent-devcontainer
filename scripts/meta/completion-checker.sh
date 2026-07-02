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
    touch "$MARKER"
fi

exit $RC
