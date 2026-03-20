---
name: status
description: Show workspace status - all git repos, services, WIP tasks, and environment health
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep
---

Show the current workspace status by running these steps:

## 0. Workspace Root Resolution
Resolve the actual workspace root (handles both direct and worktree execution):
```bash
WORKSPACE_ROOT=$(git rev-parse --git-common-dir 2>/dev/null | xargs dirname)
if [ -z "$WORKSPACE_ROOT" ] || [ "$WORKSPACE_ROOT" = "." ]; then
  WORKSPACE_ROOT="${CLAUDE_PROJECT_DIR:-.}"
fi
echo "Workspace root: $WORKSPACE_ROOT"
```
Use `$WORKSPACE_ROOT` for ALL subsequent paths.

## 1. Git Repos
Delegate to the canonical git-status script (single source of truth for repo enumeration):
```bash
"$WORKSPACE_ROOT/scripts/git/git-status.sh" --brief
```
This covers root, products/root/*, products/derived/*, and nested repos within derived projects.

## 2. Unpushed Commits
For each repo with a remote, check:
```bash
find "$WORKSPACE_ROOT/products" -name ".git" -type d -maxdepth 5 2>/dev/null | while read gitdir; do
  REPO=$(dirname "$gitdir")
  UNPUSHED=$(git -C "$REPO" log --oneline @{u}..HEAD 2>/dev/null)
  if [ -n "$UNPUSHED" ]; then
    echo "=== $REPO ==="
    echo "$UNPUSHED"
  fi
done
```
Flag any repo with unpushed commits.

## 3. Active Sessions
Detect active sessions via per-worktree `.heartbeat` (consistent with worker-guard.sh and collaboration-protocol.md):
```bash
NOW=$(date +%s)
TIMEOUT=600
git -C "$WORKSPACE_ROOT" worktree list 2>/dev/null | while IFS= read -r line; do
  WT_PATH=$(echo "$line" | awk '{print $1}')
  WT_BRANCH=$(echo "$line" | sed -n 's/.*\[\(.*\)\]/\1/p')
  HB="$WT_PATH/.claude/.heartbeat"
  if [ -f "$HB" ]; then
    AGE=$(( NOW - $(stat -c '%Y' "$HB" 2>/dev/null || echo 0) ))
    if [ "$AGE" -lt "$TIMEOUT" ]; then
      echo "  ${WT_BRANCH} (${WT_PATH}) — active ${AGE}s ago"
    else
      echo "  ${WT_BRANCH} (${WT_PATH}) — inactive (${AGE}s)"
    fi
  else
    echo "  ${WT_BRANCH} (${WT_PATH}) — no heartbeat"
  fi
done
```

## 4. WIP Tasks
Check for active WIP tasks: `ls "$WORKSPACE_ROOT/wip/" 2>/dev/null`
If WIP directories exist, read each README.md to show current task status.

## 5. Active Plans
Check `~/.claude/plans/` for plan files. Show name and age of each.

## 6. Stale Markers
- `$WORKSPACE_ROOT/.claude/.pending-review` — show file list if exists
- `$WORKSPACE_ROOT/.claude/.last-verification` — show age

## 7. Summary
Summarize findings concisely: repos status, unpushed count, WIP count, stale items.
