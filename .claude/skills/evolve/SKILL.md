---
name: evolve
description: Cluster related instincts into skills, commands, or agents. Run after accumulating 5+ instincts in a domain.
user-invocable: true
---

# /evolve — Instinct Evolution

Cluster related instincts from `.claude/instincts/personal/` into higher-order constructs.

## Process

1. Read all instincts in `.claude/instincts/personal/`
2. Group by domain (code-style, testing, git, debugging, workflow, infrastructure)
3. For each domain with 3+ instincts:
   - Identify common triggers
   - Merge into a cohesive pattern
   - Decide target: skill (workflow) | rule (always-follow) | agent update (checklist item)
4. Create/update the target construct
5. Mark evolved instincts with `evolved: true`

## Evolution Targets

| Instinct Count | Confidence Avg | Target |
|---------------|---------------|--------|
| 3-5 | > 0.5 | Rule (`.claude/rules/`) |
| 5-10 | > 0.6 | Skill (`.claude/skills/`) |
| 10+ | > 0.7 | Agent update or new agent |

## Output

```
Evolution Report:
- Domain: <domain>
- Instincts clustered: <count>
- Target: <rule|skill|agent>
- Created/Updated: <file path>
```
