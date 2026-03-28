#!/bin/bash
# pre-compact.sh — Save critical state before context compaction
# Event: PreCompact
# Purpose: Preserve task progress and key context that might be lost during compaction

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# read JSON from stdin (PreCompact provides session context)
INPUT=$(cat)

# save compact event metadata
# Honest fallback: jq unavailable or parse failure → "unknown" (P-6)
COMPACT_TYPE=$(echo "$INPUT" | jq -r '.matcher // "unknown"' 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# log compaction event for debugging
if ! printf '{"ts":"%s","event":"pre_compact","type":"%s"}\n' \
  "$TIMESTAMP" "$COMPACT_TYPE" \
  >> "$PROJECT_DIR/.claude/compaction.log"; then
  echo "WARN: compaction log write failed: $PROJECT_DIR/.claude/compaction.log" >&2
fi

# Note: PreCompact does not support hookSpecificOutput JSON.
# Context preservation is handled by the compaction.log above.
exit 0
