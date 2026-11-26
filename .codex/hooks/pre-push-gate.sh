#!/bin/bash
# PreToolUse hook: git push safety gate for the Codex harness — a policy
# tripwire, not a security sandbox (mirror of the Claude gate). It reads the
# command TEXT; it does not work out what the shell will actually run.
# Exit codes:
#   2  blocked: a positive match below (stderr is the reason).
#   0  not blocked: checked with no match, not a push-shaped command, or not
#      checked. This is not an approval and not evidence that the command is
#      safe. "Not checked" means a step the result depends on failed (input
#      unreadable or not JSON, no command in it, jq/git missing, sed/grep/git
#      config error, no repository found for a push-shaped command, or an
#      approval marker used but not removed); the gate then writes one line
#      "pre-push gate: not checked: <cause>" to stderr.
#      The Codex hooks documentation defines only exit 0 and exit 2 for
#      PreToolUse, so on Codex an unchecked command also exits 0 and still
#      runs (fail-open is unchanged).
#
# Blocks:
#  1. Force-push text (--force / -f / +refspec) after an unquoted standalone
#     `push` word, up to the next ; | & ( ) or newline, without a single-use
#     approval marker in the target repo root
#     (.codex/state/allow-force-push.<remote>.<branch>),
#     consumed on allow. Matching is on the text with quoted spans removed:
#     force text inside quotes is ignored, but an unquoted `git push --force`
#     blocks even where it is only printed (e.g. `echo git push --force ...`),
#     while a push hidden in a variable, eval, alias or script file is not seen.
#     <remote> is the first non-option word after `push` in the first such
#     span, else the upstream's remote, else origin. <branch> is the branch
#     currently checked out in the target repo, as `git rev-parse --abbrev-ref
#     HEAD` prints it (HEAD when detached or before the first commit, unknown
#     when it prints nothing),
#     not the refspec named in the command. These fallbacks define the scope:
#     no upstream (or an unreadable one) means origin. The marker name turns
#     each run of characters outside [A-Za-z0-9._-] into `_`, so names such as
#     feature/a and feature_a share one marker.
#     Decision: --force-with-lease passes WITHOUT a marker — it is the
#     narrower alternative and fails
#     instead of clobbering remote work it has not seen.
#  2. Credential-looking secret in the raw command text of ANY command.
#     Accepted cost: token-shaped fixture/doc text inline in a command also
#     blocks — keep such strings in files.
#  3. Stored-config credential visible from the resolved target repo:
#     remote/url/credential config values carrying a literal token or
#     user:pass@. A helper value that only references a shell variable
#     (e.g. "password=${GITHUB_PAT}") is the sanctioned pattern and passes.
set -uf

not_checked() { echo "pre-push gate: not checked: $1" >&2; exit 0; }
# match <regex> <text>: grep -Eq, where an exit above 1 is a grep error, not "no match".
match() { printf '%s' "$2" | grep -Eq "$1"; local rc=$?; [ "$rc" -le 1 ] || not_checked "grep exited $rc"; return "$rc"; }

INPUT=$(cat) || not_checked "could not read the hook input"
command -v jq >/dev/null 2>&1 || not_checked "jq not found"
command -v git >/dev/null 2>&1 || not_checked "git not found"
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || not_checked "jq could not read the hook input as JSON"
[ -n "$COMMAND" ] || not_checked "no tool_input.command in the hook input"

# Block 2: credential-looking secret in the raw command text.
CRED_RE='ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{16,}|oauth2:[^@[:space:]]+@|x-access-token:[^@[:space:]]+@|[A-Za-z][A-Za-z0-9+.-]*://[^/@:[:space:]]+:[^/@[:space:]]+@'
if match "$CRED_RE" "$COMMAND"; then
  echo "Blocked: the command text matches a credential-looking secret." >&2
  echo "Keep tokens in gitignored files; supply them via a credential helper at call time." >&2
  exit 2
fi

