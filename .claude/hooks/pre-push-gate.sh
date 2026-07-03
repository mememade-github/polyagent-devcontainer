#!/bin/bash
# PrePush gate (PreToolUse, matcher: Bash): block pushing inline credentials and
# flag remote-URL drift / declaration mismatches.
#
# Scope (deliberate): the credential HARD BLOCK below scans the RAW command plus
# every configured remote of the target repo, so a credential is caught no matter
# how the command is wrapped or nested (timeout/xargs/flock/sh -c/env -S/control
# structures) — the raw scan does not depend on parsing the push out of a wrapper.
# The gate therefore does NOT carry a large adversarial command parser: per
# REFERENCE.md the container is a workspace boundary, not a trust boundary, so
# enforcing "the command must be shaped so the gate can parse it" adds complexity
# without adding credential safety. Drift (Layer 2) and declaration (Layer 3) use
# a light best-effort parse of the push target.

INPUT=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq is required to parse hook input safely." >&2
  exit 2
fi
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Cheap pre-filter: proceed only for commands that could be a git push. Strip
# shell quotes first so quote-obfuscated words (g"i"t / pu"sh") and a separator
# between git and push (-c '...;...' push) are still recognized; Layer 1 below
# then scans the raw command, so wrapping (timeout/xargs/sh -c/env -S) is caught
# regardless. A false candidate costs only one python parse; it never blocks.
# Quote-strip only: backslash-split words (git p\ush) and custom push aliases
# stay out of charter — the container is a workspace boundary, not a trust one.
STRIPPED=$(printf '%s' "$COMMAND" | tr -d '\042\047\140')
if ! printf '%s' "$STRIPPED" | grep -qw git; then
  exit 0
fi
if ! printf '%s' "$STRIPPED" | grep -qw push; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Blocked: python3 is required to parse git push commands safely." >&2
  exit 2
fi

# Light parse: locate each `git push`, resolving `git -C <path>` for the target
# repo and the first positional as the remote (for the drift/declaration layers).
parse_git_push() {
  python3 - "$COMMAND" "$PROJECT_DIR" <<'PY'
import json, os, shlex, sys

command, base_dir = sys.argv[1], sys.argv[2]
seps = {"&&", "||", ";", "|", "&", "(", ")"}
git_global_value = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                    "--exec-path", "--config", "--config-env"}
push_value_opts = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}

def abspath(path, cwd):
    return os.path.abspath(path if os.path.isabs(path) else os.path.join(cwd, path))

try:
    toks = shlex.split(command, posix=True)
except ValueError:
    print(json.dumps({"found": False, "invocations": [], "workdir": os.path.abspath(base_dir)}))
    sys.exit(0)

segments, cur = [], []
for t in toks:
    if t in seps:
        if cur:
            segments.append(cur)
            cur = []
    else:
        cur.append(t)
if cur:
    segments.append(cur)

def push_of(seg, base):
    n = len(seg)
    if n == 0 or seg[0] != "git":
        return None
    cwd = base
    j = 1
    while j < n:
        t = seg[j]
        if t == "-C":
            if j + 1 >= n:
                return None
            cwd = abspath(seg[j + 1], cwd)
            j += 2
            continue
        if t.startswith("-C") and len(t) > 2:
            cwd = abspath(t[2:], cwd)
            j += 1
            continue
        if t in git_global_value:
            j += 2
            continue
        if t.startswith("-"):
            j += 1
            continue
        if t != "push":
            return None
        args = seg[j + 1:]
        remote = ""
        k = 0
        while k < len(args):
            a = args[k]
            if a == "--":
                if k + 1 < len(args):
                    remote = args[k + 1]
                break
            if a in push_value_opts:
                k += 2
                continue
            if a.startswith("-"):
                k += 1
                continue
            remote = a
            break
        return (os.path.abspath(cwd), remote)
    return None

invs = []
for seg in segments:
    r = push_of(seg, base_dir)
    if r is None:
        continue
    invs.append({"workdir": r[0], "remote": r[1]})

print(json.dumps({
    "found": bool(invs),
    "invocations": invs,
    "workdir": invs[0]["workdir"] if invs else os.path.abspath(base_dir),
}))
PY
}

