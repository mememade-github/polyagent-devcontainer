#!/bin/bash
# worker-guard.sh — Detect other active sessions via git worktree + heartbeat
# Called by session-start.sh to inject session awareness into context.
# Outputs plain text (not JSON) — caller wraps into additionalContext.
#
# Detection mechanism:
#   1. git worktree list → all worktree paths (including main)
#   2. per-worktree .heartbeat mtime → heartbeat (written by observe.sh to PROJECT_DIR)
#   3. mtime < HEARTBEAT_TIMEOUT → active session
# No registration needed — git is the source of truth, observe.sh provides heartbeat.
# Key: observe.sh writes .heartbeat to PROJECT_DIR (per-worktree), not ACTUAL_ROOT (shared).

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
HEARTBEAT_TIMEOUT=600  # seconds — session inactive after 10 minutes without tool call

# resolve actual project root (handle worktree)
if command -v git &>/dev/null; then
  GIT_COMMON=$(git -C "$PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
    ACTUAL_ROOT=$(dirname "$GIT_COMMON")
  else
    ACTUAL_ROOT="$PROJECT_DIR"
  fi
else
  ACTUAL_ROOT="$PROJECT_DIR"
fi

CURRENT_PATH=$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)
CURRENT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
NOW=$(date +%s)

# collect active sessions from all worktrees
OUTPUT=""
ACTIVE_COUNT=0
SAME_WORKTREE_CONFLICT=false

while IFS= read -r line; do
  # parse: /path/to/worktree  <sha> [branch-name]
  WT_PATH=$(echo "$line" | awk '{print $1}')
  WT_BRANCH=$(echo "$line" | sed -n 's/.*\[\(.*\)\]/\1/p')

  [ -z "$WT_PATH" ] && continue

  WT_REAL=$(cd "$WT_PATH" 2>/dev/null && pwd -P)
  [ -z "$WT_REAL" ] && continue

  # skip self
  [ "$WT_REAL" = "$CURRENT_PATH" ] && continue

  # check heartbeat via per-worktree .heartbeat file (written by observe.sh)
  HB_FILE="$WT_PATH/.claude/.heartbeat"
  if [ ! -f "$HB_FILE" ]; then
    continue
  fi

  HB_MTIME=$(stat -c '%Y' "$HB_FILE" 2>/dev/null || stat -f '%m' "$HB_FILE" 2>/dev/null || echo 0)
  AGE=$(( NOW - HB_MTIME ))

  if [ "$AGE" -lt "$HEARTBEAT_TIMEOUT" ]; then
    ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
    AGE_HUMAN="${AGE}s ago"
    OUTPUT="${OUTPUT}  - ${WT_BRANCH} (${WT_PATH}) — last activity ${AGE_HUMAN}\n"
  fi
done < <(git -C "$ACTUAL_ROOT" worktree list 2>/dev/null)

# output if other active sessions found
if [ "$ACTIVE_COUNT" -gt 0 ]; then
  echo "ACTIVE_SESSIONS: ${ACTIVE_COUNT} other session(s) detected via heartbeat:"
  echo -e "$OUTPUT"
  echo "COLLABORATION: Per collaboration-protocol.md, check file ownership before editing shared files."
  echo "NOTE: Detection based on per-worktree .heartbeat mtime (updated every tool call by observe.sh)."
fi

# check if current branch diverges from main
if [ "$CURRENT_BRANCH" != "main" ]; then
  BEHIND=$(git -C "$PROJECT_DIR" rev-list --count HEAD..main 2>/dev/null || echo "?")
  if [ "$BEHIND" != "0" ] && [ "$BEHIND" != "?" ]; then
    echo "SYNC_NEEDED: Current branch is ${BEHIND} commits behind main. Consider: git rebase main"
  fi
fi
