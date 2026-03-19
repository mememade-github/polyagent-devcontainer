#!/bin/bash
# Stop hook: Prevent Claude from stopping when code review is pending
# Checks .pending-review marker — if files are pending review, blocks Stop.
#
# Safety: file-based loop prevention (if already blocked once, allow stop).
# The marker is cleared by review-complete.sh after code-reviewer finishes.

INPUT=$(cat)

# Resolve actual project root (worktree -> original repo root)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
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

# File-based loop prevention: if we already blocked once recently, allow stop
BLOCK_MARKER="$ACTUAL_ROOT/.claude/.stop-blocked-review.$BRANCH_SAFE"
if [ -f "$BLOCK_MARKER" ]; then
  MARKER_AGE=$(( $(date +%s) - $(stat -c %Y "$BLOCK_MARKER" 2>/dev/null || echo 0) ))
  if [ "$MARKER_AGE" -lt 120 ]; then
    rm -f "$BLOCK_MARKER"
    exit 0
  fi
  rm -f "$BLOCK_MARKER"
fi

MARKER="$ACTUAL_ROOT/.claude/.pending-review.$BRANCH_SAFE"

if [ ! -f "$MARKER" ]; then
  exit 0
fi

FILE_COUNT=$(wc -l < "$MARKER")
FILES=$(cat "$MARKER" | head -5 | tr '\n' ', ')

if [ "$FILE_COUNT" -gt 0 ]; then
  # Record that we blocked, so next invocation allows stop
  touch "$BLOCK_MARKER"
  jq -n --arg count "$FILE_COUNT" --arg files "$FILES" --arg projdir "$PROJECT_DIR" '{
    decision: "block",
    reason: ($count + " file(s) in products/ were modified but not reviewed: " + $files + "\nPer CLAUDE.md §2: delegate to code-reviewer agent (team: quality) before finishing. After review completes, run: bash \"" + $projdir + "/.claude/hooks/review-complete.sh\" to clear.")
  }'
fi