if ! PUSH_INFO=$(parse_git_push); then
  echo "Blocked: unable to parse git push command safely." >&2
  exit 2
fi

# === LAYER 1: credential residue (HARD BLOCK) ===
# 1a: scan the RAW command — nesting-robust, catches credentials regardless of
#     any wrapper/subshell (timeout/xargs/flock/sh -c/env -S/control structures).
# 1b: scan configured remote URLs of the session repo AND any parsed `-C` target
#     — closes the case where the command names a clean remote alias whose stored
#     URL carries a credential (independent of how the command names its target).
CRED_RE='github_pat_[A-Za-z0-9_]+@|ghp_[A-Za-z0-9]+@|glpat-[A-Za-z0-9_]+@|ghs_[A-Za-z0-9]+@|oauth2:[^@[:space:]]+@|https?://[^/@[:space:]]+@'
CONFIG_REMOTE_STORED_RE='^(remote\..*\.(url|pushurl)|url\..*\.(insteadof|pushinsteadof)|credential\..*)[[:space:]]'
# git -c / --config-env overrides that can inject a credential or redirect the push
# target: a redirected remote/url, an auth-carrying http.extraHeader (the value is
# an Authorization header, so it has no `@` for CRED_RE to catch), or a config
# include that pulls in a credentialed remote the scans below never see.
CONFIG_OVERRIDE_RE='(^|[[:space:]])(-c|--config|--config-env)(=|[[:space:]])+(config-env:)?(remote\.[^=[:space:]]*\.(url|pushurl)|url\.[^=[:space:]]*\.(insteadof|pushinsteadof)|credential\.|include\.|includeif\.|http\.[^=[:space:]]*extraheader)'
# The same override keys injected via GIT_CONFIG_* env vars (parity with the -c
# form): GIT_CONFIG/_GLOBAL/_SYSTEM point at a config file, GIT_CONFIG_KEY_n=<key>
# sets one key. No documented push workflow uses these, so block them on a push.
GIT_CONFIG_ENV_RE='(^|[[:space:]])GIT_CONFIG(_[A-Z0-9]+)*='
LEAK=""
if printf '%s' "$COMMAND" | grep -Eq "$CRED_RE"; then
  LEAK="command: $(printf '%s' "$COMMAND" | grep -oE "$CRED_RE" | head -1)"
fi
if printf '%s' "$COMMAND" | grep -Eiq "$CONFIG_OVERRIDE_RE"; then
  LEAK="$LEAK
command: remote/url/credential/include/http.extraHeader config override on a push"
fi
if printf '%s' "$COMMAND" | grep -Eq "$GIT_CONFIG_ENV_RE"; then
  LEAK="$LEAK
command: GIT_CONFIG_* env config override on a push"
fi
scan_stored_config() {
  local root
  root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
  local hit
  hit=$(git -C "$root" config --get-regexp '.*' 2>/dev/null | grep -Ei "$CONFIG_REMOTE_STORED_RE" | grep -E "$CRED_RE" || true)
  [ -n "$hit" ] && printf '%s stored-config: %s' "$root" "$hit"
}
# Always scan the session repo (covers wrapped/nested pushes that name no -C).
_s=$(scan_stored_config "$PROJECT_DIR")
[ -n "$_s" ] && LEAK="$LEAK
$_s"
while IFS= read -r _push; do
  _workdir=$(echo "$_push" | jq -r '.workdir')
  _s=$(scan_stored_config "$_workdir")
  [ -n "$_s" ] && LEAK="$LEAK
$_s"
done < <(echo "$PUSH_INFO" | jq -c '.invocations[]')
if [ -n "$LEAK" ]; then
  echo "Blocked: credential, config override (remote/url/credential/include/http.extraHeader), or GIT_CONFIG env injection detected in the command." >&2
  echo "$LEAK" | sed -E 's#(https?://)[^/@[:space:]]+@#\1***@#g' | sed -E 's/(oauth2:|github_pat_|ghp_|glpat-|ghs_)[^@]*@/***@/g' | sed 's/^/  /' >&2
  echo "Fix: git remote set-url <remote> <url-without-credentials>; keep tokens and remote/url overrides out of the command." >&2
  exit 2
