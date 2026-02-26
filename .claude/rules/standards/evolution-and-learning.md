# Evolution and Learning Standard

## Source
- Derived: MEMEMADE continuous-learning-v2 architecture
- Community: ECC instinct-based learning patterns
- Last verified: 2026-02-26

## Standard

### Evolution Pipeline

```
RUNTIME (every tool call)
observe.sh → observations.jsonl
    |
    v
SESSION STOP
evolution-gate.sh → checks .last-verification vs .last-evolution
    |
    v (if evolution needed)
AGENT-EVOLVER (manual delegation)
    |
    v
1. Read observations → detect patterns (4 types)
2. Read existing instincts → check for matches
3. Create/update instincts with confidence scoring
4. Cluster instincts → evolve (rules, skills, agents)
5. Mark evolution complete
```

### Pattern Types

| Pattern | Signal | Instinct Type |
|---------|--------|--------------|
| User corrections | Follow-up reverses action | Preference |
| Error resolutions | Error → fix repeated | Prevention |
| Repeated workflows | Same tool sequence 3+ times | Workflow |
| Tool preferences | Consistent tool choice | Preference |

### Confidence Scoring

| Observations | Confidence Level |
|-------------|-----------------|
| 1-2 | 0.3 (tentative) |
| 3-5 | 0.5 (moderate) |
| 6-10 | 0.7 (strong — auto-approved) |
| 11+ | 0.85 (very strong) |

### Confidence Adjustments

| Event | Adjustment |
|-------|------------|
| Confirming observation | +0.05 |
| Contradicting observation | -0.10 |
| Unobserved decay | -0.02/week |
| Archive threshold | < 0.2 |

### Evolution Threshold

Evolution triggers when a domain has:
- 3+ instincts
- Average confidence > 0.5

### Evolution Targets

| Instinct Cluster | Evolves Into | Location |
|-----------------|-------------|----------|
| Code pattern | Rule | `.claude/rules/` |
| Workflow pattern | Skill | `.claude/skills/` |
| Agent behavior | Agent definition update | `.claude/agents/` |
| Error prevention | Hook or pre-commit rule | Flag for manual update |

### Observation Data Requirements

For instinct generation to work, observations MUST contain semantic data:

**Minimum** (current): `{ts, phase, tool}` — insufficient for pattern detection
**Required**: `{ts, phase, tool, input_summary, success}` — enables meaningful patterns

Without `input_summary`, the agent-evolver cannot detect:
- Which files are frequently modified together
- Which search patterns precede edits
- Which tool sequences form workflows

### Domain Specificity

- Instincts are domain-specific (NOT included in Tier 1 templates)
- Rules evolved from instincts ARE portable (go to `.claude/rules/`)
- Skills evolved from instincts ARE portable (go to `.claude/skills/`)

## Compliance Checks

- [ ] `observe.sh` records minimum 3 fields: ts, phase, tool
- [ ] `observe.sh` records recommended 5 fields: + input_summary, success
- [ ] Instinct files have required frontmatter: id, trigger, confidence, domain
- [ ] Instinct confidence is within [0.0, 1.0] range
- [ ] Archived instincts have confidence < 0.2
- [ ] Evolution only triggered with 3+ instincts at avg > 0.5
- [ ] Evolved artifacts go to correct locations (rules/, skills/, agents/)
- [ ] `mark-evolved.sh` is called after evolution completes

## References

- `.claude/hooks/observe.sh` (observation hook)
- `.claude/hooks/evolution-gate.sh` (evolution trigger)
- `.claude/agents/agent-evolver.md` (evolution agent)
- `.claude/instincts/` (instinct storage)
