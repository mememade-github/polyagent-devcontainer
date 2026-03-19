# Collaboration Protocol — Multi-Worker Git Strategy

> Two or more workers (human or Claude Code sessions) working on the same repository.
> Prevents git conflicts through isolation, visibility, and structured integration.

## Fundamental Rules

1. **Never commit directly to `main`** — all work on worker branches.
2. **One worker per worktree** — never run two sessions in the same worktree.
3. **Check before editing** — verify no other active session is working on the same files.

## Why One Worker Per Worktree?

Git tracks changes at the working tree level. Two sessions editing the same worktree cause:
- **Unstaged change collision**: session A edits file X, session B overwrites it
- **Staging area conflict**: both sessions `git add` different versions
- **Tool call race**: Edit tool's `old_string` matching breaks on concurrent modification

**If you need a second worker**: create a second worktree, not a second session in the same one.

## Session Detection (Automatic)

Active sessions are detected automatically — no manual registration required.

**Mechanism**: `worker-guard.sh` uses two data sources:
1. `git worktree list` — all worktree paths and branches (git-managed, always accurate)
2. Per-worktree `.claude/.heartbeat` mtime — heartbeat (written by `observe.sh` to `PROJECT_DIR`)

A session is considered **active** if its `.heartbeat` was modified within the last 10 minutes.

**Why this works**:
- `observe.sh` runs on every PreToolUse/PostToolUse (registered in settings.json)
- It touches `.claude/.heartbeat` in the current worktree's `PROJECT_DIR` (not `ACTUAL_ROOT`)
- Each worktree gets its own heartbeat file — no cross-worktree false positives
- No registration/deregistration needed — no stale files on crash
- `git worktree list` includes the main working directory, so non-worktree sessions are detected too

**Key distinction**: `observations.jsonl` is centralized at `ACTUAL_ROOT` (shared for learning).
`.heartbeat` is per-worktree at `PROJECT_DIR` (isolated for session detection).

## Worker Lifecycle

### 1. Start: Create Worktree + Branch

```bash
# From the project root (where .git/ lives)
WORKER_NAME="alpha"  # unique per worker
git worktree add .claude/worktrees/${WORKER_NAME} -b worktree-${WORKER_NAME}
```

Session detection begins automatically once the session's first tool call triggers `observe.sh`.

### 2. Sync: Rebase onto Main Periodically

```bash
# In your worktree directory
git fetch origin main
git rebase origin/main
```

Do this before starting new work and before finishing.

### 3. Finish: Merge + Cleanup

```bash
# 1. Final rebase
git rebase main

# 2. Merge to main (fast-forward only)
git checkout main
git merge --ff-only worktree-${WORKER_NAME}

# 3. Remove worktree
git worktree remove .claude/worktrees/${WORKER_NAME}
git branch -d worktree-${WORKER_NAME}
```

No deregistration step needed — worktree removal makes `git worktree list` stop listing it.

## Conflict Prevention

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

| File Pattern | Why Safe |
|--------------|----------|
| Independent sub-repositories | Separate git history, no merge conflicts |
| `.claude/agent-memory/` | Per-agent, no cross-reference |
| `.claude/instincts/` | Append-only observations |
| Test files not shared across modules | Isolated by design |

## Session-Start Integration

At session start, the `worker-guard` hook automatically:
1. Enumerates all worktrees via `git worktree list`
2. Checks each worktree's `observations.jsonl` mtime for activity
3. Reports active sessions (within 10-minute heartbeat window)
4. Warns if the current session's worktree branch diverges from main

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