fi

# === LAYER 2 (drift, WARN) + LAYER 3 (declaration, OPT-IN) ===
while IFS= read -r _push; do
  _workdir=$(echo "$_push" | jq -r '.workdir')
  REPO_ROOT=$(git -C "$_workdir" rev-parse --show-toplevel 2>/dev/null || true)
  [ -z "$REPO_ROOT" ] && continue
  PUSH_REMOTE=$(echo "$_push" | jq -r '.remote')
  [ -z "$PUSH_REMOTE" ] && PUSH_REMOTE=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null | cut -d/ -f1)
  [ -z "$PUSH_REMOTE" ] && PUSH_REMOTE="origin"
  DIRECT_URL=0
  if printf '%s\n' "$PUSH_REMOTE" | grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*://|^[^/:@]+@[^/:]+:.+|^[^/:]+\.[^/:]+:.+|^[^/:]+:.*/.+'; then
    DIRECT_URL=1
    ACTUAL_URL="$PUSH_REMOTE"
  else
    ACTUAL_URL=$(git -C "$REPO_ROOT" remote get-url --push --all "$PUSH_REMOTE" 2>/dev/null | head -1)
    [ -z "$ACTUAL_URL" ] && ACTUAL_URL=$(git -C "$REPO_ROOT" config "remote.${PUSH_REMOTE}.url" 2>/dev/null)
  fi
  [ -z "$ACTUAL_URL" ] && continue

  BASELINE_DIR="$REPO_ROOT/.claude"
  PUSH_REMOTE_SAFE=$(printf '%s' "$PUSH_REMOTE" | sed -E 's/[^A-Za-z0-9._-]+/_/g')
  [ -n "$PUSH_REMOTE_SAFE" ] || PUSH_REMOTE_SAFE="direct-url"
  BASELINE_FILE="$BASELINE_DIR/.last-push-url.${PUSH_REMOTE_SAFE}"
  if [ -f "$BASELINE_FILE" ]; then
    BASELINE_URL=$(cat "$BASELINE_FILE" 2>/dev/null)
    if [ -n "$BASELINE_URL" ] && [ "$ACTUAL_URL" != "$BASELINE_URL" ]; then
      echo "Warning: remote '$PUSH_REMOTE' URL changed since last push." >&2
      echo "  Previous: $BASELINE_URL" >&2
      echo "  Current:  $ACTUAL_URL" >&2
      echo "If intentional, baseline will update after this push." >&2
    fi
  fi
  if [ -d "$BASELINE_DIR" ]; then
    echo "$ACTUAL_URL" > "$BASELINE_FILE" || echo "WARN: baseline write failed: $BASELINE_FILE" >&2
  fi

  DECL_FILE="$REPO_ROOT/.claude/.push-remote"
  if [ -f "$DECL_FILE" ]; then
    if [ "$DIRECT_URL" -eq 1 ]; then
      EXPECTED=$(cut -d= -f2- "$DECL_FILE" 2>/dev/null)
    else
      EXPECTED=$(grep "^${PUSH_REMOTE}=" "$DECL_FILE" 2>/dev/null | cut -d= -f2-)
    fi
    if [ -n "$EXPECTED" ]; then
      CLEAN_URL=$(printf '%s\n' "$ACTUAL_URL" | sed -E 's#(https?://)[^/@[:space:]]+@#\1#g')
      MATCHED=0
      while IFS= read -r _expected; do
        [ -z "$_expected" ] && continue
        if printf '%s\n' "$CLEAN_URL" | grep -qF "$_expected"; then
          MATCHED=1
          break
        fi
      done <<< "$EXPECTED"
      if [ "$MATCHED" -ne 1 ]; then
        echo "Push blocked: remote URL doesn't match declaration." >&2
        echo "  Expected: $EXPECTED" >&2
        echo "  Actual:   $CLEAN_URL" >&2
        echo "  Source:   $DECL_FILE" >&2
        echo "Fix: git remote set-url $PUSH_REMOTE <correct-url>" >&2
        exit 2
      fi
    fi
  fi
done < <(echo "$PUSH_INFO" | jq -c '.invocations[]')

exit 0
