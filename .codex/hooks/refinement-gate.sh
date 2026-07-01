#!/bin/bash
# Stop hook: prevent stopping during an active Codex refine loop

set -u

PROJECT_DIR="${CODEX_PROJECT_DIR:-.}"
STATE_DIR="$PROJECT_DIR/.codex/state"
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

BLOCK_MARKER="$STATE_DIR/stop-blocked-refinement.$BRANCH_SAFE"
if [ -f "$BLOCK_MARKER" ]; then
  BLOCK_MTIME=$(stat -c %Y "$BLOCK_MARKER" 2>/dev/null || echo 0)
  MARKER_AGE=$(( $(date +%s) - BLOCK_MTIME ))
  rm -f "$BLOCK_MARKER"
  if [ "$MARKER_AGE" -lt 120 ]; then
    exit 0
  fi
fi

REFINE_MARKER="$STATE_DIR/refinement-active"
[ -f "$REFINE_MARKER" ] || exit 0
[ -L "$REFINE_MARKER" ] && rm -f "$REFINE_MARKER" && exit 0
mkdir -p "$STATE_DIR/refinement/attempts"

TASK_ID=$(jq -r '.task_id // ""' "$REFINE_MARKER" 2>/dev/null || echo "")
THRESHOLD=$(jq -r '.threshold // "0.85"' "$REFINE_MARKER" 2>/dev/null || echo "0.85")
MAX_ITER=$(jq -r '.max_iterations // "5"' "$REFINE_MARKER" 2>/dev/null || echo "5")
[ -z "$TASK_ID" ] && rm -f "$REFINE_MARKER" && exit 0

ATTEMPTS_FILE="$STATE_DIR/refinement/attempts/${TASK_ID}.jsonl"
[ -f "$ATTEMPTS_FILE" ] || exit 0

BEST_SCORE=$(jq -s 'sort_by(.score) | last | .score // 0' "$ATTEMPTS_FILE" 2>/dev/null || echo "0")
ITERATION=$(wc -l < "$ATTEMPTS_FILE" 2>/dev/null || echo "0")

# M1: score/threshold/max-iteration all come from a gitignored, agent-writable
# state file. Numeric-validate each before use, and pass the awk operands as
# DATA vars (-v) rather than interpolating them into the program text -- string
# interpolation here was a code-injection vector in this auto-running Stop hook.
# MAX_ITER (used in the [ -ge ] test below) is inert today but validated for
# uniformity so a later refactor can't reopen it.
is_decimal() { printf '%s\n' "$1" | grep -Eq '^[0-9]+([.][0-9]+)?$'; }
is_integer() { printf '%s\n' "$1" | grep -Eq '^[0-9]+$'; }
is_decimal "$BEST_SCORE" || BEST_SCORE=0
is_decimal "$THRESHOLD" || THRESHOLD=0.85
is_integer "$MAX_ITER" || MAX_ITER=5
if awk -v s="$BEST_SCORE" -v t="$THRESHOLD" 'BEGIN{exit !(s >= t)}' 2>/dev/null; then
  exit 0
fi

if [ "$ITERATION" -ge "$MAX_ITER" ]; then
  exit 0
fi

touch "$BLOCK_MARKER"
jq -n \
  --arg task "$TASK_ID" \
  --arg score "$BEST_SCORE" \
  --arg thresh "$THRESHOLD" \
  --arg iter "$ITERATION" \
  --arg max "$MAX_ITER" \
  '{
    decision: "block",
    reason: ("Refinement loop active: task=" + $task + " score=" + $score + "/" + $thresh + " iteration=" + $iter + "/" + $max + ". Continue refinement or remove .codex/state/refinement-active to force stop.")
  }'

exit 0
