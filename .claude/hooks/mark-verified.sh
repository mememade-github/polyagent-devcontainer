#!/bin/bash
# Utility: Create verification timestamp marker.
# Called after pre-commit verification passes (ruff, mypy, pnpm build, etc.)
#
# Usage: .claude/hooks/mark-verified.sh
# Creates .last-verification marker that pre-commit-gate.sh checks.

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

MARKER="$ACTUAL_ROOT/.claude/.last-verification.$BRANCH_SAFE"

touch "$MARKER"
echo "Verification marker created at $(date) (branch: $BRANCH). Commits allowed for 10 minutes."
