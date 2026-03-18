---
name: instinct-status
description: Show all learned instincts with confidence scores, grouped by domain. Overview of the instinct-based learning system.
user-invocable: true
---

# /instinct-status — Instinct Overview

Show current state of the instinct-based learning system.

## Process

1. Read all files in `.claude/instincts/personal/` and `.claude/instincts/inherited/`
2. Parse YAML frontmatter (id, trigger, confidence, domain, source)
3. Group by domain
4. Sort by confidence (descending)
5. Display:

```
INSTINCT STATUS
===============

Personal Instincts: X
Inherited Instincts: Y
Observations: Z lines in observations.jsonl

By Domain:
  code-style (3):
    [0.9] prefer-functional-style: "when writing new functions"
    [0.7] use-type-annotations: "when defining function parameters"
    [0.5] avoid-global-state: "when structuring modules"

  testing (2):
    [0.8] test-first: "when implementing new features"
    [0.6] mock-external: "when testing API integrations"

Ready for Evolution:
  code-style: 3 instincts (avg 0.7) → ready for /evolve
```

6. Count observations.jsonl lines
7. Suggest `/evolve` for domains with 3+ instincts above 0.5 avg confidence
