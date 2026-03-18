# Agent System — Project Overrides

> Project-specific agent policies that override portable standards.
> For base standards, see `.claude/rules/standards/agent-definition.md`.

## Model Policy

All agents in this workspace use the top-tier model:

```yaml
model: opus    # ALL agents — no exceptions
```

This overrides the standard's per-complexity model selection guide.
Rationale: consistency and maximum capability across all agent operations.

## Tool Access Policy

All agents have full tool access:

```yaml
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]
```

- No `disallowedTools` — agents self-regulate based on role description
- No `permissionMode` — default system behavior
- Overrides the standard's role-based restriction recommendation

## Team Structure

| Team | Agents | Auto-trigger |
|------|--------|-------------|
| quality | code-reviewer, security-reviewer, database-reviewer, environment-checker, agent-evolver | After code changes; on env issues; before session end |
| build | build-error-resolver, tdd-guide, refactor-cleaner | On build failure; on new feature; on maintenance |
| testing | e2e-runner, tdd-guide | On feature completion; on regression check |
| docs | doc-updater | On system changes (agents, services, scripts) |
| workflow | wip-manager | When tasks span sessions |

## Agent Inventory (14)

All agents: `model: opus`, `memory: project`, full tool access, `maxTurns` 8-20.

| Agent | maxTurns | Skills | Purpose |
|-------|----------|--------|---------|
| agent-evolver | 15 | verify, audit | Session analysis, agent/rule/skill evolution |
| architect | 20 | — | Architecture patterns and design review |
| build-error-resolver | 15 | — | Fix build/type errors with minimal diffs |
| code-reviewer | 15 | — | Code review with severity framework |
| database-reviewer | 15 | — | PostgreSQL optimization, schema design |
| debugger | 15 | — | Root cause analysis for runtime errors |
| doc-updater | 15 | — | Documentation and codemap specialist |
| e2e-runner | 15 | — | E2E testing (curl, Playwright) |
| environment-checker | 10 | — | Workspace health verification |
| planner | 20 | — | Implementation planning specialist |
| refactor-cleaner | 15 | — | Dead code cleanup and consolidation |
| security-reviewer | 15 | — | Security vulnerability detection (OWASP) |
| tdd-guide | 20 | — | TDD: RED→GREEN→REFACTOR cycle |
| wip-manager | 8 | status | Multi-session task tracking |
