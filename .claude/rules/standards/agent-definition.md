# Agent Definition Standard

## Source
- Official: Claude Code agent documentation (2026)
- Community: everything-claude-code (ECC) v5
- Last verified: 2026-02-26

## Standard

### Required Frontmatter Fields

```yaml
---
name: agent-name          # kebab-case, must match filename
description: >-           # One-line purpose statement
tools: ["Read", "Grep"]   # YAML array format (not comma string)
---
```

### Optional Frontmatter Fields

```yaml
model: opus|sonnet|haiku  # Default: inherits from parent
maxTurns: 15              # Default: unlimited
memory: project           # Enables .claude/agent-memory/<name>/MEMORY.md
permissionMode: default   # default|acceptEdits|bypassPermissions
disallowedTools: [...]    # Explicit deny list
skills: [verify, learn]   # Skills available to agent
```

### Tool Discipline by Role

| Role | Agents | Allowed Tools | disallowedTools |
|------|--------|---------------|-----------------|
| Read-only review | code-reviewer, security-reviewer, planner, architect, database-reviewer | Read, Grep, Glob | Write, Edit, Bash, NotebookEdit |
| Diagnostic | debugger, environment-checker | Read, Grep, Glob, Bash | Write, Edit, NotebookEdit |
| Execution | build-error-resolver, tdd-guide, e2e-runner, refactor-cleaner, wip-manager, doc-updater | Read, Write, Edit, Bash, Grep, Glob | NotebookEdit |
| Evolution | agent-evolver | Read, Write, Edit, Bash, Grep, Glob | NotebookEdit |

### Model Selection Guide

| Model | Use For | Examples |
|-------|---------|---------|
| opus | Complex reasoning, multi-file analysis, evolution | agent-evolver, code-reviewer, planner |
| sonnet | Standard tasks, balanced cost/quality | doc-updater, wip-manager |
| haiku | Quick diagnostics, simple checks | build-error-resolver, environment-checker |

### Body Content

- Start with role description ("You are a...")
- Include review checklist or step-by-step process
- Define output format
- Keep under 200 lines (system prompt budget)

## Compliance Checks

- [ ] `name` field matches filename (without .md)
- [ ] `tools` is YAML array format `["Tool1", "Tool2"]`
- [ ] Tool set matches agent role per Tool Discipline table
- [ ] `disallowedTools` set for read-only and diagnostic agents
- [ ] `model` specified and appropriate for complexity
- [ ] `description` is a single line, not truncated
- [ ] No tools granted beyond what the role requires

## References

- `.claude/agents/*.md` (current agent definitions)
- Claude Code docs: Agent system and subagent types
