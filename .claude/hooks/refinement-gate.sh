#!/bin/bash
# refinement-gate.sh — Stop hook: prevent stopping during active refinement
# Pattern: stop-gate.sh (JSON decision, 120s loop prevention, worktree-safe)
#
# When .refinement-active marker exists and score < threshold:
#   → JSON {decision:"block"} to continue refinement loop
# When no marker or score >= threshold:
#   → exit 0 (allow stop)

INPUT=$(cat)

# --- Resolve actual project root (worktree → original repo root) ---
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

BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

# --- Loop prevention: if already blocked once recently, allow stop ---
BLOCK_MARKER="$ACTUAL_ROOT/.claude/.stop-blocked-any.$BRANCH_SAFE"
if [ -f "$BLOCK_MARKER" ]; then
  BLOCK_MTIME=$(stat -c %Y "$BLOCK_MARKER" 2>/dev/null) || {  # P-4: stat error handled by || block
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
REFINE_MARKER="$ACTUAL_ROOT/.claude/.refinement-active"

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
# Honest fallback: jq unavailable or malformed marker (P-6)
TASK_ID=$(jq -r '.task_id // ""' "$REFINE_MARKER" 2>/dev/null || echo "")
THRESHOLD=$(jq -r '.threshold // "0.85"' "$REFINE_MARKER" 2>/dev/null || echo "0.85")
MAX_ITER=$(jq -r '.max_iterations // "5"' "$REFINE_MARKER" 2>/dev/null || echo "5")

if [ -z "$TASK_ID" ]; then
  # Invalid marker — clean up and allow stop
  rm -f "$REFINE_MARKER"
  exit 0
fi

# --- Check current state ---
SCRIPTS_DIR="$ACTUAL_ROOT/scripts/refinement"
if [ ! -f "$SCRIPTS_DIR/memory-ops.sh" ]; then
  # Infrastructure missing — allow stop
  exit 0
fi

# Honest fallback: script or jq failure → safe defaults (P-6)
BEST_SCORE=$(bash "$SCRIPTS_DIR/memory-ops.sh" best --task "$TASK_ID" 2>/dev/null | jq -r '.score // "0"' 2>/dev/null || echo "0")
ITERATION=$(bash "$SCRIPTS_DIR/memory-ops.sh" count --task "$TASK_ID" 2>/dev/null || echo "0")

# --- Termination check (bc 금지, awk only) ---
# Score >= threshold → allow stop
# P-6: awk failure on non-numeric input → exit non-zero → falls through to block (fail-safe)
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
