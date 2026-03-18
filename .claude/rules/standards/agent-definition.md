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
model: opus               # 프로젝트 특수 지침: 모든 Agent는 최상위 모델 사용
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

> 이 워크스페이스는 모든 Agent에 전체 도구 접근을 허용합니다 (프로젝트 특수 지침).
> 공식 문서는 역할별 제한을 권장하지만, 이 워크스페이스에서는 Agent body content로
> 적절한 도구 사용을 유도하는 방식을 선택합니다.

### Model Selection Guide

| Model | Use For | Note |
|-------|---------|------|
| opus | ALL agents | 프로젝트 특수 지침: 모든 Agent는 최상위 모델 사용 (2026-03-19) |

> 이 워크스페이스는 모든 Agent에 opus 모델을 사용합니다.
> 이는 공식 문서의 역할별 모델 선택 가이드를 override합니다.

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
- [ ] `model` is `opus` for all agents (프로젝트 특수 지침)
- [ ] `maxTurns` specified for all agents (no unlimited execution)
- [ ] `memory: project` specified for all agents with MEMORY.md
- [ ] `description` is a single line, not truncated
- [ ] New optional fields (isolation, background, mcpServers, hooks) valid when present

## References

- https://code.claude.com/docs/en/agents (official agent reference)
- https://code.claude.com/docs/en/sub-agents (official subagent specification)
- `.claude/agents/*.md` (current agent definitions)
