#!/bin/bash
# refinement-gate.sh — Stop hook: keep an active /refine loop running.
# Blocks (JSON decision) once per 120s window while .refinement-active exists
# and the best recorded score is below threshold; on any missing/invalid
# state it allows the stop (fail-open). Never exits non-zero.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

# Loop prevention: if we already blocked within the last 120s, allow the stop.
BLOCK_MARKER="$PROJECT_DIR/.claude/.stop-blocked-refinement.$BRANCH_SAFE"
if [ -f "$BLOCK_MARKER" ]; then
  BLOCK_MTIME=$(stat -c %Y "$BLOCK_MARKER" 2>/dev/null || echo 0)
  rm -f "$BLOCK_MARKER"
  [ $(( $(date +%s) - BLOCK_MTIME )) -lt 120 ] && exit 0
fi

REFINE_MARKER="$PROJECT_DIR/.claude/.refinement-active"
[ -L "$REFINE_MARKER" ] && { rm -f "$REFINE_MARKER"; exit 0; }
[ -f "$REFINE_MARKER" ] || exit 0

# Marker fields: jq type checks keep untrusted values out of shell/awk code.
TASK_ID=$(jq -er '.task_id | select(type == "string" and length > 0)' "$REFINE_MARKER" 2>/dev/null) ||
  { rm -f "$REFINE_MARKER"; exit 0; }
case "$TASK_ID" in */*) rm -f "$REFINE_MARKER"; exit 0 ;; esac
THRESHOLD=$(jq -er '.threshold | select(type == "number")' "$REFINE_MARKER" 2>/dev/null) || THRESHOLD=0.85
MAX_ITER=$(jq -er '.max_iterations | select(type == "number") | floor' "$REFINE_MARKER" 2>/dev/null) || MAX_ITER=5

ATTEMPTS_FILE="$PROJECT_DIR/.claude/agent-memory/refinement/attempts/${TASK_ID}.jsonl"
[ -f "$ATTEMPTS_FILE" ] || exit 0
BEST_SCORE=$(jq -es '[.[].score | select(type == "number")] | max // 0' "$ATTEMPTS_FILE" 2>/dev/null) || exit 0
ITERATION=$(wc -l < "$ATTEMPTS_FILE" 2>/dev/null || echo 0)

# Termination: awk receives operands as -v data vars, never as program text.
awk -v s="$BEST_SCORE" -v t="$THRESHOLD" 'BEGIN{exit !(s >= t)}' 2>/dev/null && exit 0
[ "$ITERATION" -ge "$MAX_ITER" ] 2>/dev/null && exit 0

touch "$BLOCK_MARKER" 2>/dev/null || exit 0  # cannot record the block -> fail open
jq -n --arg task "$TASK_ID" --arg score "$BEST_SCORE" --arg thresh "$THRESHOLD" \
  --arg iter "$ITERATION" --arg max "$MAX_ITER" \
  '{decision: "block",
    reason: ("Refinement loop active: task=" + $task + " score=" + $score + "/" + $thresh
      + " iteration=" + $iter + "/" + $max
      + ". Continue refinement or remove .claude/.refinement-active to force stop.")}'
exit 0
