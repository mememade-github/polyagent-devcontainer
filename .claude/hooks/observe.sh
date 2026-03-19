#!/bin/bash
# Instinct observation hook — records tool calls to observations.jsonl
# Called by PreToolUse/PostToolUse hooks. MUST complete in < 2 seconds.
# Part of continuous-learning-v2 (instinct-based learning system).

# Resolve actual project root (worktree -> original repo root)
_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
if command -v git &>/dev/null; then
  _GIT_COMMON=$(git -C "$_PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$_GIT_COMMON" ] && [ "$_GIT_COMMON" != ".git" ]; then
    _ACTUAL_ROOT=$(dirname "$_GIT_COMMON")
  else
    _ACTUAL_ROOT="$_PROJECT_DIR"
  fi
else
  _ACTUAL_ROOT="$_PROJECT_DIR"
fi

DIR="$_ACTUAL_ROOT/.claude/instincts"
FILE="$DIR/observations.jsonl"

# Ensure directory exists (fast no-op after first call)
[ -d "$DIR" ] || mkdir -p "$DIR/personal" "$DIR/inherited" "$DIR/archive"

PHASE="${1:-unknown}"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Read tool info from stdin (Claude Code hook JSON)
# Use 4096 bytes to avoid truncating JSON mid-field
INPUT=$(head -c 4096 2>/dev/null || echo "{}")

# Extract tool name with sed (no python/jq dependency for speed)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$TOOL" ] && TOOL="unknown"

# Extract input_summary: first 200 chars of tool_input value (truncate for speed)
# JSON-escape: strip control chars, escape backslash FIRST, then double-quote
# Use tr for backslash to avoid sed double-interpretation issues (W-4 fix)
INPUT_SUMMARY=$(echo "$INPUT" | sed -n 's/.*"tool_input"[[:space:]]*:[[:space:]]*\(.\{1,200\}\).*/\1/p' | head -1 | tr -d '\000-\010\013\014\016-\037' | tr '\n\r\t' '   ' | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
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
# Use %s for all fields to avoid printf interpreting % in user data
if [ -n "$INPUT_SUMMARY" ]; then
  LINE="{\"ts\":\"$TS\",\"phase\":\"$PHASE\",\"tool\":\"$TOOL\",\"input_summary\":\"$INPUT_SUMMARY\"$SUCCESS}"
  printf '%s\n' "$LINE" >> "$FILE" 2>/dev/null
else
  LINE="{\"ts\":\"$TS\",\"phase\":\"$PHASE\",\"tool\":\"$TOOL\"$SUCCESS}"
  printf '%s\n' "$LINE" >> "$FILE" 2>/dev/null
fi

# per-worktree heartbeat for session detection (worker-guard.sh reads this)
# PROJECT_DIR = current worktree path, distinct from ACTUAL_ROOT
_HEARTBEAT="${CLAUDE_PROJECT_DIR:-.}/.claude/.heartbeat"
touch "$_HEARTBEAT" 2>/dev/null

# Rotate at 10MB to prevent unbounded growth
if [ -f "$FILE" ]; then
  SIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE" 2>/dev/null || echo 0)
  if [ "$SIZE" -gt 10485760 ]; then
    mv "$FILE" "$DIR/archive/observations.$(date +%Y%m%d%H%M%S).jsonl" 2>/dev/null
  fi
fi
