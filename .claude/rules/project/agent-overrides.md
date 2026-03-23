# Agent System — Project Overrides

> Project-specific agent policies. Compliance verified by `bash .claude/tests/test-agents.sh`.

## Model Policy

All agents in this workspace use the top-tier model:

```yaml
model: opus    # ALL agents — no exceptions
```

This overrides the standard's per-complexity model selection guide.
Rationale: consistency and maximum capability across all agent operations.

## Tool Access Policy

전 에이전트에 동일한 전체 도구를 명시적으로 주입 (예외 없음):

```yaml
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]
```

## Effort Policy

전 에이전트 `effort: high` (예외 없음):

```yaml
effort: high    # ALL agents — 최대 추론 품질
```

Rationale: 모든 도구를 활용하고 모든 능력을 고수준으로 작업하는 것이 지침.

## Team Structure

| Team | Agents | Auto-trigger |
|------|--------|-------------|
| quality | code-reviewer, security-reviewer, database-reviewer, environment-checker, agent-evolver | After code changes; on env issues; before session end |
| build | build-error-resolver, tdd-guide, refactor-cleaner | On build failure; on new feature; on maintenance |
| testing | e2e-runner, tdd-guide | On feature completion; on regression check |
| docs | doc-updater | On system changes (agents, services, scripts) |
| workflow | wip-manager | When tasks span sessions |

## Agent Inventory (14)

All agents: `model: opus`, `memory: project`, `maxTurns` 8-20.

| Agent | maxTurns | effort | Tools | Skills | Color | MCP | Extra | Purpose |
|-------|----------|--------|-------|--------|-------|-----|-------|---------|
| agent-evolver | 15 | high | full | verify, audit | magenta | — | background | Session analysis, agent/rule/skill evolution |
| architect | 20 | high | full | — | cyan | serena | — | Architecture patterns and design review |
| build-error-resolver | 15 | high | full | verify | red | — | — | Fix build/type errors with minimal diffs |
| code-reviewer | 15 | high | full | — | green | serena | hooks | Code review with severity framework |
| database-reviewer | 15 | high | full | — | blue | serena | — | PostgreSQL optimization, schema design |
| debugger | 15 | high | full | — | yellow | — | — | Root cause analysis for runtime errors |
| doc-updater | 15 | high | full | — | cyan | context7 | — | Documentation and codemap specialist |
| e2e-runner | 15 | high | full | verify | green | — | — | E2E testing (curl, Playwright) |
| environment-checker | 10 | high | full | status | yellow | — | — | Workspace health verification |
| planner | 20 | high | full | — | cyan | — | — | Implementation planning specialist |
| refactor-cleaner | 15 | high | full | verify | magenta | — | isolation | Dead code cleanup and consolidation |
| security-reviewer | 15 | high | full | — | red | serena | — | Security vulnerability detection (OWASP) |
| tdd-guide | 20 | high | full | verify | green | — | — | TDD: RED→GREEN→REFACTOR cycle |
| wip-manager | 8 | high | full | status | blue | — | — | Multi-session task tracking |
