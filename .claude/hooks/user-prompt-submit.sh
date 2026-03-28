#!/bin/bash
# user-prompt-submit.sh — UserPromptSubmit hook
# Injects active-state reminders (WIP, refinement, pending review).
# Survives compaction — re-injects context that PostCompact may miss.
# Non-blocking observation hook (exit 0 always).

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Resolve worktree-safe root
GIT_COMMON=$(git -C "$PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null)  # Worktree resolution
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  ACTUAL_ROOT=$(cd "$PROJECT_DIR" && cd "$(dirname "$GIT_COMMON")" && pwd)
else
  ACTUAL_ROOT="$PROJECT_DIR"
fi

BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")  # Honest fallback
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

CONTEXT_PARTS=()

# Check active refinement
if [ -f "$ACTUAL_ROOT/.claude/.refinement-active" ]; then
  CONTEXT_PARTS+=("[REFINEMENT ACTIVE] Iterative refinement loop in progress.")
fi

# Check pending review
if [ -f "$ACTUAL_ROOT/.claude/.pending-review.$BRANCH_SAFE" ]; then
  CONTEXT_PARTS+=("[REVIEW PENDING] Code changes await review before commit.")
fi

# Check WIP tasks
WIP_DIRS=$(ls -d "$ACTUAL_ROOT"/wip/*/ 2>/dev/null)  # Resource may not exist
if [ -n "$WIP_DIRS" ]; then
  WIP_COUNT=$(echo "$WIP_DIRS" | wc -l | tr -d ' ')
  CONTEXT_PARTS+=("[WIP ACTIVE] $WIP_COUNT task(s) in wip/ directory.")
fi

# Only output if there's something to inject
if [ ${#CONTEXT_PARTS[@]} -gt 0 ]; then
  JOINED=$(printf '%s ' "${CONTEXT_PARTS[@]}")
  if command -v jq &>/dev/null; then  # Intentional: graceful fallback
    jq -n --arg ctx "$JOINED" \
      '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$ctx}}'
  fi
fi

exit 0