# Everything below applies only to `git ... push` text at the start or after
# ; | & ( or whitespace, in a view with quoted spans removed: text inside
# quotes is ignored, while unquoted push text matches even as an argument.
QUOTELESS=$(printf '%s' "$COMMAND" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g") || not_checked "sed failed"
match '(^|[;&|([:space:]])git[[:space:]]([^;|&]*[[:space:]])?push([[:space:];|&)]|$)' "$QUOTELESS" || exit 0

# Resolve the target repo: `git -C <path>` up to the first space ; | or &,
# quotes removed (a path with a space is cut there; the repo containing the cut
# path is used, or none is found and it is not checked), else the session dir.
TARGET_DIR=$(printf '%s' "$COMMAND" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:];|&]+).*/\1/p') || not_checked "sed failed"
TARGET_DIR=${TARGET_DIR%%$'\n'*}
TARGET_DIR=${TARGET_DIR//[\"\']/}; case "$TARGET_DIR" in '$PWD'|'${PWD}'|'$(pwd)') TARGET_DIR=$PWD ;; '$CODEX_PROJECT_DIR'|'${CODEX_PROJECT_DIR}') TARGET_DIR="${CODEX_PROJECT_DIR:-.}" ;; esac
[ -n "$TARGET_DIR" ] || TARGET_DIR="${CODEX_PROJECT_DIR:-.}"
REPO_ROOT=$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null) || not_checked "no git repository found at $TARGET_DIR"

# Block 3: stored-config credential (remote URLs, credential-helper values).
# git config exits 1 when no key matches; any other non-zero status is an error.
CONFIG=$(git -C "$REPO_ROOT" config --get-regexp '^(remote\.|credential\.|url\.)' 2>/dev/null); rc=$?
[ "$rc" -le 1 ] || not_checked "git config exited $rc"
STORED=$(printf '%s\n' "$CONFIG" | grep -E "$CRED_RE"); rc=$?
[ "$rc" -le 1 ] || not_checked "grep exited $rc"
if [ -n "$STORED" ]; then
  echo "Blocked: git config visible from $REPO_ROOT stores a literal credential in:" >&2
  KEYS=$(printf '%s\n' "$STORED" | awk '!seen[$1]++ {print "  " $1}') || KEYS="  (could not list the keys: awk failed)"
  printf '%s\n' "$KEYS" >&2
  echo "Fix: keep remote URLs clean; let a credential helper read the token from a gitignored file (variable-reference helper values pass)." >&2
  exit 2
fi

# Block 1: plain force push text requires a scoped single-use marker.
SPANS=$(printf '%s' "${QUOTELESS//$'\n'/;}" | grep -oE '(^|[[:space:]])push([[:space:]][^;|&()]*|$)'); rc=$?
[ "$rc" -le 1 ] || not_checked "grep exited $rc"
TAIL=""
while IFS= read -r S; do
  match '(^|[[:space:]])(--force|-[A-Za-z]*f[A-Za-z]*|\+[A-Za-z0-9][^[:space:]]*)([[:space:]]|$)' "${S#*push}" && { TAIL=${S#*push}; break; }
done <<< "$SPANS"
[ -n "$TAIL" ] || exit 0

REMOTE=""
for w in $TAIL; do case "$w" in -*|+*) ;; *) REMOTE="$w"; break ;; esac; done
if [ -z "$REMOTE" ]; then U=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) && REMOTE=${U%%/*}; fi
[ -n "$REMOTE" ] || REMOTE=origin
BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
[ -n "$BRANCH" ] || BRANCH=unknown
R=$(printf '%s' "$REMOTE" | sed -E 's/[^A-Za-z0-9._-]+/_/g') || not_checked "sed failed"
B=$(printf '%s' "$BRANCH" | sed -E 's/[^A-Za-z0-9._-]+/_/g') || not_checked "sed failed"
MARKER="$REPO_ROOT/.codex/state/allow-force-push.${R:-unnamed}.${B:-unnamed}"
if [ -f "$MARKER" ]; then
  rm -f "$MARKER" || not_checked "approved by $MARKER, but could not remove it, so it was not consumed"
  exit 0
fi
echo "Blocked: the command text matches a force push, which requires explicit single-use approval." >&2
echo "Approval scope: remote '$REMOTE', branch '$BRANCH' (checked out in $REPO_ROOT; not read from the command's refspec)." >&2
echo "Narrower alternative: --force-with-lease passes without a marker." >&2
echo "To approve exactly once, create the marker file and retry:" >&2
echo "  mkdir -p '$REPO_ROOT/.codex/state' && touch '$MARKER'" >&2
exit 2
