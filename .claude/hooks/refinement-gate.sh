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
if awk "BEGIN{exit !($BEST_SCORE >= $THRESHOLD)}" 2>/dev/null; then
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
