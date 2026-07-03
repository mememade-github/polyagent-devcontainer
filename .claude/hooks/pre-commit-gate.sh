#!/bin/bash
# PreToolUse hook (matcher: Bash): Enforce pre-commit verification gate
# Intercepts `git commit` commands and blocks unless verification was run recently.
# Uses exit code 2 + stderr for reliable blocking per official docs:
#   "Exit 2 means a blocking error. stderr text is fed back to Claude."
# Reference: https://code.claude.com/docs/en/hooks#exit-code-output
#
# Marker file: created by completion-checker.sh at ACTUAL_ROOT/.claude/.last-verification.$BRANCH_SAFE
#
# Scope (deliberate): this gate stops the COMMON accidental bypass — `--no-verify`
# / `-n` on a real `git commit` — quoting-aware so a commit MESSAGE mentioning the
# flag is not a false positive, and separator-aware so a `-n` on an adjacent
# command (git commit -m x && git log -n 5) is not matched. It does NOT chase
# exotic shell evasions (nested `sh -c`, process substitution, env overrides,
# xargs/flock wrappers): per REFERENCE.md the container is a workspace boundary,
# not a trust boundary — an agent that owns the shell can always skip a
# self-imposed gate, so completeness there is unwinnable and not worth the
# complexity. The load-bearing enforcement is the fail-closed verification
# marker below, which no argument spelling can bypass.

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
            skip = True          # value is the next token
            continue
        if a.startswith("--"):
            continue             # other long opt (incl. --opt=value)
        if a.startswith("-") and a != "-":
            rest = a[1:]
            for k, c in enumerate(rest):
                if c == "n":
                    no_verify = True
                elif c == "a":
                    all_ = True
                if c in value_short:
                    # A value-taking short opt consumes the remainder of the
                    # cluster as its value; only if it is the LAST char is the
                    # value the next token. Either way, stop scanning — trailing
                    # chars are message text, not flags.
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

# Only intercept git commit commands (not git add, git status, etc.)
if [ "$(echo "$COMMIT_INFO" | jq -r '.found // false')" != "true" ]; then
  exit 0
fi

# AUD-2026-029: block --no-verify and its short alias -n on git commit.
if [ "$(echo "$COMMIT_INFO" | jq -r '.no_verify // false')" = "true" ]; then
  echo "Blocked: --no-verify/-n bypass is not permitted (project pre-commit gate)." >&2
  echo "Fix verification issues before committing — do not skip the gate." >&2
  exit 2
fi

# Target the repo git will actually commit: the parser resolved it from any
# `git -C <path>`. Per-worktree on purpose — the marker lives in the worktree
# being committed (the same locus completion-checker.sh derives), so a
# session-root locus would deadlock worktree commits.
PROJECT_DIR=$(echo "$COMMIT_INFO" | jq -r '.workdir')
ACTUAL_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_DIR")

# AUD-2026-030: secret-pattern scan on staged content. project coding rules "Protect secrets".
# Extends pre-push-gate.sh Layer 1 (which only scans remote URL) to scan staged file content.
# git commit -a auto-stages tracked mods at commit time and `git commit <path>` commits the
# working-tree version, so scan --cached plus the extra diff each form will pull in.
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
  echo "Blocked: secret pattern detected in staged content." >&2
  echo "Inspect: git diff --cached" >&2
  echo "If false positive (e.g. regex literal in documentation), inspect manually and decide whether to amend or document the exception." >&2
  exit 2
fi

# resolve branch name for per-worktree marker isolation
if ! BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null); then
  BRANCH="unknown"
fi
BRANCH=$(printf '%s\n' "$BRANCH" | head -1)
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

MARKER="$ACTUAL_ROOT/.claude/.last-verification.$BRANCH_SAFE"
MAX_AGE=600  # 10 minutes

NEEDS_VERIFICATION=0

if [ ! -f "$MARKER" ]; then
  NEEDS_VERIFICATION=1
