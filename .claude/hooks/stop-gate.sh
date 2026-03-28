#!/bin/bash
# Stop hook: Prevent Claude from stopping when code review is pending
# Checks .pending-review marker — if files are pending review, blocks Stop.
#
# Safety: file-based loop prevention (if already blocked once, allow stop).
# The marker is cleared by review-complete.sh after code-reviewer finishes.

INPUT=$(cat)

# Resolve actual project root (worktree -> original repo root)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
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

# Honest fallback: "unknown" signals uncertainty (P-3)
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

# File-based loop prevention: if we already blocked once recently, allow stop
BLOCK_MARKER="$ACTUAL_ROOT/.claude/.stop-blocked-review.$BRANCH_SAFE"
if [ -f "$BLOCK_MARKER" ]; then
  BLOCK_MTIME=$(stat -c %Y "$BLOCK_MARKER" 2>/dev/null) || {
    # Cannot read block marker — safe to clear and continue
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

MARKER="$ACTUAL_ROOT/.claude/.pending-review.$BRANCH_SAFE"

if [ ! -f "$MARKER" ]; then
  exit 0
fi

# filter out files already committed — only uncommitted changes need review
UNCOMMITTED_FILES=""
while IFS= read -r file; do
  [ -z "$file" ] && continue
  FULL_PATH="$ACTUAL_ROOT/$file"
  if [ -f "$FULL_PATH" ]; then
    # subrepo detection: find the git root for this file
    FILE_DIR=$(dirname "$FULL_PATH")
    # git rev-parse may fail if not in a git repo (subrepo detection)
    SUB_ROOT=$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$ACTUAL_ROOT")
    if [ "$SUB_ROOT" != "$ACTUAL_ROOT" ]; then
      # file is in a subrepo — run diff there
      # realpath may fail on dangling paths — fallback to original
      SUB_REL=$(realpath --relative-to="$SUB_ROOT" "$FULL_PATH" 2>/dev/null || echo "$file")
      # git diff conditional: failure = "no changes" = correct semantics (P-8)
      if git -C "$SUB_ROOT" diff --name-only HEAD -- "$SUB_REL" 2>/dev/null | grep -q .; then
        UNCOMMITTED_FILES="${UNCOMMITTED_FILES}${file}\n"
      elif git -C "$SUB_ROOT" diff --cached --name-only -- "$SUB_REL" 2>/dev/null | grep -q .; then
        UNCOMMITTED_FILES="${UNCOMMITTED_FILES}${file}\n"
      fi
    else
      # file exists: check for unstaged or staged changes
      # git diff conditional: failure = "no changes" = correct semantics (P-8)
      if git -C "$ACTUAL_ROOT" diff --name-only HEAD -- "$file" 2>/dev/null | grep -q .; then
        UNCOMMITTED_FILES="${UNCOMMITTED_FILES}${file}\n"
      elif git -C "$ACTUAL_ROOT" diff --cached --name-only -- "$file" 2>/dev/null | grep -q .; then
        UNCOMMITTED_FILES="${UNCOMMITTED_FILES}${file}\n"
      fi
    fi
  else
    # file missing from disk: may have been deleted — still needs review (fail toward safety)
    UNCOMMITTED_FILES="${UNCOMMITTED_FILES}${file}\n"
  fi
done < "$MARKER"

# all files committed — auto-clear marker and allow stop
if [ -z "$UNCOMMITTED_FILES" ]; then
  rm -f "$MARKER"
  exit 0
fi

FILE_COUNT=$(printf '%b' "$UNCOMMITTED_FILES" | grep -c .)
FILES=$(printf '%b' "$UNCOMMITTED_FILES" | head -5 | tr '\n' ', ')

if [ "$FILE_COUNT" -gt 0 ]; then
  # Record that we blocked, so next invocation allows stop
  touch "$BLOCK_MARKER"
  jq -n --arg count "$FILE_COUNT" --arg files "$FILES" --arg projdir "$PROJECT_DIR" '{
    decision: "block",
    reason: ($count + " file(s) in products/ were modified but not reviewed: " + $files + "\nPer CLAUDE.md §2: delegate to code-reviewer agent (team: quality) before finishing. After review completes, run: bash \"" + $projdir + "/.claude/hooks/review-complete.sh\" to clear.")
  }'
fi
