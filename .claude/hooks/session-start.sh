#!/bin/bash
# SessionStart hook: Inject project context + WIP auto-resume + env check
# Outputs JSON with additionalContext that Claude receives at session start.
# This is the core automation driver — Claude acts on these directives without user prompting.

INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

# Set environment variables for the session
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export CLAUDE_CODE_DISABLE_AUTO_MEMORY=0' >> "$CLAUDE_ENV_FILE"
fi

# Gather live context
CONTEXT=""

# Set project dir early (used by all sections)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# 1. Git status summary
if command -v git &>/dev/null && [ -d "$PROJECT_DIR/.git" ]; then
  BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  DIRTY=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l)
  CONTEXT="${CONTEXT}Git branch: ${BRANCH} (${DIRTY} uncommitted changes)\n"
fi

# 2. Active WIP tasks — auto-resume directive
if [ -d "$PROJECT_DIR/wip" ]; then
  WIP_DIRS=$(ls -d "$PROJECT_DIR"/wip/*/ 2>/dev/null)
  if [ -n "$WIP_DIRS" ]; then
    CONTEXT="${CONTEXT}Active WIP tasks:\n"
    for d in $WIP_DIRS; do
      TASK_NAME=$(basename "$d")
      CONTEXT="${CONTEXT}  - ${TASK_NAME}\n"
      # Include first 5 lines of README for immediate context
      if [ -f "$d/README.md" ]; then
        SUMMARY=$(head -5 "$d/README.md" | sed 's/^/    /')
        CONTEXT="${CONTEXT}${SUMMARY}\n"
      fi
    done
    CONTEXT="${CONTEXT}\nAUTO_RESUME: WIP tasks detected. Per CLAUDE.md Automated Workflow step 1, read the WIP README.md and resume work immediately.\n"
  fi
fi

# 3. Environment quick check
ENV_ISSUES=""
[ ! -S /var/run/docker.sock ] && ENV_ISSUES="${ENV_ISSUES}  - Docker socket not available\n"
# Check for any SSH deploy key (project-agnostic)
SSH_KEY_FOUND=$(find "${HOME}/.ssh/" -name "*_ed25519" -o -name "*_rsa" 2>/dev/null | head -1)
[ -z "$SSH_KEY_FOUND" ] && ENV_ISSUES="${ENV_ISSUES}  - No SSH deploy key found\n"
# Check for env directory (project-agnostic)
[ -d "$PROJECT_DIR/.env" ] && [ -z "$(ls "$PROJECT_DIR/.env/"*.env 2>/dev/null)" ] && ENV_ISSUES="${ENV_ISSUES}  - .env/ directory has no .env files\n"
[ ! -d "$PROJECT_DIR/.env" ] && ENV_ISSUES="${ENV_ISSUES}  - .env/ directory missing\n"

if [ -n "$ENV_ISSUES" ]; then
  CONTEXT="${CONTEXT}Environment issues:\n${ENV_ISSUES}"
  CONTEXT="${CONTEXT}AUTO_CHECK: Delegate to environment-checker agent (team: quality) to diagnose.\n"
fi

# 4. Known Issues — parse from auto memory (system-enforced, not AI-dependent)
# Derive project memory path portably
PROJECT_KEY=$(echo "$PROJECT_DIR" | tr "/" "-" | sed "s/^-//")
MEMORY_DIR="${HOME}/.claude/projects/${PROJECT_KEY}/memory"
MEMORY_FILE="$MEMORY_DIR/MEMORY.md"
if [ -f "$MEMORY_FILE" ]; then
  KNOWN_ISSUES=$(grep -E 'ISSUE-[0-9]+' "$MEMORY_FILE" 2>/dev/null | head -10)
  if [ -n "$KNOWN_ISSUES" ]; then
    CONTEXT="${CONTEXT}Known Issues (from MEMORY.md — system-parsed):\n"
    while IFS= read -r line; do
      CONTEXT="${CONTEXT}  ${line}\n"
    done <<< "$KNOWN_ISSUES"
    CONTEXT="${CONTEXT}AUTO_REPORT: Include these Known Issues in your session start summary.\n"
  fi
fi

# 5. Stale markers cleanup — clear old pending-review if leftover from previous session
PENDING_MARKER="$PROJECT_DIR/.claude/.pending-review"
if [ -f "$PENDING_MARKER" ]; then
  MARKER_AGE=$(( $(date +%s) - $(stat -c %Y "$PENDING_MARKER" 2>/dev/null || echo 0) ))
  if [ "$MARKER_AGE" -gt 3600 ]; then
    rm -f "$PENDING_MARKER"
    CONTEXT="${CONTEXT}Note: Stale pending-review marker (${MARKER_AGE}s old) was auto-cleaned.\n"
  else
    PENDING_FILES=$(cat "$PENDING_MARKER" | head -5 | tr '\n' ', ')
    CONTEXT="${CONTEXT}WARNING: Pending code review from previous session: ${PENDING_FILES}\n"
    CONTEXT="${CONTEXT}AUTO_ACTION: Complete code review before other work.\n"
  fi
fi

# 6. Claude Code update check (daily, cached)
UPDATE_SCRIPT="$PROJECT_DIR/.claude/hooks/claude-update-check.sh"
if [ -x "$UPDATE_SCRIPT" ]; then
  UPDATE_INFO=$("$UPDATE_SCRIPT" 2>/dev/null)
  if [ -n "$UPDATE_INFO" ]; then
    CONTEXT="${CONTEXT}${UPDATE_INFO}\n"
  fi
fi

# 7. Instinct system status (observation count)
OBS_FILE="$PROJECT_DIR/.claude/instincts/observations.jsonl"
if [ -f "$OBS_FILE" ]; then
  OBS_COUNT=$(wc -l < "$OBS_FILE" 2>/dev/null || echo 0)
  INSTINCT_COUNT=$(find "$PROJECT_DIR/.claude/instincts/personal/" -name "*.md" 2>/dev/null | wc -l)
  if [ "$OBS_COUNT" -gt 0 ] || [ "$INSTINCT_COUNT" -gt 0 ]; then
    CONTEXT="${CONTEXT}Instinct system: ${OBS_COUNT} observations, ${INSTINCT_COUNT} personal instincts\n"
  fi
fi

# 8. Tool call counter reset (new session = fresh count)
COUNTER_FILE="$PROJECT_DIR/.claude/.tool-call-counter"
echo "0" > "$COUNTER_FILE" 2>/dev/null

# 9. Environment info (auto-detected)
if [ -f /.dockerenv ]; then
  OS_INFO=$(. /etc/os-release 2>/dev/null && echo "$NAME $VERSION_ID" || echo "Linux")
  CONTEXT="${CONTEXT}Environment: Dev Container (${OS_INFO})\n"
else
  CONTEXT="${CONTEXT}Environment: Host ($(uname -s))\n"
fi
CONTEXT="${CONTEXT}User: $(whoami)\n"

# Output JSON with additionalContext
jq -n --arg ctx "$(echo -e "$CONTEXT")" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
