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

NEEDS_VERIFICATION=0

if [ ! -f "$MARKER" ]; then
  NEEDS_VERIFICATION=1
else
  MARKER_MTIME=$(stat -c %Y "$MARKER" 2>/dev/null) || NEEDS_VERIFICATION=1
  if [ "$NEEDS_VERIFICATION" -eq 0 ]; then
    MARKER_AGE=$(( $(date +%s) - MARKER_MTIME ))
    if [ "$MARKER_AGE" -gt "$MAX_AGE" ]; then
      NEEDS_VERIFICATION=1
    fi
  fi
fi

if [ "$NEEDS_VERIFICATION" -eq 1 ]; then
  # Try auto-verification for common project types
  CHECKER="$ACTUAL_ROOT/scripts/meta/completion-checker.sh"
  if [ -x "$CHECKER" ] || [ -f "$CHECKER" ]; then
    bash "$CHECKER" >&2
    VERIFY_EXIT=$?
    if [ "$VERIFY_EXIT" -eq 0 ]; then
      exit 0  # checker creates marker on success
    fi
    echo "Auto-verification failed (exit $VERIFY_EXIT). Fix issues before committing." >&2
    exit 2
  fi

  # No checker available — provide self-service instructions
  echo "Verification is stale or missing. Run verification before committing:" >&2
  echo "1. Python: ruff check src/ && mypy src/ --ignore-missing-imports" >&2
  echo "2. TypeScript: pnpm build" >&2
  echo "3. Or run: your project verification script (see CLAUDE.md §3)" >&2
  echo "Then create the marker: mkdir -p '$ACTUAL_ROOT/.claude' && touch '$MARKER'" >&2
  exit 2
fi

# --- Layer 2: /refine requirement check for multi-file changes ---
SCORER="$ACTUAL_ROOT/.refine/score.sh"
REFINE_MARKER="$ACTUAL_ROOT/.claude/.refinement-active"
if [ -f "$SCORER" ] && [ ! -f "$REFINE_MARKER" ]; then
  STAGED_COUNT=$(git -C "$PROJECT_DIR" diff --cached --name-only | wc -l)
  if [ "$STAGED_COUNT" -ge 2 ]; then
    echo "WARNING: $STAGED_COUNT files staged but /refine is not active." >&2
    echo "CLAUDE.md §2 requires /refine for changes affecting 2+ files when scorer exists." >&2
    echo "Consider running /refine instead of direct commit." >&2
    # WARNING only, not blocking — agent can proceed with justification
  fi
fi

# Verification is recent — allow commit
exit 0
