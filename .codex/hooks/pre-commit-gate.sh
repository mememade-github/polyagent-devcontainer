#!/bin/bash
# PreToolUse hook: enforce pre-commit verification gate for Codex harness
#
# Scope (deliberate, mirror of the Claude gate): stops the COMMON accidental
# bypass — `--no-verify` / `-n` on a real `git commit` — quoting-aware so a
# commit MESSAGE mentioning the flag is not a false positive, and separator-aware
# so a `-n` on an adjacent command (git commit -m x && git log -n 5) is not
# matched. It does NOT chase exotic shell evasions (nested `sh -c`, process
# substitution, env overrides): per REFERENCE.md the container is a workspace
# boundary, not a trust boundary, so completeness there is unwinnable. The
# load-bearing enforcement is the fail-closed verification marker below.

set -u

INPUT=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq is required to parse hook input safely." >&2
  exit 2
fi
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .toolInput.command // .command // .input.command // empty' 2>/dev/null)
PROJECT_DIR="${CODEX_PROJECT_DIR:-.}"
[ -z "$COMMAND" ] && exit 0

if ! command -v python3 >/dev/null 2>&1; then
  if echo "$COMMAND" | grep -qE '(^|[^A-Za-z0-9_])git([^;&|]*[[:space:]])commit([^A-Za-z0-9_]|$)'; then
    echo "Blocked: python3 is required to parse git commit commands safely." >&2
    exit 2
  fi
  exit 0
fi

# Parse the command into {found, no_verify, all, paths}. Quoting- and
# separator-aware, and it parses git's short-option grammar correctly so an
# attached message value (`-mDoc`) is a value, not a flag cluster.
parse_git_commit() {
  python3 - "$COMMAND" "$PROJECT_DIR" <<'PY'
import json, os, shlex, sys

command, base_dir = sys.argv[1], sys.argv[2]
seps = {"&&", "||", ";", "|", "&", "(", ")"}
git_global_value = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                    "--exec-path", "--config", "--config-env"}
value_short = set("mcCFt")   # git commit short opts that consume a value
value_long = {"--message", "--reuse-message", "--reedit-message", "--file",
              "--author", "--date", "--template", "--fixup", "--squash",
              "--trailer", "--cleanup"}

try:
    # shlex.shlex with punctuation_chars splits operators even without surrounding
    # spaces (x&&git -> x, &&, git), so a no-space `&&`/`;` between a commit and a
    # following `git log -n` is segmented out, not mis-read as the commit's -n.
    lex = shlex.shlex(command, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""   # match shlex.split: no comment handling
    toks = list(lex)
except ValueError:
    # Unbalanced quotes / trailing backslash: cannot tokenize safely. Fail closed
    # — signal the wrapper to block if the raw command looks like a git commit, so
    # an unparsed `-n` can't slip through the not-found path.
    print(json.dumps({"parse_error": True}))
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

def abspath(path, cwd):
    return os.path.abspath(path if os.path.isabs(path) else os.path.join(cwd, path))

def commit_of(seg, base):
    """(cwd, argv-after-commit) for a git commit in seg, or None. cwd tracks
    `git -C <path>` so the marker/checker/secret-scan below resolve against the
    repo git will actually commit (worktree locus), not the session root."""
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
        return (cwd, seg[j + 1:]) if t == "commit" else None
    return None

def scan(args):
    no_verify = all_ = False
    paths = []
    skip = endopt = False
    for a in args:
        if endopt:
            paths.append(a)
            continue
        if skip:
            skip = False
            continue
        if a == "--":
            endopt = True
            continue
        if a == "--no-verify":
            no_verify = True
            continue
        if a == "--all":
            all_ = True
            continue
        if a in value_long:
            skip = True
            continue
        if a.startswith("--"):
            continue
        if a.startswith("-") and a != "-":
            rest = a[1:]
            for k, c in enumerate(rest):
                if c == "n":
                    no_verify = True
                elif c == "a":
                    all_ = True
                if c in value_short:
                    if k == len(rest) - 1:
                        skip = True
                    break
            continue
        paths.append(a)
    return no_verify, all_, paths

found = False
no_verify = all_ = False
paths = []
workdir = os.path.abspath(base_dir)
first = True
for seg in segments:
    r = commit_of(seg, base_dir)
    if r is None:
        continue
    cwd, ca = r
    found = True
    if first:
        workdir = os.path.abspath(cwd)
        first = False
    nv, al, pa = scan(ca)
    no_verify = no_verify or nv
    all_ = all_ or al
    paths.extend(pa)

print(json.dumps({
    "found": found,
    "no_verify": no_verify,
    "all": all_,
    "paths": paths,
    "workdir": workdir,
}))
PY
}

if ! COMMIT_INFO=$(parse_git_commit); then
  echo "Blocked: unable to parse git commit command safely." >&2
  exit 2
fi

# Fail closed on an untokenizable command (unbalanced quotes / trailing backslash):
# block if it looks like a git commit, else ignore (not our concern).
if [ "$(echo "$COMMIT_INFO" | jq -r '.parse_error // false')" = "true" ]; then
  if echo "$COMMAND" | grep -qE '(^|[^A-Za-z0-9_])git([^;&|]*[[:space:]])commit([^A-Za-z0-9_]|$)'; then
    echo "Blocked: unable to parse git commit command safely (unbalanced quotes / trailing backslash). Failing closed." >&2
    exit 2
  fi
  exit 0
fi

if [ "$(echo "$COMMIT_INFO" | jq -r '.found // false')" != "true" ]; then
  exit 0
fi

