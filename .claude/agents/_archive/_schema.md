# Agent System — Internalized & Portable

> **DEPRECATED (2026-03-19)**: This file is a historical archive. Current authoritative sources:
> - Agent standard: `.claude/rules/standards/agent-definition.md`
> - Project overrides: `.claude/rules/project/agent-overrides.md`
> - Team patterns: `.claude/rules/standards/team-patterns.md`
>
> Tool restrictions and model selections below reflect **obsolete** policy.
> All agents now have full tool access and use opus model per project override.

## Architecture

```
ECC Plugin (source) ──updates──→ Compare & Merge
Other best practices ──────────→ Compare & Merge
                                      │
                                      ▼
                          .claude/agents/ (자체 소유, 14개)
                                      │
                          Usage + agent-evolver 진화
                                      ▼
                          단일 소스보다 우월한 진화체
```

**원칙**: 에이전트는 외부 참조(`everything-claude-code:`)가 아니라 자체 복사본. ECC 업데이트 시 비교&병합, 다른 모범사례 추가, 사용 중 진화.

## Teams

| Team | Agents | Auto-trigger |
|------|--------|-------------|
| quality | code-reviewer, security-reviewer, database-reviewer, environment-checker, agent-evolver | After code changes; on env issues; before session end |
| build | build-error-resolver, tdd-guide, refactor-cleaner | On build failure; on new feature; on maintenance |
| testing | e2e-runner, tdd-guide | On feature completion; on regression check |
| docs | doc-updater | On system changes (agents, services, scripts) |
| workflow | wip-manager | When tasks span sessions |

## All Agents (14 — all portable, all self-owned)

| Agent | Origin | Lines | Purpose |
|-------|--------|-------|---------|
| code-reviewer | ECC | 104 | Code review with severity framework |
| security-reviewer | ECC | 545 | Security vulnerability detection (OWASP) |
| database-reviewer | ECC | 654 | PostgreSQL optimization, schema design |
| build-error-resolver | ECC | 532 | Fix build/type errors with minimal diffs |
| tdd-guide | ECC | 280 | TDD: RED→GREEN→REFACTOR cycle |
| e2e-runner | ECC | 797 | E2E testing (Agent Browser + Playwright) |
| doc-updater | ECC | 452 | Documentation and codemap specialist |
| refactor-cleaner | ECC | 306 | Dead code cleanup and consolidation |
| architect | ECC | 211 | Architecture patterns and design review |
| planner | ECC | 119 | Implementation planning specialist |
| agent-evolver | Custom | 106 | Session analysis → agent/rule/skill evolution |
| debugger | Custom | 79 | Root cause analysis for runtime/integration errors |
| environment-checker | Custom | 56 | Workspace health verification |
| wip-manager | Custom | 74 | Multi-session task tracking |

## Delegation Rules

1. **code-reviewer**: Auto-delegate after code changes in source directories
2. **security-reviewer**: Auto-delegate after security-sensitive changes
3. **environment-checker**: Auto-delegate when SessionStart reports environment issues
4. **wip-manager**: Auto-delegate when tasks span sessions
5. **agent-evolver**: Auto-delegate before session end (evolution-gate.sh)

## Invocation

```
Task tool → subagent_type: "<agent-name>"
         → team_name: "quality" / "build" / "testing" / "docs" / "workflow"
```

All 14 agents are invoked by name without prefix.

## Rules Separation

```
.claude/rules/                    # Standard (portable — copy to any project)
├── devcontainer-patterns.md
├── iterative-retrieval.md
└── testing.md

.claude/rules/project/            # Project-specific (NOT portable — customize per project)
├── <tech-stack>.md               # e.g., python-fastapi.md, typescript-nextjs.md
└── <domain>.md                   # e.g., deployment.md, derived-projects.md
```

## Evolution Protocol

### Source Updates (ECC 등 외부 업데이트 시)
1. `diff` 현재 `.claude/agents/X.md` vs 새 ECC 버전
2. 우리 커스텀 변경사항 보존하며 새 기능 병합
3. agent-evolver 기록에 변경 이력 추가

### Usage Evolution (사용 중 진화)
1. observe.sh → observations.jsonl (매 도구 호출)
2. agent-evolver → 패턴 분석 → 에이전트/규칙/스킬 개선
3. Instinct system: confidence 0.3→0.9, decay -0.02/week

### Other Best Practices (다른 모범사례 추가 시)
1. 해당 패턴을 가장 관련 있는 에이전트에 병합
2. 새 에이전트가 필요한 경우에만 생성 (기존 에이전트 커버 불가 시)
3. 모든 변경은 agent-evolver 기록에 추적

## Design Rationale

| Agent | tools | disallowedTools | Why |
|-------|-------|-----------------|-----|
| code-reviewer | Read, Grep, Glob | Write, Edit, Bash | 리뷰는 read-only |
| environment-checker | Bash, Read, Glob, Grep | Write, Edit | 진단 실행, 수정 불필요 |
| wip-manager | Bash, Read, Write, Edit, Glob | NotebookEdit | WIP 파일 관리 |
| agent-evolver | Read, Write, Edit, Grep, Glob, Bash | NotebookEdit | .claude/ 파일 수정 |
| debugger | Read, Bash, Grep, Glob | Write, Edit | 진단 실행, 수정 불필요 |

ECC-origin agents use their original tool configurations.

## Version History

| Version | Date | Change |
|---------|------|--------|
| v7 | 2026-02-25 | ECC 내재화: 10개 에이전트 복사, 접두사 제거, 자체 소유 |
| v6 | 2026-02-25 | Agent 표준화: 중복 제거, 범용화 |
| v5 | 2026-02-25 | ECC 통합: 관측/진화/학습 시스템 |
| v4 | 2026-02-24 | 100% compliance, disallowedTools |
| v3 | 2026-02-24 | Best practices, security-reviewer |
| v2 | 2026-02-14 | GAP analysis, Ansible checklist |
