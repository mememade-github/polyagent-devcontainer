#!/bin/bash
# claude-hooks-adapter.sh — run the Claude hooks under Antigravity (agy).
#
# Antigravity reads .agents/hooks.json and runs each handler with the working
# directory set to .agents/. This adapter translates the agy hook contract to
# the Claude hook contract, calls the unmodified .claude/hooks/*.sh, and
# translates the result back. It never executes the tool command itself.
#
# Usage: bash hooks/claude-hooks-adapter.sh <session-start|pre-tool-use>
# Event mapping is documented in REFERENCE.md, section Hooks.
# For pre-tool-use, an empty {} blocks commands; emit ask on a non-denial.
#
# Exit status is always 0 with one valid JSON object on stdout: that is the
# agy response format, not a claim that a gate succeeded. The fail-open policy
# of the Claude hooks is unchanged: pre-push-gate.sh exit 2 -> deny, anything
# else -> ask. An ask is not an approval. When the gate did not check the
# command (its exit is neither 0 nor 2, including a 124 timeout) or the adapter
# could not run it (no jq, unreadable input, no hook file), the answer is still
# ask, and one line "pre-push gate: not checked: <cause>" goes to the adapter's
# stderr so that case is not silent like a checked ask.
EVENT="${1:-}"

fallback() {
  case "$EVENT" in
    pre-tool-use) printf '%s\n' '{"decision":"ask"}' ;;
    session-start) printf '%s\n' '{"injectSteps":[]}' ;;
    *) printf '%s\n' '{}' ;;
  esac
  exit 0
}
unchecked() {
  [ "$EVENT" = pre-tool-use ] && echo "pre-push gate: not checked: $1" >&2
  fallback
}

INPUT=$(cat 2>/dev/null) || INPUT=""
command -v jq >/dev/null 2>&1 || unchecked "jq not found (adapter)"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) ||
  ROOT=$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || unchecked "project root not found (adapter)"
HOOKS="$ROOT/.claude/hooks"

case "$EVENT" in
  pre-tool-use)
    CMD=$(printf '%s' "$INPUT" | jq -r '.toolCall.args.CommandLine // empty' 2>/dev/null) || unchecked "jq could not read the hook input as JSON (adapter)"
    [ -n "$CMD" ] || unchecked "no toolCall.args.CommandLine in the hook input (adapter)"
    CWD=$(printf '%s' "$INPUT" | jq -r '.toolCall.args.Cwd // empty' 2>/dev/null) || unchecked "jq could not read toolCall.args.Cwd (adapter)"
    PROJ="$ROOT"
    RUN_DIR="$ROOT"
    if [ -n "$CWD" ] && [ -d "$CWD" ]; then
      RUN_DIR="$CWD"
      # Outside a repository the gate gets Cwd itself and reports a push there as not checked.
      P=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) && PROJ="$P" || PROJ="$CWD"
    fi
    CLAUDE_INPUT=$(jq -n --arg c "$CMD" '{tool_name: "Bash", tool_input: {command: $c}}') || unchecked "could not build the Claude hook input (adapter)"
    [ -f "$HOOKS/pre-push-gate.sh" ] || unchecked "$HOOKS/pre-push-gate.sh not found (adapter)"
    ERR=$(cd "$RUN_DIR" && printf '%s' "$CLAUDE_INPUT" |
      CLAUDE_PROJECT_DIR="$PROJ" timeout 5 bash "$HOOKS/pre-push-gate.sh" 2>&1 >/dev/null)
    RC=$?
    if [ "$RC" -eq 2 ]; then
      jq -cn --arg r "$ERR" '{decision: "deny", reason: $r}' || unchecked "could not build the deny response (adapter)"
      exit 0
    fi
    [ "$RC" -eq 0 ] && fallback
    LAST=${ERR##*$'\n'}
    unchecked "pre-push-gate.sh exited $RC${LAST:+: ${LAST#pre-push gate: not checked: }} (adapter)"
    ;;
  session-start)
    CTX=""
    if [ -f "$HOOKS/session-start.sh" ]; then
      OUT=$(cd "$ROOT" && printf '%s' '{"source":"startup"}' |
        CLAUDE_PROJECT_DIR="$ROOT" timeout 10 bash "$HOOKS/session-start.sh" 2>/dev/null)
      CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null) || CTX=""
    fi
    # Antigravity does not follow an instruction to read PROJECT.md, so its
    # contents ride in the session-start message. --rawfile, not --arg: a large
    # file would exceed the single-argument size limit.
    if [ -s "$ROOT/PROJECT.md" ] && [ -r "$ROOT/PROJECT.md" ]; then
      jq -cn --arg c "$CTX" --rawfile p "$ROOT/PROJECT.md" \
        '{injectSteps: [{systemMessage: {systemMessage: ((if $c == "" then "" else $c + "\n" end) + "Project instructions from PROJECT.md at the repository root; follow them as you follow AGENTS.md:\n\n" + $p)}}]}' 2>/dev/null &&
        exit 0
    fi
    [ -n "$CTX" ] || fallback
    jq -cn --arg m "$CTX" '{injectSteps: [{systemMessage: {systemMessage: $m}}]}' || fallback
    ;;
  *)
    fallback
    ;;
esac
exit 0
