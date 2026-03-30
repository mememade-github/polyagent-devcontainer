#!/bin/bash
# SessionStart hook: Inject project context + WIP auto-resume + env check
# Outputs JSON with additionalContext that Claude receives at session start.
# Worktree-aware: resolves actual project root via git-common-dir.

INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

# Gather live context
CONTEXT=""

# Set project dir early (used by all sections)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Resolve actual project root (worktree → original repo root)
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

# 1. Git status summary
if command -v git &>/dev/null && [ -e "$PROJECT_DIR/.git" ]; then
  BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  DIRTY=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l)
  CONTEXT="${CONTEXT}Git branch: ${BRANCH} (${DIRTY} uncommitted changes)\n"
fi

# 2. Active WIP tasks — auto-resume directive (always check ACTUAL_ROOT)
if [ -d "$ACTUAL_ROOT/wip" ]; then
  WIP_DIRS=$(ls -d "$ACTUAL_ROOT"/wip/*/ 2>/dev/null)
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

# 3. Environment quick check (use ACTUAL_ROOT for .env/)
ENV_ISSUES=""
[ ! -S /var/run/docker.sock ] && ENV_ISSUES="${ENV_ISSUES}  - Docker socket not available\n"
# Check for any SSH deploy key (project-agnostic)
SSH_KEY_FOUND=$(find "${HOME}/.ssh/" -name "*_ed25519" -o -name "*_rsa" 2>/dev/null | head -1)
[ -z "$SSH_KEY_FOUND" ] && ENV_ISSUES="${ENV_ISSUES}  - No SSH deploy key found\n"
# Check for env directory (use ACTUAL_ROOT — .env/ lives at project root, not worktree)
[ -d "$ACTUAL_ROOT/.env" ] && [ -z "$(ls "$ACTUAL_ROOT/.env/"*.env 2>/dev/null)" ] && ENV_ISSUES="${ENV_ISSUES}  - .env/ directory has no .env files\n"
[ ! -d "$ACTUAL_ROOT/.env" ] && ENV_ISSUES="${ENV_ISSUES}  - .env/ directory missing\n"

if [ -n "$ENV_ISSUES" ]; then
  CONTEXT="${CONTEXT}Environment issues:\n${ENV_ISSUES}"
  CONTEXT="${CONTEXT}AUTO_CHECK: Review environment issues above and resolve if blocking.\n"
fi

# 4. Stale markers cleanup
rm -f "$ACTUAL_ROOT/.claude/.last-verification"

# orphan marker cleanup: remove verification markers for deleted branches
for marker in "$ACTUAL_ROOT"/.claude/.last-verification.*; do
  [ -f "$marker" ] || continue
  MARKER_FILE=$(basename "$marker")
  MARKER_BRANCH="${MARKER_FILE#.last-verification.}"
  [ -z "$MARKER_BRANCH" ] && continue
  if ! git -C "$PROJECT_DIR" rev-parse --verify "$MARKER_BRANCH" &>/dev/null; then
    rm -f "$marker"
  fi
done

# 5. Environment info (auto-detected)
if [ -f /.dockerenv ]; then
  # Optional: os-release may not exist (P-5)
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
}' || true  # Context hook: jq failure must not block session

exit 0
