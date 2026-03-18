#!/bin/bash
# Instinct observation hook — records tool calls to observations.jsonl
# Called by PreToolUse/PostToolUse hooks. MUST complete in < 2 seconds.
# Part of continuous-learning-v2 (instinct-based learning system).

DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/instincts"
FILE="$DIR/observations.jsonl"

# Ensure directory exists (fast no-op after first call)
[ -d "$DIR" ] || mkdir -p "$DIR/personal" "$DIR/inherited" "$DIR/archive"

PHASE="${1:-unknown}"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Read tool info from stdin (Claude Code hook JSON)
# Use timeout to prevent hanging, read only first 1000 chars for speed
INPUT=$(head -c 1000 2>/dev/null || echo "{}")

# Extract tool name with sed (no python/jq dependency for speed)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$TOOL" ] && TOOL="unknown"

# Extract input_summary: first 200 chars of tool_input value (truncate for speed)
# JSON-escape: replace backslash, double-quote, newline, tab with safe chars
INPUT_SUMMARY=$(echo "$INPUT" | sed -n 's/.*"tool_input"[[:space:]]*:[[:space:]]*\(.\{1,200\}\).*/\1/p' | head -1 | tr -d '\000-\010\013\014\016-\037' | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g' | tr '\n' ' ' | tr -d '\r')
[ -z "$INPUT_SUMMARY" ] && INPUT_SUMMARY=""

# Detect success in post phase (check for error indicators in response)
SUCCESS=""
if [ "$PHASE" = "post" ]; then
  if echo "$INPUT" | grep -qi '"error"\|"FAIL"\|"not found"' 2>/dev/null; then
    SUCCESS=',"success":false'
  else
    SUCCESS=',"success":true'
  fi
fi

# Append observation (atomic write) — 5 fields: ts, phase, tool, input_summary, success
if [ -n "$INPUT_SUMMARY" ]; then
  printf '{"ts":"%s","phase":"%s","tool":"%s","input_summary":"%s"%s}\n' "$TS" "$PHASE" "$TOOL" "$INPUT_SUMMARY" "$SUCCESS" >> "$FILE" 2>/dev/null
else
  printf '{"ts":"%s","phase":"%s","tool":"%s"%s}\n' "$TS" "$PHASE" "$TOOL" "$SUCCESS" >> "$FILE" 2>/dev/null
fi

# Rotate at 10MB to prevent unbounded growth
if [ -f "$FILE" ]; then
  SIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE" 2>/dev/null || echo 0)
  if [ "$SIZE" -gt 10485760 ]; then
    mv "$FILE" "$DIR/archive/observations.$(date +%Y%m%d%H%M%S).jsonl" 2>/dev/null
  fi
fi