# AUD-2026-029: block --no-verify and its short alias -n on git commit.
if [ "$(echo "$COMMIT_INFO" | jq -r '.no_verify // false')" = "true" ]; then
  echo "Blocked: --no-verify/-n bypass is not permitted (AGENTS.md Pre-Commit Gate)." >&2
  echo "Fix verification issues before committing — do not skip the gate." >&2
  exit 2
fi

# Target the repo git will actually commit: the parser resolved it from any
# `git -C <path>`. Per-worktree on purpose (worktree marker locus).
PROJECT_DIR=$(echo "$COMMIT_INFO" | jq -r '.workdir')
ACTUAL_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_DIR")

# AUD-2026-030: secret-pattern scan on staged content (mirror of Claude variant).
# git commit -a auto-stages tracked mods at commit time and `git commit <path>` commits
# the working-tree version, so scan --cached plus the extra diff each form will pull in.
SECRET_PATTERNS='github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{36}|glpat-[A-Za-z0-9_-]{20,}|ghs_[A-Za-z0-9]{36}|(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}|BEGIN[[:space:]]+(RSA[[:space:]]+|OPENSSH[[:space:]]+|EC[[:space:]]+|DSA[[:space:]]+|ENCRYPTED[[:space:]]+)?PRIVATE[[:space:]]+KEY[-]*[-][[:space:]]*$|AKIA[0-9A-Z]{16}'
SECRET_SCAN=$(git -C "$PROJECT_DIR" diff --cached -U0 2>/dev/null)
if [ "$(echo "$COMMIT_INFO" | jq -r '.all // false')" = "true" ]; then
  SECRET_SCAN="$SECRET_SCAN
$(git -C "$PROJECT_DIR" diff -U0 2>/dev/null)"
else
  while IFS= read -r _path; do
    [ -z "$_path" ] && continue
    SECRET_SCAN="$SECRET_SCAN
$(git -C "$PROJECT_DIR" diff -U0 -- "$_path" 2>/dev/null)"
  done < <(echo "$COMMIT_INFO" | jq -r '.paths[]?')
fi
if echo "$SECRET_SCAN" | grep -qE "$SECRET_PATTERNS"; then
  echo "Blocked: secret pattern detected in staged content (AGENTS.md Coding Rules item 1)." >&2
  echo "Inspect: git diff --cached" >&2
  exit 2
fi

if ! BRANCH=$(git -C "$ACTUAL_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null); then
  BRANCH="unknown"
fi
BRANCH=$(printf '%s\n' "$BRANCH" | head -1)
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')
STATE_DIR="$ACTUAL_ROOT/.codex/state"
MARKER="$STATE_DIR/last-verification.$BRANCH_SAFE"
CHECKER="$ACTUAL_ROOT/scripts/meta/completion-checker.sh"
MAX_AGE=600

mkdir -p "$STATE_DIR"

NEEDS_VERIFICATION=0
if [ ! -f "$MARKER" ]; then
  NEEDS_VERIFICATION=1
else
  MARKER_MTIME=$(stat -c %Y "$MARKER" 2>/dev/null) || NEEDS_VERIFICATION=1
  if [ "$NEEDS_VERIFICATION" -eq 0 ]; then
    MARKER_AGE=$(( $(date +%s) - MARKER_MTIME ))
    [ "$MARKER_AGE" -gt "$MAX_AGE" ] && NEEDS_VERIFICATION=1
  fi
fi

if [ "$NEEDS_VERIFICATION" -eq 1 ]; then
  # Fail closed: never run the checker inside the hook — its runtime exceeds
  # the PreToolUse timeout budget (hooks.json), so an in-hook run can be
  # killed mid-flight and the gate outcome would depend on harness timeout
  # semantics. Block immediately and print the exact command instead.
  echo "Blocked: verification marker is stale or missing for branch '$BRANCH'." >&2
  if [ -f "$CHECKER" ]; then
    echo "Run verification, then retry the commit:" >&2
    echo "  CODEX_PROJECT_DIR=\"$ACTUAL_ROOT\" bash \"$CHECKER\"" >&2
    echo "(On success it records the marker: $MARKER)" >&2
  else
    echo "Verification helper missing: $CHECKER" >&2
    echo "Run your project verification, then create the marker: touch \"$MARKER\"" >&2
  fi
  exit 2
fi

SCORER="$ACTUAL_ROOT/.refine/score.sh"
REFINE_MARKER="$STATE_DIR/refinement-active"
if [ -f "$SCORER" ] && [ ! -f "$REFINE_MARKER" ]; then
  STAGED_COUNT=$(git -C "$ACTUAL_ROOT" diff --cached --name-only | wc -l | tr -d ' ')
  if [ "$STAGED_COUNT" -ge 2 ]; then
    echo "WARNING: $STAGED_COUNT files staged but refine loop marker is not active." >&2
    echo "AGENTS.md recommends refine for meaningful multi-file changes when scorer exists." >&2
  fi
fi

# AUD-2026-031: Coupling: reminder for multi-file commits (non-blocking).
# commit-discipline §2 mirror. Codex parity for reminder gate.
STAGED_COUNT_L3=$(git -C "$ACTUAL_ROOT" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
if [ "$STAGED_COUNT_L3" -ge 2 ]; then
  COMMIT_MSG=$(echo "$COMMAND" | grep -oE -- '-m[[:space:]]+"[^"]*"' | head -1 | sed -E 's/^-m[[:space:]]+"//; s/"$//')
  if [ -n "$COMMIT_MSG" ] && ! echo "$COMMIT_MSG" | grep -qE '^[[:space:]]*Coupling:'; then
    echo "REMINDER: $STAGED_COUNT_L3 files staged but commit message lacks 'Coupling:' line." >&2
    echo "commit-discipline §2 mirror: bundled commits state coupling reason. Add 'Coupling: <reason>' if intentional bundle." >&2
  fi
fi

exit 0
