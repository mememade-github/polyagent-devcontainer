#!/bin/bash
# Utility: Clear pending-review marker after code review is complete.
# Called by the AI after code-reviewer agent finishes its review.
#
# Usage: .claude/hooks/review-complete.sh

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

# clear pending review marker (branch-specific)
rm -f "$ACTUAL_ROOT/.claude/.pending-review.$BRANCH_SAFE"

echo "Code review marker cleared (branch: $BRANCH). Commits are now unblocked (pending verification)."
