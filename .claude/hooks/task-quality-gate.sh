#!/bin/bash
# task-quality-gate.sh — Quality gate for completed agent team tasks
# Event: TaskCompleted
# Purpose: Verify task completion meets quality standards before accepting

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# read JSON from stdin
INPUT=$(cat)

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# log task completion
# Honest fallback: jq unavailable or parse failure → empty JSON (P-6)
TASK_INFO=$(echo "$INPUT" | jq -r '.tool_input // "{}"' 2>/dev/null || echo "{}")
if ! printf '{"ts":"%s","event":"task_completed","info":"%s"}\n' \
  "$TIMESTAMP" "$(echo "$TASK_INFO" | head -c 200)" \
  >> "$PROJECT_DIR/.claude/task-completions.log"; then
  echo "WARN: task completion log write failed: $PROJECT_DIR/.claude/task-completions.log" >&2
fi

# non-blocking: inject quality reminder with optional refinement context
REFINE_MARKER="$PROJECT_DIR/.claude/.refinement-active"
REFINE_CTX=""
if [ -f "$REFINE_MARKER" ] && [ ! -L "$REFINE_MARKER" ]; then
  REFINE_TASK=$(jq -r '.task_id // ""' "$REFINE_MARKER" 2>/dev/null || echo "")
  REFINE_THRESH=$(jq -r '.threshold // "0.85"' "$REFINE_MARKER" 2>/dev/null || echo "0.85")
  if [ -n "$REFINE_TASK" ]; then
    SCRIPTS_DIR="$PROJECT_DIR/scripts/refinement"
    if [ -f "$SCRIPTS_DIR/memory-ops.sh" ]; then
      BEST=$(bash "$SCRIPTS_DIR/memory-ops.sh" best --task "$REFINE_TASK" 2>/dev/null | jq -r '.score // "0"' 2>/dev/null || echo "0")
      ITER=$(bash "$SCRIPTS_DIR/memory-ops.sh" count --task "$REFINE_TASK" 2>/dev/null || echo "0")
      REFINE_CTX=" Refinement active: task=$REFINE_TASK score=$BEST threshold=$REFINE_THRESH iteration=$ITER."
    fi
  fi
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "TaskCompleted",
    "additionalContext": "Task completed. Verify: (1) output meets acceptance criteria, (2) no regressions introduced, (3) changes are consistent with project standards.${REFINE_CTX}"
  }
}
EOF
