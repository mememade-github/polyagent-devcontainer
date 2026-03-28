# Agent System — Project Overrides

> Project-specific agent policies. Compliance verified by `.claude/tests/test-agents.sh`.

## Model Policy

All agents in this workspace use the top-tier model:

```yaml
model: opus    # ALL agents — no exceptions
```

Rationale: consistency and maximum capability across all agent operations.

## Tool Access Policy

All agents have full tool access. Behavioral boundaries are enforced at the prompt level, not by tool restriction. This aligns with the autoresearch principle: maximize agent capability, control via measurement.

```yaml
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]
```

Each agent's prompt defines a **Behavioral Boundary** section specifying its operational scope (e.g., "you REVIEW and REPORT — you do not fix code"). This preserves full diagnostic capability while establishing clear role expectations.

**Exception — agent-evolver**: May modify rules/ and skills/ directly, but agents/*.md changes must be proposed (not applied) to prevent self-referential modification loops.

## Effort Policy

Global `effortLevel: high` in `settings.json`. Per-agent `effort` field not used.

## Team Structure

| Team | Agents | Auto-trigger |
|------|--------|-------------|
| quality | code-reviewer, agent-evolver | After code changes; on audit request |
| build | build-error-resolver | On build failure; on runtime error |
| testing | e2e-runner | On feature completion; on regression check |
| workflow | wip-manager | When task spans sessions |

> planner is not team-bound — invoked on-demand for design/architecture tasks.

## Frontmatter Reference

**Required fields** (all agents):

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | kebab-case, must match filename |
| `description` | string | One-line purpose statement |
| `tools` | array | `["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]` |
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

## Agent Inventory (6)

All agents: `model: opus`, full tools, `maxTurns` 8-20.

| Agent | maxTurns | Boundary | Skills | Color | MCP | Extra | Purpose |
|-------|----------|----------|--------|-------|-----|-------|---------|
| agent-evolver | 15 | audit/report | verify, audit | magenta | — | background, memory | Standards compliance auditor |
| build-error-resolver | 15 | — | verify, build-fix | red | — | — | Build errors + runtime debugging |
| code-reviewer | 15 | review/report | verify | green | serena | hooks | Code + security + DB review |
| e2e-runner | 20 | — | verify | green | — | — | TDD + unit + E2E testing |
| planner | 20 | plan/document | — | cyan | serena, context7 | — | Planning + architecture |
| wip-manager | 8 | wip/ dir only | status | blue | — | memory | Multi-session task tracker |