else
  MARKER_MTIME=$(stat -c %Y "$MARKER" 2>/dev/null) || NEEDS_VERIFICATION=1
  if [ "$NEEDS_VERIFICATION" -eq 0 ]; then
    MARKER_AGE=$(( $(date +%s) - MARKER_MTIME ))
    if [ "$MARKER_AGE" -gt "$MAX_AGE" ]; then
      NEEDS_VERIFICATION=1
    fi
  fi
fi

if [ "$NEEDS_VERIFICATION" -eq 1 ]; then
  # Fail closed: never run the checker inside the hook — its runtime exceeds
  # the PreToolUse timeout budget (settings.json), so an in-hook run can be
  # killed mid-flight and the gate outcome would depend on harness timeout
  # semantics. Block immediately and print the exact command instead.
  CHECKER="$ACTUAL_ROOT/scripts/meta/completion-checker.sh"
  echo "Blocked: verification marker is stale or missing for branch '$BRANCH'." >&2
  if [ -f "$CHECKER" ]; then
    echo "Run verification, then retry the commit:" >&2
    echo "  CLAUDE_PROJECT_DIR=\"$ACTUAL_ROOT\" bash \"$CHECKER\"" >&2
    echo "(On success it records the marker: $MARKER)" >&2
  else
    echo "Run verification before committing:" >&2
    echo "1. Python: ruff check src/ && mypy src/ --ignore-missing-imports" >&2
    echo "2. TypeScript: pnpm build" >&2
    echo "3. Or run: your project verification script (see project governance docs)" >&2
    echo "Then create the marker: mkdir -p '$ACTUAL_ROOT/.claude' && touch '$MARKER'" >&2
  fi
  exit 2
fi

# --- Layer 2: /refine requirement check for multi-file changes ---
SCORER="$ACTUAL_ROOT/.refine/score.sh"
REFINE_MARKER="$ACTUAL_ROOT/.claude/.refinement-active"
if [ -f "$SCORER" ] && [ ! -f "$REFINE_MARKER" ]; then
  STAGED_COUNT=$(git -C "$PROJECT_DIR" diff --cached --name-only | wc -l)
  if [ "$STAGED_COUNT" -ge 2 ]; then
    echo "WARNING: $STAGED_COUNT files staged but /refine is not active." >&2
    echo "Project automated workflow requires /refine for changes affecting 2+ files when scorer exists." >&2
    echo "Consider running /refine instead of direct commit." >&2
    # WARNING only, not blocking — agent can proceed with justification
  fi
fi

# --- Layer 3: Coupling: reminder for multi-file commits (AUD-2026-031, non-blocking) ---
# commit-discipline §2 requires explicit "Coupling:" line when bundling orthogonal concerns.
# Tooling cannot mechanically determine orthogonality, so this is a reminder gate, not enforcement.
STAGED_COUNT_L3=$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null | wc -l)
if [ "$STAGED_COUNT_L3" -ge 2 ]; then
  # Extract -m message if present in the command. Limitation: only the first -m argument is inspected;
  # commit via editor (no -m) bypasses this reminder. Acceptable trade-off — reminder, not enforcement.
  COMMIT_MSG=$(echo "$COMMAND" | grep -oE -- '-m[[:space:]]+"[^"]*"' | head -1 | sed -E 's/^-m[[:space:]]+"//; s/"$//')
  if [ -n "$COMMIT_MSG" ] && ! echo "$COMMIT_MSG" | grep -qE '^[[:space:]]*Coupling:'; then
    echo "REMINDER: $STAGED_COUNT_L3 files staged but commit message lacks 'Coupling:' line." >&2
    echo "commit-discipline §2: bundled commits must state coupling reason. Add 'Coupling: <reason>' line if files are intentionally bundled." >&2
    echo "(reminder only, not blocking — single-concern multi-file commits are legitimate)" >&2
  fi
fi

# Verification is recent — allow commit
exit 0
