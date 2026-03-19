#!/bin/bash
# Utility: Create evolution timestamp marker.
# Called after agent-evolver completes (or when evolution is skipped).
#
# Usage: .claude/hooks/mark-evolved.sh
# Creates .last-evolution marker that evolution-gate.sh checks.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Resolve actual project root (worktree -> original repo root)
if command -v git &>/dev/null; then
  GIT_COMMON=$(git -C "$PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
    ACTUAL_ROOT=$(dirname "$GIT_COMMON")
  else
    ACTUAL_ROOT="$PROJECT_DIR"
  fi
else
  ACTUAL_ROOT="$PROJECT_DIR"
fi

# resolve branch name for per-worktree marker isolation
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

MARKER="$ACTUAL_ROOT/.claude/.last-evolution.$BRANCH_SAFE"

touch "$MARKER"
echo "Evolution marker created at $(date) (branch: $BRANCH). Agent evolution recorded."
