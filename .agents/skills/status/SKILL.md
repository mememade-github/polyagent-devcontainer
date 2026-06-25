---
name: status
description: Show current-repository status, WIP tasks, and environment health
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep
---

Show the current workspace status by running these steps:

## 0. Workspace Root Resolution
Resolve the project root and vendor state directory:
```bash
WORKSPACE_ROOT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  STATE_DIR="$WORKSPACE_ROOT/.claude"
  MARKER_PREFIX=".last-verification."
elif [ -n "${CODEX_PROJECT_DIR:-}" ] || [ "${CODEX_CI:-}" = "1" ] || [ -n "${CODEX_THREAD_ID:-}" ]; then
  STATE_DIR="$WORKSPACE_ROOT/.codex/state"
  MARKER_PREFIX="last-verification."
else
  case "${AGENT_VENDOR:-}" in
    claude) STATE_DIR="$WORKSPACE_ROOT/.claude"; MARKER_PREFIX=".last-verification." ;;
    codex) STATE_DIR="$WORKSPACE_ROOT/.codex/state"; MARKER_PREFIX="last-verification." ;;
    *) echo "ERROR: cannot identify Claude or Codex host; set AGENT_VENDOR=claude|codex" >&2; exit 2 ;;
  esac
fi
echo "Workspace root: $WORKSPACE_ROOT ($STATE_DIR)"
```
Use `$WORKSPACE_ROOT` for ALL subsequent paths.

## 1. Git Repos
Delegate to the canonical single-repository status script:
```bash
bash "$WORKSPACE_ROOT/scripts/git/git-status.sh" --brief
```
Derived multi-repository workspaces may replace that script with their own
enumerator; this base template reports the current repository only.

## 2. Unpushed Commits
The canonical script already reports commits ahead of the configured upstream.
If no upstream exists, report that explicitly rather than treating it as zero.
```bash
git -C "$WORKSPACE_ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null \
  || echo "No upstream configured"
```
Flag any repo with unpushed commits.

## 3. Active Worktrees
List git worktrees (Claude Code `--worktree` creates these automatically):
```bash
git -C "$WORKSPACE_ROOT" worktree list 2>/dev/null | while IFS= read -r line; do
  WT_PATH=$(echo "$line" | awk '{print $1}')
  WT_BRANCH=$(echo "$line" | sed -n 's/.*\[\(.*\)\]/\1/p')
  echo "  ${WT_BRANCH} (${WT_PATH})"
done
```

## 4. WIP Tasks
Check for active WIP tasks: `ls "$WORKSPACE_ROOT/wip/" 2>/dev/null`
If WIP directories exist, read each README.md to show current task status.

## 5. Stale Markers
Check for branch-scoped verification markers:
```bash
for marker in "$STATE_DIR"/"$MARKER_PREFIX"*; do
  [ -f "$marker" ] || continue
  AGE=$(( $(date +%s) - $(stat -c '%Y' "$marker" 2>/dev/null || echo 0) ))
  echo "  $(basename "$marker") — ${AGE}s ago"
done
```

## 6. Summary
Summarize findings concisely: repos status, unpushed count, WIP count, stale items.
