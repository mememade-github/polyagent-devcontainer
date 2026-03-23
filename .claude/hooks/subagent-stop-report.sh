#!/bin/bash
# subagent-stop-report.sh — SubagentStop hook
# Logs subagent completion with last_assistant_message summary.
# Non-blocking observation hook (exit 0 always).

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

INPUT=$(cat)

# Honest fallback: jq unavailable or parse failure (P-6)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"' 2>/dev/null || echo "unknown")
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // "unknown"' 2>/dev/null || echo "unknown")
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SUMMARY=$(echo "$LAST_MSG" | head -c 300)

LOG_FILE="$PROJECT_DIR/.claude/subagent.log"

if ! printf '[%s] SubagentStop agent=%s id=%s summary=%s\n' \
  "$TIMESTAMP" "$AGENT_TYPE" "$AGENT_ID" "$SUMMARY" \
  >> "$LOG_FILE"; then
  echo "WARN: subagent stop log write failed: $LOG_FILE" >&2
fi

exit 0
