# Agent Definition Standard

## Source
- Official: Claude Code agent documentation (https://code.claude.com/docs/en/agents)
- Official: Claude Code subagent specification (https://code.claude.com/docs/en/sub-agents)
- Last verified: 2026-03-19

## Standard

### Required Frontmatter Fields

```yaml
---
name: agent-name          # kebab-case, must match filename
description: >-           # One-line purpose statement
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]  # Full access (YAML array)
---
```

### Required Operational Fields

These fields are functionally necessary for safe and cost-effective agent operation.
Removal causes regression (ref: c752d12 incident). **Do NOT strip during compliance audits.**

```yaml
model: opus               # Select per complexity — see Model Selection Guide below
maxTurns: 15              # Safety/cost gate — MUST be set for all agents
memory: project           # Enables .claude/agent-memory/<name>/MEMORY.md injection
```

> **Note**: `maxTurns`, `memory`, `skills` are officially supported fields
> documented at code.claude.com/docs/en/sub-agents (confirmed 2026-03-19).
> These are **operationally required** in this workspace. Do not remove during compliance audits.

### Optional Frontmatter Fields

```yaml
skills: [verify, learn]   # Skills available to agent (official)
isolation: worktree        # Run in temporary git worktree (official)
background: true           # Always run as background task (official)
mcpServers: []             # MCP servers available to subagent (official)
hooks: {}                  # Lifecycle hooks scoped to subagent (official)
```

### Tool Access Policy

**All agents have full tool access** for maximum autonomy:

```yaml
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]
```

- No `disallowedTools` — agents self-regulate based on their role description
- No `permissionMode` — uses system default
- Agent body content guides appropriate tool usage (not enforcement via restrictions)

> **Note**: Projects may override tool access via `.claude/rules/project/agent-overrides.md`.
> The official docs recommend role-based restrictions; full access relies on agent body
> content to guide appropriate tool usage.

### Model Selection Guide

| Model | Use For | Note |
|-------|---------|------|
| opus | Complex reasoning, architecture, security | Highest capability |
| sonnet | Standard tasks, code review, testing | Balanced cost/performance |
| haiku | Simple checks, formatting, env verification | Fast and economical |

> **Note**: Projects may override model selection via `.claude/rules/project/agent-overrides.md`.

### Body Content

- Start with role description ("You are a...")
- Include review checklist or step-by-step process
- Define output format
- Keep under 200 lines (system prompt budget)

## Compliance Checks

- [ ] `name` field matches filename (without .md)
- [ ] `tools` is `["Read", "Write", "Edit", "Bash", "Grep", "Glob"]` (full access)
- [ ] No `disallowedTools` field present
- [ ] No `permissionMode` field present
- [ ] `model` is set appropriately (see project overrides if applicable)
- [ ] `maxTurns` specified for all agents (no unlimited execution)
- [ ] `memory: project` specified for all agents with MEMORY.md
- [ ] `description` is a single line, not truncated
- [ ] New optional fields (isolation, background, mcpServers, hooks) valid when present

## References

- https://code.claude.com/docs/en/agents (official agent reference)
- https://code.claude.com/docs/en/sub-agents (official subagent specification)
- `.claude/agents/*.md` (current agent definitions)
