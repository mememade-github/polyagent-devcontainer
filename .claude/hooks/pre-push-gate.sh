#!/bin/bash
# PreToolUse hook (matcher: Bash): git push safety gate
# 3-layer progressive hardening — works from initial state, no declaration needed.
#
# Layer 1: PAT residue in remote URL → BLOCK (exit 2)
# Layer 2: Remote URL drift from baseline → WARN (stderr feedback)
# Layer 3: .push-remote declaration mismatch → BLOCK (exit 2, opt-in)
#
# Uses exit code 2 + stderr for reliable blocking per official docs:
#   "Exit 2 means a blocking error. stderr text is fed back to Claude."
# Reference: https://code.claude.com/docs/en/hooks#exit-code-output

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Only intercept git push
if ! echo "$COMMAND" | grep -qE '\bgit\s+push\b'; then
  exit 0
fi

# Resolve repo root (worktree-aware)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
if command -v git &>/dev/null; then
  REPO_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)
else
  REPO_ROOT="$PROJECT_DIR"
fi
[ -z "$REPO_ROOT" ] && exit 0

# Extract push target remote from command
PUSH_REMOTE=$(echo "$COMMAND" | sed -n 's/.*git\s\+push\s\+\(\S\+\).*/\1/p')
[ -z "$PUSH_REMOTE" ] && PUSH_REMOTE="origin"

# Get actual URL for that remote
ACTUAL_URL=$(git -C "$REPO_ROOT" config "remote.${PUSH_REMOTE}.url" 2>/dev/null)
[ -z "$ACTUAL_URL" ] && exit 0

# === LAYER 1: PAT residue detection (HARD BLOCK) ===
if echo "$ACTUAL_URL" | grep -qE 'github_pat_[A-Za-z0-9_]+@|ghp_[A-Za-z0-9]+@|glpat-[A-Za-z0-9_]+@|ghs_[A-Za-z0-9]+@|oauth2:[^@]+@'; then
  MASKED_URL=$(echo "$ACTUAL_URL" | sed -E 's/(oauth2:|github_pat_|ghp_|glpat-|ghs_)[^@]*@/***@/g')
  echo "Push blocked: credential detected in remote URL." >&2
  echo "  Remote: $PUSH_REMOTE" >&2
  echo "  URL: $MASKED_URL" >&2
  echo "Fix: git remote set-url $PUSH_REMOTE <url-without-credentials>" >&2
  exit 2
fi

# === LAYER 2: Remote URL drift detection (WARN) ===
BASELINE_DIR="$REPO_ROOT/.claude"
BASELINE_FILE="$BASELINE_DIR/.last-push-url.${PUSH_REMOTE}"

if [ -f "$BASELINE_FILE" ]; then
  # Graceful: baseline file may be empty or corrupted (P-1)
  BASELINE_URL=$(cat "$BASELINE_FILE" 2>/dev/null)
  if [ -n "$BASELINE_URL" ] && [ "$ACTUAL_URL" != "$BASELINE_URL" ]; then
    echo "Warning: remote '$PUSH_REMOTE' URL changed since last push." >&2
    echo "  Previous: $BASELINE_URL" >&2
    echo "  Current:  $ACTUAL_URL" >&2
    echo "If intentional, baseline will update after this push." >&2
  fi
fi

# Record baseline (create on first push, update on subsequent)
if [ -d "$BASELINE_DIR" ]; then
  echo "$ACTUAL_URL" > "$BASELINE_FILE" 2>/dev/null
fi

# === LAYER 3: Declaration validation (OPT-IN) ===
DECL_FILE="$REPO_ROOT/.claude/.push-remote"
if [ -f "$DECL_FILE" ]; then
  EXPECTED=$(grep "^${PUSH_REMOTE}=" "$DECL_FILE" 2>/dev/null | cut -d= -f2-)
  if [ -n "$EXPECTED" ]; then
    CLEAN_URL=$(echo "$ACTUAL_URL" | sed -E 's|https://[^@]+@|https://|')
    if ! echo "$CLEAN_URL" | grep -qF "$EXPECTED"; then
      echo "Push blocked: remote URL doesn't match declaration." >&2
      echo "  Expected: $EXPECTED" >&2
      echo "  Actual:   $CLEAN_URL" >&2
      echo "  Source:   $DECL_FILE" >&2
      echo "Fix: git remote set-url $PUSH_REMOTE <correct-url>" >&2
      exit 2
    fi
  fi
fi

exit 0
