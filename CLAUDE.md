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
│   ├── agents/                     # 14 agents
│   ├── hooks/                      # 21 automation hooks
│   ├── skills/                     # 12 /command skills
│   ├── rules/                      # Standard rules (portable)
│   ├── rules/project/              # Project-specific rules
│   └── agent-memory/               # Per-agent cross-session memory
├── .devcontainer/                  # Container configuration
│   ├── Dockerfile                  # Image (Claude Code + Python/Serena + tools)
│   ├── docker-compose.yml          # Service + ports + volumes
│   ├── devcontainer.json           # VS Code integration + lifecycle
│   ├── setup-env.sh                # postCreateCommand
│   └── .env                        # ALL user configuration
└── src/                            # Source code (your project)
```

## Template Hierarchy

이 저장소는 **Tier 1 베이스 템플릿**입니다. 모든 Claude DevContainer 프로젝트가 이 템플릿에서 파생됩니다.

| Tier | 역할 | 포함 |
|------|------|------|
| **Tier 1** | 베이스 템플릿 (이 저장소) | 14 agents, 21 hooks, 12 skills, DevContainer 인프라 |
| **Domain** | Tier 1 + 도메인 특화 기능 | 파생 프로젝트가 필요에 따라 추가 |

### Tier 1에 포함되지 않는 요소

도메인 프로젝트에서 필요에 따라 추가하는 기능:
- evolution 시스템 (agent-evolver, observe/evolution-gate/mark-evolved hooks)
- instincts 디렉토리 및 학습 시스템
- evolution 관련 스킬 (/evolve, /learn, /instinct-status, /instinct-export, /instinct-import)
- 프로젝트별 에이전트 및 도메인 규칙

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

### 2. Code Change Cycle (Agent Teams: quality)

After completing a batch of code changes:
1. Delegate review to **code-reviewer** agent (team: quality) via Task tool
2. If reviewer finds issues → fix before proceeding
3. This step is NOT optional — skip only if changes are trivial

### 3. Pre-Commit Gate (automated by pre-commit-gate.sh)

Before ANY `git commit`:
1. Run verification for affected code (auto-detected by file type)
2. All checks MUST pass before commit. No `--no-verify`.

### 4. Multi-Session Tasks (Agent Teams: workflow)

- Tasks likely to span sessions → create WIP via **wip-manager** agent
- WIP location: `wip/task-YYYYMMDD-description/README.md`
- Auto-resume at next session start
- Delete WIP directory when task is complete

### 5. Agent Teams Delegation

| Team | Agent | Auto-trigger |
|------|-------|-------------|
| quality | code-reviewer | After code changes |
| quality | environment-checker | On env issues |
| workflow | wip-manager | When task spans sessions |

Delegation via Task tool with `subagent_type` parameter.
- **Team lifecycle**: `TeamCreate` at first delegation → `TeamDelete` when all agents complete.
  Do NOT leave teams running between tasks.
- Agent model is set per agent in `.claude/agents/` frontmatter (`model: opus/sonnet/haiku`).
- Each agent has its own memory directory (`.claude/agent-memory/<agent-name>/`).
  Enable cross-session learning with `memory: project` in agent frontmatter.

## Coding Rules

1. **Read first** — Read existing code before modifying
2. **Keep it simple** — Minimum code for the task
3. **Follow patterns** — Match existing codebase style
4. **Protect secrets** — Never commit credentials or API keys
5. **Verify** — Build and test before claiming success
6. **Fix root causes** — 에러 발생 시 근본 원인을 진단·해결. 우회(workaround)나 무시 금지
7. **Explicit failure** — No form of arbitrary success is permitted; every operation must genuinely succeed or explicitly fail

## Communication

- **Language**: 사용자에게 응답할 때 반드시 한국어를 사용합니다.

## Environment

- **Ports**: `.devcontainer/.env`에서 관리 (PORT_APP, PORT_API, PORT_DB, PORT_EXTRA)
- **Claude Code**: 네이티브 바이너리 (~/.local/bin/claude, 자동 업데이트)
- **Node.js**: MCP 인프라용 Node 22 LTS 항상 설치. PROJECT_NODE_VERSION 설정 시 추가 버전 설치
- **Persistent volumes**: `~/.claude` (인증 토큰), `/commandhistory` (히스토리)
- **9p mount**: `core.filemode=false` (postStartCommand 자동 적용)
- **MCP**: Context7 (documentation), Serena (code intelligence) — 플러그인 자동 관리

## Extended Reference

@PROJECT.md
@REFERENCE.md

---

*Last updated: 2026-03-22*
