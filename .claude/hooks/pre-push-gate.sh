#!/bin/bash
# PrePush gate (PreToolUse, matcher: Bash): block pushing inline credentials and
# flag remote-URL drift.
#
# Scope (deliberate): the credential HARD BLOCK catches credentials visible in
# the raw command text plus every configured remote of the target repo, regardless
# of common wrappers (timeout/xargs/flock/sh -c/env -S/control structures);
# deliberate obfuscation and assembled tokens are out of charter — the container
# is a workspace boundary, not a trust boundary.
# The gate therefore does NOT carry a large adversarial command parser: enforcing
# "the command must be shaped so the gate can parse it" adds complexity without
# adding credential safety. Drift (Layer 2) uses a light best-effort parse of the
# push target.

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
# quotes/backticks/backslashes so quote-obfuscated (g"i"t) and backslash-split
# (git p\ush) words both reduce to their executed form before the word test.
# Layer 1 below then scans the raw command, so wrapping (timeout/xargs/sh -c/env -S)
# is caught regardless. A false candidate costs only one python parse; it never blocks.
# The shlex parser below unescapes backslashes, so the strip view must not
# under-match. Custom push aliases stay out of charter — the container is a
# workspace boundary, not a trust one.
STRIPPED=$(printf '%s' "$COMMAND" | tr -d '\042\047\140\\')
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
# repo and the first positional as the remote (for the drift layer).
parse_git_push() {
  python3 - "$COMMAND" "$PROJECT_DIR" <<'PY'
import json, os, shlex, sys

command, base_dir = sys.argv[1], sys.argv[2]
seps = {"&&", "||", ";", "|", "&", "(", ")"}
git_global_value = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                    "--exec-path", "--config", "--config-env"}
push_value_opts = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
force_long = {"--force", "--force-with-lease", "--force-if-includes"}

def abspath(path, cwd):
    return os.path.abspath(path if os.path.isabs(path) else os.path.join(cwd, path))

try:
    lex = shlex.shlex(command, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    toks = list(lex)
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
        force = False
        positionals = []
        k = 0
        while k < len(args):
            a = args[k]
            if a == "--":
                positionals.extend(args[k + 1:])
                if any(p.startswith("+") for p in args[k + 1:]):
                    force = True
                break
            if a in force_long or a.startswith("--force-with-lease="):
                force = True
                k += 1
                continue
            if a in push_value_opts:
                k += 2
                continue
            if any(a.startswith(opt + "=") for opt in push_value_opts):
                k += 1
                continue
            if a.startswith("-"):
                if not a.startswith("--") and "f" in a[1:]:
                    force = True
                k += 1
                continue
            if a.startswith("+"):
                force = True
            positionals.append(a)
            k += 1
        if positionals:
            if positionals[0].startswith("+"):
                remote = ""
            else:
                remote = positionals[0]
        return (os.path.abspath(cwd), remote, force)
    return None

invs = []
for seg in segments:
    r = push_of(seg, base_dir)
    if r is None:
        continue
    invs.append({"workdir": r[0], "remote": r[1], "force": r[2]})

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

# === LAYER 1b: destructive push (BLOCK unless single-use marker exists) ===
safe_component() {
  value=$(printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]+/_/g')
  [ -n "$value" ] && printf '%s' "$value" || printf '%s' unnamed
}
allow_force_marker() {
  local repo_root=$1 remote=$2 branch=$3
  local remote_safe branch_safe marker expected
  remote_safe=$(safe_component "$remote")
  branch_safe=$(safe_component "$branch")
  marker="$repo_root/.claude/.allow-force-push.${remote_safe}.${branch_safe}"
  expected=$(printf 'remote=%s\nbranch=%s\n' "$remote" "$branch")
  if [ ! -f "$marker" ]; then
    echo "Blocked: destructive git push requires explicit single-use approval." >&2
    echo "Detected force push for remote '$remote' on branch '$branch'." >&2
    echo "Narrower alternative: prefer --force-with-lease over --force when rewriting is unavoidable, and coordinate timing with collaborators." >&2
    echo "To approve exactly once, create this marker with exact content, then retry:" >&2
    echo "  printf 'remote=%s\\nbranch=%s\\n' '$remote' '$branch' > '$marker'" >&2
    return 1
  fi
  if [ "$(cat "$marker" 2>/dev/null)" != "$expected" ]; then
    echo "Blocked: force-push approval marker is not scoped to remote '$remote' and branch '$branch'." >&2
    echo "Expected marker content:" >&2
    printf '%s' "$expected" | sed 's/^/  /' >&2
    return 1
  fi
  rm -f "$marker"
  return 0
}
while IFS= read -r _push; do
  [ "$(echo "$_push" | jq -r '.force // false')" = "true" ] || continue
  _workdir=$(echo "$_push" | jq -r '.workdir')
  REPO_ROOT=$(git -C "$_workdir" rev-parse --show-toplevel 2>/dev/null || true)
  [ -z "$REPO_ROOT" ] && continue
  PUSH_REMOTE=$(echo "$_push" | jq -r '.remote')
  [ -z "$PUSH_REMOTE" ] && PUSH_REMOTE=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null | cut -d/ -f1)
  [ -z "$PUSH_REMOTE" ] && PUSH_REMOTE="origin"
  PUSH_BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  PUSH_BRANCH=$(printf '%s\n' "$PUSH_BRANCH" | head -1)
  allow_force_marker "$REPO_ROOT" "$PUSH_REMOTE" "$PUSH_BRANCH" || exit 2
done < <(echo "$PUSH_INFO" | jq -c '.invocations[]')

# === LAYER 2 (drift, WARN) ===
while IFS= read -r _push; do
  _workdir=$(echo "$_push" | jq -r '.workdir')
  REPO_ROOT=$(git -C "$_workdir" rev-parse --show-toplevel 2>/dev/null || true)
  [ -z "$REPO_ROOT" ] && continue
  PUSH_REMOTE=$(echo "$_push" | jq -r '.remote')
  [ -z "$PUSH_REMOTE" ] && PUSH_REMOTE=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null | cut -d/ -f1)
  [ -z "$PUSH_REMOTE" ] && PUSH_REMOTE="origin"
  if printf '%s\n' "$PUSH_REMOTE" | grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*://|^[^/:@]+@[^/:]+:.+|^[^/:]+\.[^/:]+:.+|^[^/:]+:.*/.+'; then
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
      echo "If intentional, no action needed — this URL is now recorded as the baseline (recorded at gate time, before the push runs)." >&2
    fi
  fi
  if [ -d "$BASELINE_DIR" ]; then
    echo "$ACTUAL_URL" > "$BASELINE_FILE" || echo "WARN: baseline write failed: $BASELINE_FILE" >&2
  fi

done < <(echo "$PUSH_INFO" | jq -c '.invocations[]')

exit 0
