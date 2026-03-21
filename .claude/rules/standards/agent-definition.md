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
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]
---
```

### Required Operational Fields

These fields are functionally necessary for safe and cost-effective agent operation.
Removal causes regression (ref: c752d12 incident). **Do NOT strip during compliance audits.**

```yaml
model: opus               # Select per complexity — see Model Selection Guide below
maxTurns: 15              # Safety/cost gate — MUST be set for all agents
memory: project           # Scope: user | project | local. Enables agent-memory/<name>/MEMORY.md
```

> **Note**: `maxTurns`, `memory`, `skills` are officially supported fields
> documented at code.claude.com/docs/en/sub-agents (confirmed 2026-03-19).
> These are **operationally required** in this workspace. Do not remove during compliance audits.

### Optional Frontmatter Fields

```yaml
effort: high               # Reasoning depth: low | medium | high | max (official)
skills: [verify, learn]   # Skills available to agent (official)
isolation: worktree        # Run in temporary git worktree (official)
background: true           # Always run as background task (official)
mcpServers: []             # MCP servers available to subagent (official)
hooks: {}                  # Lifecycle hooks scoped to subagent (official)
```

### Tool Access Policy

**모든 에이전트에 전체 도구를 명시적으로 주입한다.**

```yaml
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]
```

- 전 에이전트 동일한 도구 세트 명시 (암묵적 상속 대신 명시적 선언)
- No `disallowedTools` — 역할 기반 body content로 자율 규제
- No `permissionMode` — uses system default

> **Note**: Projects may override via `.claude/rules/project/agent-overrides.md`.

### Model Selection Guide

Default model selection per complexity. **Check project overrides first** — many projects standardize on a single model tier via `.claude/rules/project/agent-overrides.md`.

| Model | Use For |
|-------|---------|
| opus | Complex reasoning, architecture, security |
| sonnet | Standard tasks, code review, testing |
| haiku | Simple checks, formatting, env verification |

### Body Content

- Start with role description ("You are a...")
- Include review checklist or step-by-step process
- Define output format
- Design focused subagents: each should excel at one specific task
- No official size limit — body is injected as system prompt within context window

## Compliance Checks

- [ ] `name` field matches filename (without .md)
- [ ] `tools` is `["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"]`
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
