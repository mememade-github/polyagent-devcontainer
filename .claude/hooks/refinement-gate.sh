#!/bin/bash
# refinement-gate.sh — Stop hook: prevent stopping during active refinement
# Pattern: JSON decision, 120s loop prevention, worktree-safe
#
# When .refinement-active marker exists and score < threshold:
#   → JSON {decision:"block"} to continue refinement loop
# When no marker or score >= threshold:
#   → exit 0 (allow stop)

INPUT=$(cat)

# --- Resolve project dir ---
# Refinement markers are per-session (per-worktree), so use PROJECT_DIR directly.
# Unlike verification markers (shared via ACTUAL_ROOT in pre-commit-gate.sh),
# .refinement-active and attempts are created by /refine relative to PROJECT_DIR.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

# --- Loop prevention: if already blocked once recently, allow stop ---
BLOCK_MARKER="$PROJECT_DIR/.claude/.stop-blocked-refinement.$BRANCH_SAFE"
if [ -f "$BLOCK_MARKER" ]; then
  BLOCK_MTIME=$(stat -c %Y "$BLOCK_MARKER" 2>/dev/null) || {
    rm -f "$BLOCK_MARKER"
    BLOCK_MTIME=0
  }
  MARKER_AGE=$(( $(date +%s) - BLOCK_MTIME ))
  if [ "$MARKER_AGE" -lt 120 ]; then
    rm -f "$BLOCK_MARKER"
    exit 0
  fi
  rm -f "$BLOCK_MARKER"
fi

# --- Check refinement marker ---
REFINE_MARKER="$PROJECT_DIR/.claude/.refinement-active"

# Symlink rejection (security)
if [ -L "$REFINE_MARKER" ]; then
  rm -f "$REFINE_MARKER"
  exit 0
fi

# No marker → allow stop
if [ ! -f "$REFINE_MARKER" ]; then
  exit 0
fi

# --- Read marker data ---
TASK_ID=$(jq -r '.task_id // ""' "$REFINE_MARKER" 2>/dev/null || echo "")
THRESHOLD=$(jq -r '.threshold // "0.85"' "$REFINE_MARKER" 2>/dev/null || echo "0.85")
MAX_ITER=$(jq -r '.max_iterations // "5"' "$REFINE_MARKER" 2>/dev/null || echo "5")

if [ -z "$TASK_ID" ]; then
  # Invalid marker — clean up and allow stop
  rm -f "$REFINE_MARKER"
  exit 0
fi

# --- Check current state (inline JSONL — no external scripts) ---
ATTEMPTS_FILE="$PROJECT_DIR/.claude/agent-memory/refinement/attempts/${TASK_ID}.jsonl"
if [ ! -f "$ATTEMPTS_FILE" ]; then
  # No attempts recorded → allow stop
  exit 0
fi

BEST_SCORE=$(jq -s 'sort_by(.score) | last | .score // 0' "$ATTEMPTS_FILE" 2>/dev/null || echo "0")
ITERATION=$(wc -l < "$ATTEMPTS_FILE" 2>/dev/null || echo "0")

# --- Termination check (no bc, awk only) ---
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

# Iteration >= max → allow stop
if [ "$ITERATION" -ge "$MAX_ITER" ]; then
  exit 0
fi

# --- Block: refinement not complete ---
touch "$BLOCK_MARKER"
jq -n \
  --arg task "$TASK_ID" \
  --arg score "$BEST_SCORE" \
  --arg thresh "$THRESHOLD" \
  --arg iter "$ITERATION" \
  --arg max "$MAX_ITER" \
  '{
    decision: "block",
    reason: ("Refinement loop active: task=" + $task + " score=" + $score + "/" + $thresh + " iteration=" + $iter + "/" + $max + ". Continue refinement or remove .claude/.refinement-active to force stop.")
  }'

exit 0
