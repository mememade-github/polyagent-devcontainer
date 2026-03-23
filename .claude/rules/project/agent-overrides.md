# Agent System — Project Overrides

> Project-specific agent policies. Compliance verified by `.claude/tests/test-agents.sh`.

## Model Policy

All agents in this workspace use the top-tier model:

```yaml
model: opus    # ALL agents — no exceptions
```

Rationale: consistency and maximum capability across all agent operations.

## Tool Access Policy

Role-based tool restriction. Read-only agents cannot modify code.

| Role | Tools | Agents |
|------|-------|--------|
| **read-only** | `Read, Grep, Glob` | architect, code-reviewer, database-reviewer, security-reviewer |
| **diagnostic** | `Read, Bash, Grep, Glob` | debugger, environment-checker |
| **research** | `Read, Grep, Glob, WebSearch, WebFetch` | planner |
| **docs-only** | `Read, Write, Edit, Grep, Glob` | doc-updater |
| **state-only** | `Read, Write, Grep, Glob` | wip-manager |
| **full** | all tools | agent-evolver, build-error-resolver, e2e-runner, refactor-cleaner, tdd-guide |

## Effort Policy

Global `effortLevel: high` in `settings.json`. Per-agent `effort` field not used.

## Team Structure

| Team | Agents | Auto-trigger |
|------|--------|-------------|
| quality | code-reviewer, security-reviewer, database-reviewer, environment-checker, agent-evolver | After code changes; on env issues; before session end |
| build | build-error-resolver, tdd-guide, refactor-cleaner | On build failure; on new feature; on maintenance |
| testing | e2e-runner, tdd-guide | On feature completion; on regression check |
| docs | doc-updater | On system changes (agents, services, scripts) |
| workflow | wip-manager | When tasks span sessions |

## Frontmatter Reference

**Required fields** (all agents):

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | kebab-case, must match filename |
| `description` | string | One-line purpose statement |
| `tools` | array | Role-specific (see Tool Access Policy above) |
| `model` | string | `opus` (this workspace) |

**Common optional fields**:

| Field | Type | Description |
|-------|------|-------------|
| `maxTurns` | int | Safety/cost gate (8-20) |
| `memory` | string | `project` — only for agents needing cross-session state |
| `isolation` | string | `worktree` — run in temporary git worktree |
| `background` | bool | Always run as background task |
| `mcpServers` | array | MCP servers available to subagent |
| `skills` | array | Skills available to agent |
| `hooks` | object | Lifecycle hooks scoped to subagent |
| `color` | string | Display color in CLI |

> Verified by: `bash .claude/tests/test-agents.sh`

## Agent Inventory (14)

All agents: `model: opus`, `maxTurns` 8-20.

| Agent | maxTurns | Tools | Skills | Color | MCP | Extra | Purpose |
|-------|----------|-------|--------|-------|-----|-------|---------|
| agent-evolver | 15 | full | verify, audit | magenta | — | background, memory | Session analysis, agent/rule/skill evolution |
| architect | 20 | read-only | — | cyan | serena | — | Architecture patterns and design review |
| build-error-resolver | 15 | full | verify, build-fix | red | — | — | Fix build/type errors with minimal diffs |
| code-reviewer | 15 | read-only | verify | green | serena | hooks | Code review with severity framework |
| database-reviewer | 15 | read-only | — | blue | serena | hooks | PostgreSQL optimization, schema design |
| debugger | 15 | diagnostic | — | yellow | serena | — | Root cause analysis for runtime errors |
| doc-updater | 15 | docs-only | — | cyan | context7 | background | Documentation and codemap specialist |
| e2e-runner | 15 | full | verify | green | — | isolation | E2E testing (curl, Playwright) |
| environment-checker | 10 | diagnostic | status | yellow | — | background | Workspace health verification |
| planner | 20 | research | — | cyan | serena, context7 | — | Implementation planning specialist |
| refactor-cleaner | 15 | full | verify | magenta | — | isolation | Dead code cleanup and consolidation |
| security-reviewer | 15 | read-only | verify | red | serena | — | Security vulnerability detection (OWASP) |
| tdd-guide | 20 | full | verify | green | serena | isolation | TDD: RED→GREEN→REFACTOR cycle |
| wip-manager | 8 | state-only | status | blue | — | memory | Multi-session task tracking |
