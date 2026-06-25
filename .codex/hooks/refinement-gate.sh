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

if awk "BEGIN{exit !($BEST_SCORE >= $THRESHOLD)}" 2>/dev/null; then
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
