#!/bin/bash
# PreToolUse hook (matcher: Bash): Enforce pre-commit verification gate
# Intercepts `git commit` commands and blocks unless verification was run recently.
# Uses exit code 2 + stderr for reliable blocking per official docs:
#   "Exit 2 means a blocking error. stderr text is fed back to Claude."
# Reference: https://code.claude.com/docs/en/hooks#exit-code-output
#
# Marker file: created by completion-checker.sh at ACTUAL_ROOT/.claude/.last-verification.$BRANCH_SAFE

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only intercept git commit commands (not git add, git status, etc.)
if ! echo "$COMMAND" | grep -qE '\bgit\s+commit\b'; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Resolve actual project root (worktree -> original repo root)
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

# resolve branch name for per-worktree marker isolation
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

MARKER="$ACTUAL_ROOT/.claude/.last-verification.$BRANCH_SAFE"
MAX_AGE=600  # 10 minutes

if [ ! -f "$MARKER" ]; then
  echo "Pre-commit verification required. Run verification first:" >&2
  echo "1. Python: ruff check src/ && mypy src/ --ignore-missing-imports" >&2
  echo "2. TypeScript: pnpm build" >&2
  echo "3. Or run: your project verification script (see CLAUDE.md §3)" >&2
  exit 2
fi

# Check if marker is recent enough
MARKER_MTIME=$(stat -c %Y "$MARKER" 2>/dev/null) || {
  echo "FAIL: cannot read verification marker: $MARKER" >&2
  exit 2
}
MARKER_AGE=$(( $(date +%s) - MARKER_MTIME ))

if [ "$MARKER_AGE" -gt "$MAX_AGE" ]; then
  echo "Verification is stale (${MARKER_AGE}s ago). Run verification again before committing:" >&2
  echo "1. Python: ruff check src/ && mypy src/ --ignore-missing-imports" >&2
  echo "2. TypeScript: pnpm build" >&2
  echo "3. Or run: your project verification script (see CLAUDE.md §3)" >&2
  exit 2
fi

# Verification is recent — allow commit
exit 0
