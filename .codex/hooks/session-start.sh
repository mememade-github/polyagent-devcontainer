#!/bin/bash
# SessionStart hook: inject project context + memory + WIP + env check

set -u

INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // .hook_event_name // "startup"' 2>/dev/null || echo "startup")
PROJECT_DIR="${CODEX_PROJECT_DIR:-.}"
STATE_DIR="$PROJECT_DIR/.codex/state"
CONTEXT=""

if command -v git >/dev/null 2>&1; then
  GIT_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_DIR")
else
  GIT_ROOT="$PROJECT_DIR"
fi

mkdir -p "$STATE_DIR" 2>/dev/null || true

if command -v git >/dev/null 2>&1 && [ -e "$GIT_ROOT/.git" ]; then
  BRANCH=$(git -C "$GIT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  DIRTY=$(git -C "$GIT_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  CONTEXT="${CONTEXT}Git branch: ${BRANCH} (${DIRTY} uncommitted changes)\n"
fi

if [ -f "$GIT_ROOT/MEMORY.md" ]; then
  MEMORY_SUMMARY=$(head -20 "$GIT_ROOT/MEMORY.md" | sed 's/^/  /')
  CONTEXT="${CONTEXT}Known issues from MEMORY.md:\n${MEMORY_SUMMARY}\n"
fi

if [ -d "$GIT_ROOT/wip" ]; then
  WIP_DIRS=$(find "$GIT_ROOT/wip" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [ -n "$WIP_DIRS" ]; then
    CONTEXT="${CONTEXT}Active WIP tasks:\n"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      TASK_NAME=$(basename "$d")
      CONTEXT="${CONTEXT}  - ${TASK_NAME}\n"
      if [ -f "$d/README.md" ]; then
        SUMMARY=$(head -5 "$d/README.md" | sed 's/^/    /')
        CONTEXT="${CONTEXT}${SUMMARY}\n"
      fi
    done <<< "$WIP_DIRS"
    CONTEXT="${CONTEXT}\nAUTO_RESUME: WIP tasks detected. Per AGENTS.md, read the WIP README.md and resume work immediately.\n"
  fi
fi

ENV_ISSUES=""
[ ! -S /var/run/docker.sock ] && ENV_ISSUES="${ENV_ISSUES}  - Docker socket not available\n"
# Template-level .devcontainer/.env presence (single source of user-tunable values per PROJECT.md)
[ ! -f "$GIT_ROOT/.devcontainer/.env" ] && ENV_ISSUES="${ENV_ISSUES}  - .devcontainer/.env missing (copy .devcontainer/.env.example)\n"
if [ -n "$ENV_ISSUES" ]; then
  CONTEXT="${CONTEXT}Environment issues:\n${ENV_ISSUES}"
fi

if command -v git >/dev/null 2>&1; then
  ACTIVE_SAFE=$(git -C "$GIT_ROOT" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null | while read -r b; do echo "$b" | tr '/' '-'; done)
  for marker in "$STATE_DIR"/last-verification.*; do
    [ -f "$marker" ] || continue
    MARKER_BRANCH="${marker##*.}"
    if ! echo "$ACTIVE_SAFE" | grep -qxF "$MARKER_BRANCH"; then
      rm -f "$marker"
    fi
  done
fi

if [ -f /.dockerenv ]; then
  OS_INFO=$(. /etc/os-release 2>/dev/null && echo "$NAME $VERSION_ID" || echo "Linux")
  CONTEXT="${CONTEXT}Environment: Dev Container (${OS_INFO})\n"
else
  CONTEXT="${CONTEXT}Environment: Host ($(uname -s))\n"
fi

CONTEXT="${CONTEXT}Hook source: ${SOURCE}\n"
CONTEXT="${CONTEXT}User: $(whoami)\n"

jq -n --arg ctx "$(echo -e "$CONTEXT")" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}' || true

exit 0
