#!/bin/bash
# Stop hook: Prevent Claude from stopping when code review is pending
# Checks .pending-review marker — if files are pending review, blocks Stop.
#
# Safety: checks stop_hook_active to prevent infinite loops.
# The marker is cleared by review-complete.sh after code-reviewer finishes.

INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# Prevent infinite loop: if we already blocked once, allow stop
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
MARKER="$PROJECT_DIR/.claude/.pending-review"

if [ ! -f "$MARKER" ]; then
  exit 0
fi

FILE_COUNT=$(wc -l < "$MARKER")
FILES=$(cat "$MARKER" | head -5 | tr '\n' ', ')

if [ "$FILE_COUNT" -gt 0 ]; then
  jq -n --arg count "$FILE_COUNT" --arg files "$FILES" '{
    decision: "block",
    reason: ($count + " file(s) in products/ were modified but not reviewed: " + $files + "\nPer CLAUDE.md §2: delegate to code-reviewer agent (team: quality) before finishing. After review completes, run: bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/review-complete.sh\" to clear.")
  }'
fi
