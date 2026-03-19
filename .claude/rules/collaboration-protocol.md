# Collaboration Protocol — Multi-Worker Git Strategy

> Two or more workers (human or Claude Code sessions) working on the same repository.
> Prevents git conflicts through isolation, visibility, and structured integration.

## Fundamental Rules

1. **Never commit directly to `main`** — all work on worker branches.
2. **One worker per worktree** — never run two sessions in the same worktree.
3. **Declare before editing** — update your worker file before touching shared files.

## Why One Worker Per Worktree?

Git tracks changes at the working tree level. Two sessions editing the same worktree cause:
- **Unstaged change collision**: session A edits file X, session B overwrites it
- **Staging area conflict**: both sessions `git add` different versions
- **Tool call race**: Edit tool's `old_string` matching breaks on concurrent modification

**If you need a second worker**: create a second worktree, not a second session in the same one.

## Worker Lifecycle

### 1. Start: Create Worktree + Branch

```bash
# From the project root (where .git/ lives)
WORKER_NAME="alpha"  # unique per worker
git worktree add .claude/worktrees/${WORKER_NAME} -b worktree-${WORKER_NAME}
```

Register the worker (enables visibility for other sessions):

```bash
PROJECT_KEY=$(pwd | md5sum | cut -c1-12)
WORKER_DIR="$HOME/.claude/workers/${PROJECT_KEY}"
mkdir -p "$WORKER_DIR"
cat > "$WORKER_DIR/worker-${WORKER_NAME}.json" <<EOF
{
  "name": "${WORKER_NAME}",
  "branch": "worktree-${WORKER_NAME}",
  "worktree": "$(pwd)/.claude/worktrees/${WORKER_NAME}",
  "project_root": "$(pwd)",
  "started": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "working_on": "",
  "files": []
}
EOF
```

### 2. Work: Declare What You're Doing

Before starting a task, update the worker file:

```bash
# Update working_on and files fields
WORKER_FILE="$HOME/.claude/workers/${PROJECT_KEY}/worker-${WORKER_NAME}.json"
tmp=$(mktemp)
jq --arg desc "status skill 수정" --argjson files '[".claude/skills/status/", "scripts/git/"]' \
  '.working_on = $desc | .files = $files' "$WORKER_FILE" > "$tmp" && mv "$tmp" "$WORKER_FILE"
```

### 3. Sync: Rebase onto Main Periodically

```bash
# In your worktree directory
git fetch origin main
git rebase origin/main
```

Do this before starting new work and before finishing.

### 4. Finish: Merge + Cleanup

```bash
# 1. Final rebase
git rebase main

# 2. Merge to main (fast-forward only)
git checkout main
git merge --ff-only worktree-${WORKER_NAME}

# 3. Remove worktree
git worktree remove .claude/worktrees/${WORKER_NAME}
git branch -d worktree-${WORKER_NAME}

# 4. Deregister worker
rm "$HOME/.claude/workers/${PROJECT_KEY}/worker-${WORKER_NAME}.json"
```

## Conflict Prevention

### File Ownership Declaration

Before editing files, check if another worker has declared those files:

```bash
# Check all active workers in this project
for f in "$HOME/.claude/workers/${PROJECT_KEY}"/worker-*.json; do
  [ -f "$f" ] || continue
  OTHER=$(jq -r '.name' "$f")
  [ "$OTHER" = "$WORKER_NAME" ] && continue
  FILES=$(jq -r '.files[]' "$f" 2>/dev/null)
  echo "Worker $OTHER is working on: $FILES"
done
```

**If overlap detected**: coordinate with the other worker before proceeding.

### High-Risk Files (serialize, don't parallelize)

These files change frequently and cause merge conflicts:

| File | Risk | Strategy |
|------|------|----------|
| `CLAUDE.md` | HIGH | One worker at a time |
| `PROJECT.md` | HIGH | One worker at a time |
| `.claude/settings.json` | HIGH | One worker at a time |
| `.claude/agents/*.md` | MEDIUM | Declare specific agent file |
| `.claude/rules/*.md` | MEDIUM | Declare specific rule file |

### Low-Risk Files (safe to parallelize)

| File | Why Safe |
|------|----------|
| `products/root/*` | Independent repos |
| `products/derived/*` | Independent repos |
| `.claude/agent-memory/` | Per-agent, no cross-reference |
| `.claude/instincts/` | Append-only observations |

## Session-Start Integration

At session start, the `worker-guard` hook automatically:
1. Lists all active workers in the current project
2. Shows what they're working on and which files they declared
3. Warns if the current session's worktree branch diverges from main

## Merge Conflict Resolution

If `git rebase main` produces conflicts:

1. **Identify conflicting files**: `git diff --name-only --diff-filter=U`
2. **Check who modified**: `git log --oneline main..HEAD -- <file>`
3. **Resolve**: prefer the more recent logical change
4. **Continue**: `git rebase --continue`
5. **Never**: `git rebase --abort` and silently drop changes

## Worker Naming Convention

| Worker | Name | Branch |
|--------|------|--------|
| Human (primary) | `alpha` | `worktree-alpha` |
| Claude Code session 1 | `bravo` | `worktree-bravo` |
| Claude Code session 2 | `charlie` | `worktree-charlie` |

## Applicability

This protocol applies to **every project** with `.claude/` configuration.
