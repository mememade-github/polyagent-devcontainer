#!/bin/bash
# Strategic compaction suggestion hook
# Tracks Edit/Write tool calls and suggests /compact at logical breakpoints.
# Called by PostToolUse(Edit|Write). MUST complete in < 2 seconds.

COUNTER_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/.tool-call-counter"
THRESHOLD=${COMPACT_THRESHOLD:-50}
REMIND_INTERVAL=25

# Increment counter
COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE" 2>/dev/null

# First threshold: suggest compaction
if [ "$COUNT" -eq "$THRESHOLD" ]; then
  jq -n --arg msg "[Strategic Compact] $THRESHOLD edit/write calls reached. Consider /compact at next logical breakpoint to preserve context quality." '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $msg
    }
  }'
  exit 0
fi

# Periodic reminders after threshold
if [ "$COUNT" -gt "$THRESHOLD" ]; then
  SINCE=$((COUNT - THRESHOLD))
  if [ $((SINCE % REMIND_INTERVAL)) -eq 0 ]; then
    jq -n --arg msg "[Strategic Compact] $COUNT edit/write calls. /compact recommended between task phases." '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $msg
      }
    }'
    exit 0
  fi
fi
