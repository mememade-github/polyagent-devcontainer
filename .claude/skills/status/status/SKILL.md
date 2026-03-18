---
name: status
description: Show workspace status - all git repos, services, WIP tasks, and environment health
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep
---

Show the current workspace status by running these steps:

## 1. Git Repos
Find all git repositories in the workspace:
```bash
find "$CLAUDE_PROJECT_DIR" -name ".git" -type d -maxdepth 4 | while read gitdir; do
  REPO=$(dirname "$gitdir")
  echo "$REPO: $(git -C "$REPO" branch --show-current) | dirty=$(git -C "$REPO" status --porcelain | wc -l)"
done
```

## 2. Unpushed Commits
For each repo with a remote, check:
```bash
git -C <repo> log --oneline @{u}..HEAD 2>/dev/null
```
Flag any repo with unpushed commits.

## 3. WIP Tasks
Check for active WIP tasks: `ls $CLAUDE_PROJECT_DIR/wip/ 2>/dev/null`
If WIP directories exist, read each README.md to show current task status.

## 4. Active Plans
Check `~/.claude/plans/` for plan files. Show name and age of each.

## 5. Stale Markers
- `.claude/.pending-review` — show file list if exists
- `.claude/.last-verification` — show age

## 6. Summary
Summarize findings concisely: repos status, unpushed count, WIP count, stale items.
