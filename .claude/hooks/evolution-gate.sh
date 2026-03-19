#!/bin/bash
# Stop hook: Suggest agent evolution when meaningful work was done.
# Checks .last-verification (work done) vs .last-evolution (evolution done).
#
# Logic:
#   - If no verification marker → no work done → allow stop
#   - If verification exists but evolution is newer → already evolved → allow stop
#   - If verification exists and no evolution (or stale) → block + suggest
#   - File-based loop prevention: if already blocked once, allow stop
#
# Marker files:
#   .claude/.last-verification — set by mark-verified.sh after pre-commit checks
#   .claude/.last-evolution    — set by mark-evolved.sh after agent-evolver runs

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
BLOCK_MARKER="$ACTUAL_ROOT/.claude/.stop-blocked-evolution.$BRANCH_SAFE"
if [ -f "$BLOCK_MARKER" ]; then
  MARKER_AGE=$(( $(date +%s) - $(stat -c %Y "$BLOCK_MARKER" 2>/dev/null || echo 0) ))
  if [ "$MARKER_AGE" -lt 120 ]; then
    rm -f "$BLOCK_MARKER"
    exit 0
  fi
  rm -f "$BLOCK_MARKER"
fi

VERIFY_MARKER="$ACTUAL_ROOT/.claude/.last-verification"
EVOLVE_MARKER="$ACTUAL_ROOT/.claude/.last-evolution"

# No verification → no meaningful work → skip
if [ ! -f "$VERIFY_MARKER" ]; then
  exit 0
fi

VERIFY_TIME=$(stat -c %Y "$VERIFY_MARKER" 2>/dev/null || echo 0)

# Check if evolution was done after verification
if [ -f "$EVOLVE_MARKER" ]; then
  EVOLVE_TIME=$(stat -c %Y "$EVOLVE_MARKER" 2>/dev/null || echo 0)
  if [ "$EVOLVE_TIME" -gt "$VERIFY_TIME" ]; then
    # Evolution is current → allow stop
    exit 0
  fi
fi

# Verification exists but evolution not done → block with suggestion
touch "$BLOCK_MARKER"
jq -n '{
  decision: "block",
  reason: "Meaningful work completed but evolution not performed.\nDelegate to agent-evolver (team: quality) or run .claude/hooks/mark-evolved.sh to skip."
}'
