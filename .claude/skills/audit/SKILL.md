---
name: audit
description: Standards compliance audit for agents, hooks, skills, and rules. Self-audit capable.
argument-hint: "[all|self|<agent-name>]"
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
---

Run a standards compliance audit against `.claude/rules/standards/*.md`.

Target: $ARGUMENTS (default: all)

## Audit Modes

| Mode | Command | Scope |
|------|---------|-------|
| `all` | `/audit all` | All agents, hooks, skills, rules |
| `self` | `/audit self` | audit skill + agent-evolver + standards files (recursive) |
| `<name>` | `/audit code-reviewer` | Single agent definition |

## 4-Stage Audit Process

### Stage 1: Load Standards

Read all `.claude/rules/standards/*.md` files and extract "Compliance Checks" sections.
Build a checklist map: `{standard_file → [check_items]}`.

### Stage 2: Scan Artifacts

Scan these locations for artifacts to audit:

| Artifact Type | Location | Standard |
|---------------|----------|----------|
| Agent definitions | `.claude/agents/*.md` | agent-definition.md |
| Hook scripts | `.claude/hooks/*.sh` | hooks-and-lifecycle.md |
| Skill definitions | `.claude/skills/*/SKILL.md` | knowledge-management.md |
| Rule files | `.claude/rules/*.md` | knowledge-management.md |
| CLAUDE.md | `/CLAUDE.md` | knowledge-management.md, governance.md |
| Instinct files | `.claude/instincts/personal/*.md` | evolution-and-learning.md |
| Settings | `.claude/settings.json` | hooks-and-lifecycle.md |

### Stage 3: Check Compliance

For each artifact, verify against its applicable standard:

**Agent checks** (from agent-definition.md):
1. Parse YAML frontmatter — extract name, tools, description, model, disallowedTools
2. Verify `name` matches filename
3. Verify `tools` is YAML array format
4. Verify tool set matches role in Tool Discipline table
5. Verify `disallowedTools` set for read-only/diagnostic agents
6. Verify `model` is specified

**Hook checks** (from hooks-and-lifecycle.md):
1. Verify shebang (`#!/bin/bash`)
2. Run `bash -n <file>` for syntax
3. For observe.sh: verify observation fields recorded

**Skill checks** (from knowledge-management.md):
1. Verify SKILL.md exists with frontmatter
2. Verify required fields: name, description

**Governance checks** (from governance.md):
1. Verify CLAUDE.md immutable principles are intact
2. Verify no project-specific content in portable rules

### Stage 4: Self-Audit (recursive, `/audit self` only)

Audit the audit system itself:
1. This SKILL.md — has required frontmatter fields
2. agent-evolver.md — has audit mode documented
3. Standards files — all 6 exist with required sections (Source, Standard, Compliance Checks, References)
4. Standards cross-reference consistency

## Output Format

```markdown
## Audit Report — [target] — [date]

### Summary
- Total checks: N
- PASS: N
- FAIL: N
- WARN: N

### Findings

| ID | Severity | Artifact | Standard | Check | Status | Detail |
|----|----------|----------|----------|-------|--------|--------|
| A-1 | CRITICAL | observe.sh | hooks-and-lifecycle | Fields recorded | FAIL | Missing input_summary |
| A-2 | HIGH | code-reviewer.md | agent-definition | Tool discipline | PASS | Read-only tools only |

### Recommendations
- [ID]: [Specific fix with file path and change description]
```

### Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| CRITICAL | System broken or non-functional | Fix immediately |
| HIGH | Standard violated, degraded function | Fix before next commit |
| MEDIUM | Best practice violation | Fix in current session |
| LOW | Minor inconsistency | Track for next evolution |
