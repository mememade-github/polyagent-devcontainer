---
name: eval
description: Eval-Driven Development (EDD) framework. Define success criteria BEFORE implementation, then measure with pass@k metrics.
user-invocable: true
---

# /eval — Eval-Driven Development

## Commands

- `/eval define <name>` — Create eval definition
- `/eval check <name>` — Run evals and report status
- `/eval report <name>` — Generate full eval report

## Process

### 1. Define (BEFORE coding)
Create `.claude/evals/<name>.md`:

```markdown
## EVAL: <name>

### Capability Evals
- [ ] <expected behavior 1>
- [ ] <expected behavior 2>

### Regression Evals
- [ ] <existing behavior that must not break>

### Success Metrics
- pass@3 > 90% for capability evals
- pass^3 = 100% for regression evals
```

### 2. Implement
Write code to pass the defined evals.

### 3. Evaluate
Run each eval, record PASS/FAIL:
- **Code grader**: deterministic (test command, grep, curl)
- **Manual grader**: for UX, security, architecture decisions

### 4. Report
```
EVAL REPORT: <name>
Capability: X/Y passed (pass@k: Z%)
Regression: X/Y passed
Status: READY / NOT READY
```

## Metrics

| Metric | Meaning | Target |
|--------|---------|--------|
| pass@1 | First attempt success | > 70% |
| pass@3 | Success within 3 attempts | > 90% |
| pass^3 | All 3 trials succeed | 100% for regression |

## Storage

```
.claude/evals/
├── <name>.md       # Eval definition
└── <name>.log      # Run history
```
