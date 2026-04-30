#!/usr/bin/env bash
# Delegate a headless task to the other AI vendor in a fresh git worktree.
#
# Usage: delegate.sh <claude|codex> <task_name> <prompt...>
#
# Exit codes:
#   0    delegated task completed (vendor returned 0)
#   2    vendor CLI not installed or not authenticated
#   7    re-entrant call blocked (POLYAGENT_DELEGATING=1)
#   64   bad arguments (unknown vendor / invalid task_name / too few args)
#   124  wrapper timeout fired (delegated task killed)
#   *    other non-zero exit from the vendor CLI is propagated as-is
#
# Artifacts (preserved on success and failure):
#   .polyagent/worktrees/<task>-<unix_ts>/        git worktree
#   .polyagent/runs/<task>-<unix_ts>.json         meta (vendor, status, exit_code, ...)
#   .polyagent/runs/<task>-<unix_ts>.out          captured stdout
#   .polyagent/runs/<task>-<unix_ts>.err          captured stderr
#
# Environment overrides:
#   POLYAGENT_TIMEOUT     wrapper hard timeout in seconds (default 600)
#
# Cleanup:
#   scripts/delegate-cleanup.sh [--apply|--archive]

set -euo pipefail

# 1. re-entrancy guard
if [[ -n "${POLYAGENT_DELEGATING:-}" ]]; then
  echo "delegate.sh: re-entrant call blocked (POLYAGENT_DELEGATING=1)" >&2
  exit 7
fi

# 2. arguments
if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <claude|codex> <task_name> <prompt...>" >&2
  exit 64
fi
V=$1; T=$2; shift 2; P="$*"

case "$V" in
  claude|codex) ;;
  *) echo "delegate.sh: unknown vendor '$V' (use claude or codex)" >&2; exit 64 ;;
esac
if [[ ! "$T" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "delegate.sh: task_name must match [a-zA-Z0-9_-]+" >&2
  exit 64
fi

# 3. capability detect (auth check)
if ! command -v "$V" >/dev/null 2>&1 || ! "$V" --version >/dev/null 2>&1; then
  echo "delegate.sh: $V unavailable (not installed or not authenticated)" >&2
  exit 2
fi

# 4. workspace root + slug
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
TS=$(date +%s); SLUG="${T}-${TS}"
WT="$ROOT/.polyagent/worktrees/$SLUG"
META="$ROOT/.polyagent/runs/$SLUG.json"
mkdir -p "$ROOT/.polyagent/runs" "$ROOT/.polyagent/worktrees"

# 5. worktree
git worktree add -b "delegate/$SLUG" "$WT" HEAD >/dev/null

# 6. meta init
python3 - "$META" <<PY
import json, sys, os
json.dump({
  "vendor": "$V", "task": "$T", "slug": "$SLUG",
  "worktree": "$WT", "branch": "delegate/$SLUG",
  "started": "$(date -Iseconds)", "status": "running"
}, open(sys.argv[1], "w"), indent=2)
PY

# 7. headless invocation (timeout: hard kill after grace 30s)
TO=${POLYAGENT_TIMEOUT:-600}
export POLYAGENT_DELEGATING=1
RC=0
case "$V" in
  claude)
    timeout --kill-after=30s "${TO}s" \
      claude -p --output-format json --add-dir "$WT" \
        --allow-dangerously-skip-permissions \
        "$P" \
      > "${META%.json}.out" 2> "${META%.json}.err" || RC=$?
    ;;
  codex)
    ( cd "$WT" && timeout --kill-after=30s "${TO}s" \
        codex exec --skip-git-repo-check \
          --dangerously-bypass-approvals-and-sandbox \
          "$P" ) \
      > "${META%.json}.out" 2> "${META%.json}.err" || RC=$?
    ;;
esac

# 8. status determination
case "$RC" in 0) S=done;; 124) S=timed_out;; *) S=failed;; esac

# 9. meta finalize
python3 - "$META" "$S" "$RC" <<'PY'
import json, sys
m=json.load(open(sys.argv[1]))
m["status"]=sys.argv[2]
m["exit_code"]=int(sys.argv[3])
import datetime
m["ended"]=datetime.datetime.now().astimezone().isoformat(timespec="seconds")
json.dump(m, open(sys.argv[1],"w"), indent=2)
PY

# 10. result
cat "${META%.json}.out"
exit $RC
