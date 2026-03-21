#!/bin/bash
# post-compact.sh — Restore context awareness after compaction
# Event: PostCompact
# Purpose: Re-inject critical context that may have been lost during compaction

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# read JSON from stdin
INPUT=$(cat)

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# log post-compaction event
printf '{"ts":"%s","event":"post_compact"}\n' \
  "$TIMESTAMP" \
  >> "$PROJECT_DIR/.claude/compaction.log" 2>/dev/null || true

# check for active WIP
WIP_SUMMARY=""
if [ -d "$PROJECT_DIR/wip" ]; then
  WIP_COUNT=$(find "$PROJECT_DIR/wip" -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l)
  if [ "$WIP_COUNT" -gt 0 ]; then
    WIP_SUMMARY="Active WIP tasks: $WIP_COUNT. Resume with wip-manager agent."
  fi
fi

# check for pending review
REVIEW_NOTE=""
if [ -f "$PROJECT_DIR/.claude/.pending-review" ]; then
  REVIEW_NOTE="Pending code review exists. Delegate to code-reviewer before committing."
fi

# inject recovery context
CONTEXT="Post-compaction context recovery."
[ -n "$WIP_SUMMARY" ] && CONTEXT="$CONTEXT $WIP_SUMMARY"
[ -n "$REVIEW_NOTE" ] && CONTEXT="$CONTEXT $REVIEW_NOTE"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostCompact",
    "additionalContext": "$CONTEXT"
  }
}
EOF
