#!/bin/bash
# trajectory.sh — Format refinement attempts as XML trajectory (worst→best)
# Usage: trajectory.sh --task <id> [--max N]
# Output: XML with CDATA-wrapped feedback (Poetiq create_examples pattern)

set -euo pipefail

TASK_ID=""
MAX_ITEMS=5

while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK_ID="$2"; shift 2 ;;
    --max)  MAX_ITEMS="$2"; shift 2 ;;
    *)      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$TASK_ID" ]; then
  echo "Error: --task required" >&2
  exit 1
fi
if ! [[ "$TASK_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: invalid task_id" >&2
  exit 1
fi

# --- Locate data ---
STORE_DIR="${CLAUDE_AGENT_MEMORY:-${CLAUDE_PROJECT_DIR:-.}/.claude/agent-memory}/refinement/attempts"
FILE="$STORE_DIR/$TASK_ID.jsonl"

if [ ! -f "$FILE" ] || [ ! -s "$FILE" ]; then
  echo '<previous_attempts count="0" best_score="0"></previous_attempts>'
  exit 0
fi

# --- Select best N, display worst→best (Poetiq create_examples pattern) ---
# sort_by(.score) | .[-N:] = select top N by score, already in worst→best order
# Select top N by score, not most recent N
ATTEMPTS=$(jq -s --argjson max "$MAX_ITEMS" '
  sort_by(.score) | .[-$max:]
' "$FILE")

COUNT=$(echo "$ATTEMPTS" | jq 'length')
BEST_SCORE=$(echo "$ATTEMPTS" | jq 'last.score')

# --- XML entity escaping for <result> ---
xml_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# --- CDATA safety: split ]]> sequences ---
cdata_safe() {
  sed 's/]]>/]]]]><![CDATA[>/g'
}

# --- Build XML ---
echo "<previous_attempts count=\"$COUNT\" best_score=\"$BEST_SCORE\">"

echo "$ATTEMPTS" | jq -c '.[]' | while IFS= read -r entry; do
  N=$(echo "$entry" | jq '.attempt')
  SCORE=$(echo "$entry" | jq '.score')
  RESULT_RAW=$(echo "$entry" | jq -r '.result_summary')
  FEEDBACK_RAW=$(echo "$entry" | jq -r '.feedback')

  RESULT_ESCAPED=$(printf '%s' "$RESULT_RAW" | xml_escape)
  FEEDBACK_SAFE=$(printf '%s' "$FEEDBACK_RAW" | cdata_safe)

  cat <<XMLBLOCK
  <attempt n="$N" score="$SCORE">
    <result>$RESULT_ESCAPED</result>
    <feedback><![CDATA[
$FEEDBACK_SAFE
    ]]></feedback>
  </attempt>
XMLBLOCK
done

echo "</previous_attempts>"
