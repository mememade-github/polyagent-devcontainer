# CLAUDE.md — Project Workspace

## Identity

- **Workspace**: `/workspaces/`
- **Environment**: Dev Container (Ubuntu 22.04, user=vscode)

## Project Structure

```
/workspaces/                        # Project root
├── CLAUDE.md                       # Governance rules (this file)
├── PROJECT.md                      # Domain context (customize per project)
├── REFERENCE.md                    # Commands and procedures
├── .claude/                        # Claude Code agent system
│   ├── settings.json               # Hooks & environment
│   ├── agents/                     # 2 agents (evaluator, wip-manager)
│   ├── hooks/                      # 4 hook scripts
│   ├── skills/                     # 3 /command skills (refine, status, verify)
│   ├── rules/                      # Standard rules (portable)
│   └── rules/project/              # Project-specific rules
├── .devcontainer/                  # Container configuration
│   ├── Dockerfile                  # Image (Claude Code + Python/Serena + tools)
│   ├── docker-compose.yml          # Service + ports + volumes
│   ├── devcontainer.json           # VS Code integration + lifecycle
│   ├── setup-env.sh                # postCreateCommand
│   └── .env                        # ALL user configuration
└── src/                            # Source code (your project)
```

## Template Hierarchy

This repository is a **Tier 1 base template**. All Claude DevContainer projects are derived from this template.

| Tier | Role | Includes |
|------|------|----------|
| **Tier 1** | Base template (this repo) | 2 agents, 4 hooks, 3 skills, DevContainer infrastructure |
| **Domain** | Tier 1 + domain-specific features | Derived projects add as needed |

### Elements NOT included in Tier 1

Data managed independently per project (not a sync target):
- Project-specific rules in `rules/project/`

## Core Principle: INTEGRITY

**Every claim must be verified by execution before statement.**

- Don't say "tests pass" without running them
- Don't say "build succeeds" without building
- Don't say "works" without testing

## Destructive Operations (APPROVAL REQUIRED)

Never execute without explicit user approval:
`rm -rf`, `mv`/`cp` (overwrite), `git push --force`, `git reset --hard`, `DROP`/`DELETE` (DB)

## Automated Workflow (MANDATORY)

These rules are enforced automatically by hooks. No user commands required.

### 1. Session Start (automated by SessionStart hook)

- Hook injects: current branch, active WIP tasks, environment info
- **If WIP tasks exist**: Immediately read the WIP README.md and resume work.
  Do NOT wait for user instruction — report status and continue the task.
- **If no WIP**: Report readiness and wait for user instruction.
- **Always**: Check auto memory (MEMORY.md) for Known Issues.

### 2. Change Evaluation

- **Meaningful changes**: use `/refine` — evaluation is structural
  (modify → evaluate → keep/discard loop). Not optional.
- **Trivial changes** (typo, single config line): direct edit, no evaluation needed.
- Never self-evaluate. Delegate to **evaluator** agent.

### 3. Pre-Commit Gate (automated by pre-commit-gate.sh)

Before ANY `git commit`:
1. Run verification for affected code (auto-detected by file type)
2. All checks MUST pass before commit. No `--no-verify`.

### 4. Multi-Session Tasks

- Tasks likely to span sessions → create WIP via **wip-manager** agent
- WIP location: `wip/task-YYYYMMDD-description/README.md`
- Auto-resume at next session start
- Delete WIP directory when task is complete

### 5. Agent Delegation

| Agent | Invocation |
|-------|-----------|
| evaluator | After changes (1-pass review); within /refine loop |
| wip-manager | When task spans sessions |

## Coding Rules

1. **Read first** — Read existing code before modifying
2. **Keep it simple** — Minimum code for the task
3. **Follow patterns** — Match existing codebase style
4. **Protect secrets** — Never commit credentials or API keys
5. **Verify** — Build and test before claiming success
6. **Fix root causes** — Diagnose and fix the root cause. No workarounds, no ignoring errors
7. **Explicit failure** — Every operation must genuinely succeed or explicitly fail. No arbitrary success

## Communication

- **Language**: Always respond to users in Korean.

## Environment

- **Ports**: Managed in `.devcontainer/.env` (PORT_APP, PORT_API, PORT_DB, PORT_EXTRA)
- **Claude Code**: Native binary (~/.local/bin/claude, auto-updated)
- **Node.js**: Node 22 LTS always installed for MCP infrastructure. Additional version installed if PROJECT_NODE_VERSION is set
- **Persistent volumes**: `~/.claude` (auth tokens), `/commandhistory` (history)
- **9p mount**: `core.filemode=false` (auto-applied by postStartCommand)
- **MCP**: Context7 (documentation), Serena (code intelligence) — plugins auto-managed

## Extended Reference

@PROJECT.md
@REFERENCE.md

---

*Last updated: 2026-03-22*
