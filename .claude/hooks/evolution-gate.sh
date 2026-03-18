#!/bin/bash
# Stop hook: Suggest agent evolution when meaningful work was done.
# Checks .last-verification (work done) vs .last-evolution (evolution done).
#
# Logic:
#   - If no verification marker → no work done → allow stop
#   - If verification exists but evolution is newer → already evolved → allow stop
#   - If verification exists and no evolution (or stale) → block + suggest
#   - Respects stop_hook_active to prevent infinite loops
#
# Marker files:
#   .claude/.last-verification — set by mark-verified.sh after pre-commit checks
#   .claude/.last-evolution    — set by mark-evolved.sh after agent-evolver runs

INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# Prevent infinite loop: if we already blocked once, allow stop
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
VERIFY_MARKER="$PROJECT_DIR/.claude/.last-verification"
EVOLVE_MARKER="$PROJECT_DIR/.claude/.last-evolution"

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
jq -n '{
  decision: "block",
  reason: "Meaningful work completed but evolution not performed.\nDelegate to agent-evolver (team: quality) or run .claude/hooks/mark-evolved.sh to skip."
}'
