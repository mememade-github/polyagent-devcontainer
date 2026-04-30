# CLAUDE.md — Project Workspace

Behavioral foundation: [`.claude/rules/behavioral-core.md`](.claude/rules/behavioral-core.md) (Karpathy 4 rules — auto-imported below).

**Karpathy skill 등재**: 동일 4-rule이 [`.claude/skills/karpathy-guidelines/`](.claude/skills/karpathy-guidelines/) 으로도 노출되어 evaluator agent / explicit invocation에서 reference handle로 사용 가능 (SKILL.md + EXAMPLES.md). Cursor parity: [`.cursor/rules/karpathy-guidelines.mdc`](.cursor/rules/karpathy-guidelines.mdc). 출처: [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (MIT).

## Identity

- **Workspace**: `/workspaces/`
- **Environment**: Dev Container (Ubuntu 22.04, user=vscode)

## Project Structure

```
/workspaces/                        # Project root
├── CLAUDE.md                       # Governance rules — Claude (this file)
├── AGENTS.md                       # Governance rules — Codex (mirror)
├── PROJECT.md                      # Domain context (customize per project)
├── REFERENCE.md                    # Commands and procedures
├── .claude/                        # Claude Code agent system (ground truth)
│   ├── settings.json               # Hooks & environment
│   ├── agents/                     # 2 agents (evaluator, wip-manager)
│   ├── hooks/                      # 6 hook scripts
│   ├── skills/                     # 4 /command skills (refine, status, verify, wiki)
│   ├── rules/                      # Standard rules (portable)
│   └── rules/project/              # Project-specific rules
├── .agents/                        # Codex agent assets (mirror of .claude/)
├── .codex/                         # Codex CLI configuration
│   ├── config.toml                 # Sandbox / approval / MCP
│   ├── hooks.json                  # Event hooks (SessionStart, PreToolUse, Stop)
│   ├── hooks/                      # 4 hook scripts
│   └── state/                      # Runtime markers (gitignored)
├── scripts/
│   └── sync-agents-mirror.sh       # .claude/ → .agents/ 단방향 동기화
├── .devcontainer/                  # Container configuration
│   ├── Dockerfile                  # Image (Claude + Codex + Python/Serena + tools)
│   ├── docker-compose.yml          # Service + ports + volumes
│   ├── devcontainer.json           # VS Code integration + lifecycle
│   ├── setup-env.sh                # postCreateCommand
│   └── .env                        # ALL user configuration
└── src/                            # Source code (your project)
```

## Template Hierarchy

This repository is a **Tier 1 base template** for multi-agent (Polyagent) workflows. All derived
projects start from this template — variants extend the base with domain-specific tooling.

| Tier | Role | Includes |
|------|------|----------|
| **Tier 1** | Base template (this repo, base variant) | 2 sub-agents, 6 hooks, 4 skills, Claude+Codex parity, DevContainer infrastructure |
| **Variant** | Tier 1 + domain extension within same repo | `variants/<name>/` with own `.devcontainer/` and project skeleton |
| **Domain** | Tier 1 (or variant) + project code | Derived projects add as needed |

### Variants in this repo

| Variant | Path | Port band | Adds |
|---------|------|:---------:|------|
| base (default) | `.devcontainer/` (root) | 31000 | (Tier 1 only) |
| datascience | `variants/datascience/` | 32000 | Jupyter, data/, models/, notebooks/, src/, tests/ |

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
- **Codex CLI**: npm global (~/.npm-global/bin/codex)
- **Node.js**: Node 22 LTS always installed for MCP infrastructure. Additional version installed if PROJECT_NODE_VERSION is set
- **Persistent volumes**: `~/.claude` (Claude auth), `~/.codex` (Codex auth), `/commandhistory` (history)
- **9p mount**: `core.filemode=false` (auto-applied by postStartCommand)
- **MCP**: Context7 (documentation), Serena (code intelligence) — plugins auto-managed

## Polyagent Parity

다중 AI 에이전트(현재 Claude Code · Codex CLI)를 동등 환경에서 병행 운영합니다.
**Ground truth는 `.claude/`이며**, 다른 vendor 측은 호환 미러로 유지됩니다.

| Vendor | Source of truth | Mirror |
|--------|----------------|--------|
| Claude Code | `CLAUDE.md`, `.claude/` | — |
| Codex CLI | (mirror) | `AGENTS.md`, `.agents/`, `.codex/` |
| (향후) Cursor/Aider 등 | (mirror) | 동일 패턴으로 추가 |

```bash
bash scripts/sync-agents-mirror.sh         # 미러 갱신 (.claude/ → .agents/)
bash scripts/sync-agents-mirror.sh --dry   # 변경 확인만
```

각 vendor 거버넌스 문서: Claude=이 파일, Codex=[AGENTS.md](AGENTS.md).

## Extended Reference

@.claude/rules/behavioral-core.md
@PROJECT.md
@REFERENCE.md

---

*Last updated: 2026-03-22*
