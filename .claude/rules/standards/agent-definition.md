# Agent Definition Standard

## Source
- Official: Claude Code agent documentation (https://code.claude.com/docs/en/agents)
- Community: everything-claude-code (ECC) v5
- Last verified: 2026-02-26

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
model: opus|sonnet|haiku  # Per Model Selection Guide below
maxTurns: 15              # Safety/cost gate — MUST be set for all agents
memory: project           # Enables .claude/agent-memory/<name>/MEMORY.md injection
```

### Optional Frontmatter Fields

```yaml
color: "#FF6B6B"          # Display color in UI (hex format)
skills: [verify, learn]   # Skills available to agent
```

> **Origin note**: `maxTurns`, `memory`, `skills`
> are ECC-derived patterns (not in official Anthropic docs). They are the de facto standard
> and are **operationally required** in this workspace. Do not remove based on
> "official docs only" reasoning.

### Tool Access Policy

**All agents have full tool access** for maximum autonomy:

```yaml
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]
```

- No `disallowedTools` — agents self-regulate based on their role description
- No `permissionMode` — uses system default
- Agent body content guides appropriate tool usage (not enforcement via restrictions)

### Model Selection Guide

| Model | Use For | Agents |
|-------|---------|--------|
| opus | Complex reasoning, architecture, evolution | agent-evolver, architect, code-reviewer, planner |
| sonnet | Standard tasks, balanced cost/quality | database-reviewer, doc-updater, e2e-runner, refactor-cleaner, security-reviewer, tdd-guide |
| haiku | Quick diagnostics, simple fixes | build-error-resolver, debugger, environment-checker, wip-manager |

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
- [ ] `model` specified and appropriate for complexity per Model Selection Guide
- [ ] `maxTurns` specified for all agents (no unlimited execution)
- [ ] `memory: project` specified for all agents with MEMORY.md
- [ ] `description` is a single line, not truncated

## References

- https://code.claude.com/docs/en/agents (official agent reference)
- `.claude/agents/*.md` (current agent definitions)
