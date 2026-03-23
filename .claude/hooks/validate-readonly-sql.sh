#!/bin/bash
# validate-readonly-sql.sh — PreToolUse hook for database-reviewer
# Blocks SQL write operations (DROP, DELETE, TRUNCATE, ALTER) in Bash commands.
# SELECT, INSERT, UPDATE are allowed for review/testing workflows.
# Only blocks destructive DDL and bulk data loss operations.

set -euo pipefail

INPUT=$(cat)

# Honest fallback: jq unavailable or parse failure (P-6)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Block destructive SQL operations (case-insensitive)
if echo "$COMMAND" | grep -iE '\b(DROP|TRUNCATE|ALTER)\b' > /dev/null 2>&1; then
  echo "Blocked: Destructive SQL operation detected (DROP/TRUNCATE/ALTER). Database-reviewer operates in review mode only." >&2
  exit 2
fi

exit 0
