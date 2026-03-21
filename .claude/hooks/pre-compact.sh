#!/bin/bash
# pre-compact.sh — Save critical state before context compaction
# Event: PreCompact
# Purpose: Preserve task progress and key context that might be lost during compaction

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# read JSON from stdin (PreCompact provides session context)
INPUT=$(cat)

# save compact event metadata
COMPACT_TYPE=$(echo "$INPUT" | jq -r '.matcher // "unknown"' 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# log compaction event for debugging
printf '{"ts":"%s","event":"pre_compact","type":"%s"}\n' \
  "$TIMESTAMP" "$COMPACT_TYPE" \
  >> "$PROJECT_DIR/.claude/compaction.log" 2>/dev/null || true

# inject context reminder via additionalContext
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": "Context compaction occurring. Key state: Check active tasks via TaskList, check WIP via wip/ directory, check pending reviews via .claude/.pending-review marker."
  }
}
EOF
