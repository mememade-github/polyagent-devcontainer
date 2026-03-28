#!/bin/bash
# session-end.sh — SessionEnd hook
# Logs session closure metrics. Non-blocking observation hook (exit 0 always).
# Consumer: session-metrics.log (operational audit trail).

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

INPUT=$(cat)

# Honest fallback: jq unavailable or parse failure
SOURCE=$(echo "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null || echo "unknown")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Collect available session metrics
TOOL_CALLS=0
COUNTER_FILE="$PROJECT_DIR/.claude/.tool-call-counter"
if [ -f "$COUNTER_FILE" ]; then
  TOOL_CALLS=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")  # Honest fallback
fi

ERROR_COUNT=0
ERROR_FILE="$PROJECT_DIR/.claude/.error-log"
if [ -f "$ERROR_FILE" ]; then
  ERROR_COUNT=$(wc -l < "$ERROR_FILE" 2>/dev/null || echo "0")  # Honest fallback
fi

LOG_FILE="$PROJECT_DIR/.claude/session-metrics.log"

if ! printf '{"timestamp":"%s","event":"session_end","source":"%s","session_id":"%s","tool_calls":%s,"error_count":%s}\n' \
  "$TIMESTAMP" "$SOURCE" "$SESSION_ID" "$TOOL_CALLS" "$ERROR_COUNT" \
  >> "$LOG_FILE"; then
  echo "WARN: session metrics log write failed: $LOG_FILE" >&2
fi

exit 0
