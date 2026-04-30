# AGENTS.md — Polyagent DevContainer (Codex CLI 측 거버넌스)

> **Codex 측 미러 of CLAUDE.md.** Codex CLI는 본 `AGENTS.md`, `.codex/`, `.agents/skills/`를
> 기준으로 동작합니다. Claude Code(`CLAUDE.md`/`.claude/`)가 ground truth이며 본 문서는
> Codex 호환 미러입니다 (Polyagent Parity 모델).

**Karpathy 4-rule (Codex 미러)**: [`.agents/rules/behavioral-core.md`](.agents/rules/behavioral-core.md) + Skill [`.agents/skills/karpathy-guidelines/`](.agents/skills/karpathy-guidelines/) (SKILL.md + EXAMPLES.md). 작업 시작 시 Read 도구로 우선 로드. 출처: [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (MIT).

## Identity

- **Workspace**: `/workspaces/`
- **Environment**: Dev Container (Ubuntu 22.04, user=vscode)

## Project Structure

```
/workspaces/                        # Project root
├── AGENTS.md                       # Governance rules for Codex (this file)
├── CLAUDE.md                       # Governance rules for Claude (mirror)
├── PROJECT.md                      # Domain context (customize per project)
├── REFERENCE.md                    # Commands and procedures
├── .codex/                         # Codex CLI configuration
│   ├── config.toml                 # MCP servers, features, sandbox/approval policy
│   ├── hooks.json                  # Event hooks (SessionStart, PreToolUse, Stop)
│   ├── hooks/                      # Hook shell scripts (4)
│   └── state/                      # Runtime markers (verification, push baseline, refinement)
├── .agents/                        # Codex agent assets (mirror of .claude/)
│   ├── rules/                      # Behavioral rules (Karpathy 4-rule + project)
│   ├── security/                   # Trust boundary, registry (mirror)
│   └── skills/                     # Skills (Open Agent Skills Standard mirror of /commands)
├── .devcontainer/                  # Container configuration
└── src/                            # Source code (your project)
```

## Core Principle: INTEGRITY

**Every claim must be verified by execution before statement.**

- Don't say "tests pass" without running them
- Don't say "build succeeds" without building
- Don't say "works" without testing

## Destructive Operations (APPROVAL REQUIRED)

Never execute without explicit user approval:
`rm -rf`, `mv`/`cp` (overwrite), `git push --force`, `git reset --hard`, `DROP`/`DELETE` (DB)

## Automated Workflow (MANDATORY)

These rules are enforced automatically by hooks (`.codex/hooks.json`). No user commands required.

### 1. Session Start (automated by SessionStart hook)

- Hook injects: current branch, active WIP tasks, environment info
- **If WIP tasks exist**: Immediately read the WIP README.md and resume work.
  Do NOT wait for user instruction — report status and continue the task.
- **If no WIP**: Report readiness and wait for user instruction.
- **Always**: Check auto memory (MEMORY.md) for Known Issues.

### 2. Change Evaluation

- **Meaningful changes**: use the `refine` skill (`.agents/skills/refine/`) — evaluation is structural
  (modify → evaluate → keep/discard loop). Not optional.
- **Trivial changes** (typo, single config line): direct edit, no evaluation needed.
- Never self-evaluate. Delegate to the **evaluator** skill (`.agents/skills/evaluator/`).

### 3. Pre-Commit Gate (automated by pre-commit-gate.sh via PreToolUse hook)

Before ANY `git commit`:
1. Run verification for affected code (auto-detected by file type)
2. All checks MUST pass before commit. No `--no-verify`.

### 4. Multi-Session Tasks

- Tasks likely to span sessions → invoke the **wip-manager** skill (`.agents/skills/wip-manager/`)
- WIP location: `wip/task-YYYYMMDD-description/README.md`
- Auto-resume at next session start (via SessionStart hook)
- Delete WIP directory when task is complete

### 5. Skill Delegation

> Codex CLI는 파일 기반 커스텀 서브에이전트 선언을 아직 공식 지원하지 않으므로,
> 기존 에이전트 책임은 `.agents/skills/` 하위 스킬로 흡수했습니다.

| Skill | Invocation |
|-------|-----------|
| refine | Meaningful changes requiring iterative refinement |
| evaluator | After changes (1-pass review); within refine loop |
| wip-manager | When task spans sessions |
| status | Workspace status |
| verify | Pre-commit verification |

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
- **Node.js**: Node 22 LTS always installed for MCP infrastructure
- **Persistent volumes**: `~/.claude` (Claude auth), `~/.codex` (Codex auth), `/commandhistory` (history)
- **9p mount**: `core.filemode=false` (auto-applied by postStartCommand)
- **MCP**: Context7 (documentation), Serena (code intelligence) — DevContainer 수준에서 관리

## Behavioral Rules (Codex 미러)

Polyagent Parity 원칙: Claude `CLAUDE.md`가 `.claude/rules/`를 참조하는 것과 동등하게, Codex
작업 시 다음 규칙 파일을 우선 적용합니다 (`Read` 도구로 작업 시작 시 로드):

- [.agents/rules/behavioral-core.md](.agents/rules/behavioral-core.md) — Karpathy 4-rule 행동 가이드 (Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution)
- [.agents/rules/devcontainer-patterns.md](.agents/rules/devcontainer-patterns.md) — DevContainer DinD 방지 + Volume Mount Path Translation

> **운영 원칙**: `.claude/rules/`가 ground truth이고 `.agents/rules/`는 Codex 호환 미러입니다.
> Claude 측 변경 시 `scripts/sync-agents-mirror.sh`로 동기화. 향후 다른 vendor가 추가될 경우
> 동일 미러 모델로 흡수합니다.

## Extended Reference

도메인 맥락과 명령어는 아래 파일을 참조하세요 (Codex AGENTS.md 표준은 `@import`
구문이 없으므로, 별도 파일로 유지하며 AI는 작업 중 필요 시 `Read` 도구로 로드):

- [PROJECT.md](PROJECT.md) — 도메인 컨텍스트 (services, infrastructure)
- [REFERENCE.md](REFERENCE.md) — 명령어 · 환경변수 · 포트 · 트러블슈팅

---

*Last updated: 2026-04-30 — renamed claude-devcontainer → polyagent-devcontainer (Codex parity → Polyagent Parity 일반화 + DataScience variant 흡수)*
