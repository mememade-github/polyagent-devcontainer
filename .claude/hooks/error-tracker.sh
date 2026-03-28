#!/bin/bash
# PostToolUseFailure hook: Track tool failures and remind agent to investigate root cause.
# Uses sed for fast stdin extraction; jq for structured JSON output. MUST complete in < 2 seconds.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
ERROR=$(echo "$INPUT" | sed -n 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$TOOL" ] && TOOL="unknown"

# Log failure
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
if ! printf '[%s] FAIL tool=%s error=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL" "${ERROR:0:200}" >> "$PROJECT_DIR/.claude/.error-log"; then
  echo "WARN: error log write failed: $PROJECT_DIR/.claude/.error-log" >&2
fi

# Inject context — remind agent to investigate
jq -n --arg tool "$TOOL" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUseFailure",
    additionalContext: ("Tool " + $tool + " failed. Per Coding Rule #6: diagnose and fix the root cause before proceeding. Do NOT silently skip or work around the error.")
  }
}' || true  # Observation hook: jq failure must not block session

exit 0
