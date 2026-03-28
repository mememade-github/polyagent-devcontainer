#!/bin/bash
# PostToolUse hook (matcher: Edit|Write): Remind agent to run tests when modifying .claude/ files.
# Context-injection hook (non-blocking). Uses jq for JSON I/O.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
RELATIVE_PATH=$(echo "$FILE_PATH" | sed "s|^$PROJECT_DIR/||")

# Only activate for .claude/ subtree and CLAUDE.md
case "$RELATIVE_PATH" in
  .claude/agents/*) TEST="bash .claude/tests/test-agents.sh" ;;
  .claude/hooks/*) TEST="bash .claude/tests/test-hooks.sh" ;;
  .claude/settings.json) TEST="bash .claude/tests/test-hooks.sh" ;;
  .claude/rules/*) TEST="bash .claude/tests/test-governance.sh" ;;
  .claude/skills/*) TEST="bash .claude/tests/test-governance.sh" ;;
  CLAUDE.md) TEST="bash .claude/tests/test-governance.sh" ;;
  *) exit 0 ;;
esac

jq -n --arg file "$RELATIVE_PATH" --arg test "$TEST" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: (".claude/ file modified: " + $file + ". Verify: " + $test)
  }
}' || true  # Suggestion hook: jq failure must not block session

exit 0
