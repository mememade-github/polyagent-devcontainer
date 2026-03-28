#!/bin/bash
# PostToolUse hook (matcher: Edit|Write): Track file modifications in products/
# When files under products/ are modified, creates a pending-review marker
# and injects a reminder into Claude's context.
#
# Marker file: $ACTUAL_ROOT/.claude/.pending-review.$BRANCH_SAFE (per-worktree)
# Cleared by: review-complete.sh (called after code-reviewer agent finishes)

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Resolve actual project root (worktree -> original repo root)
# Intentional: graceful fallback when git is not installed (P-1)
if command -v git &>/dev/null; then
  # Worktree resolution: may not be in a git repo (P-2)
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
# Honest fallback: "unknown" signals uncertainty (P-3)
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

# Only track changes in products/ directory (relative to actual project root)
RELATIVE_PATH=$(echo "$FILE_PATH" | sed "s|^$PROJECT_DIR/||" | sed "s|^$ACTUAL_ROOT/||")
if ! echo "$RELATIVE_PATH" | grep -q '^products/'; then
  exit 0
fi

MARKER="$ACTUAL_ROOT/.claude/.pending-review.$BRANCH_SAFE"
if [ -f "$MARKER" ]; then
  if ! grep -qF "$RELATIVE_PATH" "$MARKER"; then
    if ! echo "$RELATIVE_PATH" >> "$MARKER"; then
      echo "WARN: review marker append failed: $MARKER" >&2
    fi
  fi
else
  if ! echo "$RELATIVE_PATH" > "$MARKER"; then
    echo "WARN: review marker create failed: $MARKER" >&2
  fi
fi

FILE_COUNT=$(wc -l < "$MARKER")

jq -n --arg count "$FILE_COUNT" --arg file "$RELATIVE_PATH" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("products/ file modified: " + $file + " (" + $count + " file(s) pending review). Per CLAUDE.md §2: delegate to code-reviewer agent before committing. After review, mark complete to clear the pending-review marker.")
  }
}' || true  # Suggestion hook: jq failure must not block session

exit 0
