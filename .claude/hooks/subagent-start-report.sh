#!/bin/bash
# subagent-start-report.sh — SubagentStart hook
# Logs subagent creation with agent type and ID.
# Non-blocking observation hook (exit 0 always).

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

INPUT=$(cat)

# Honest fallback: jq unavailable or parse failure
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"' 2>/dev/null || echo "unknown")
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // "unknown"' 2>/dev/null || echo "unknown")

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

LOG_FILE="$PROJECT_DIR/.claude/subagent.log"

if ! printf '[%s] SubagentStart agent=%s id=%s\n' \
  "$TIMESTAMP" "$AGENT_TYPE" "$AGENT_ID" \
  >> "$LOG_FILE"; then
  echo "WARN: subagent start log write failed: $LOG_FILE" >&2
fi

exit 0
