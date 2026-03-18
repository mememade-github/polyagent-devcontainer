---
name: learn
description: Extract patterns from current session and save as instincts. Use mid-session when you notice a reusable pattern.
---

# /learn — Mid-Session Pattern Extraction

Extract a reusable pattern from the current session and save it as an instinct.

## Process

1. **Identify the pattern**: What behavior/technique was effective?
2. **Classify**: code-style | testing | git | debugging | workflow | infrastructure
3. **Assess confidence**:
   - 0.3 = first observation (tentative)
   - 0.5 = seen 2-3 times (moderate)
   - 0.7 = confirmed pattern (strong)
4. **Write instinct file** to `.claude/instincts/personal/<id>.md`:

```markdown
---
id: <kebab-case-name>
trigger: "<when this pattern applies>"
confidence: <0.3-0.9>
domain: "<category>"
source: "session-observation"
created: "<YYYY-MM-DD>"
---

# <Pattern Name>

## Action
<What to do when trigger matches>

## Evidence
- <What observation created this instinct>
```

5. **Report**: Show instinct created with confidence level

## Rules

- One instinct per /learn invocation
- If similar instinct exists, UPDATE confidence (+0.1) instead of creating duplicate
- Check `.claude/instincts/personal/` for existing instincts before creating
- Never create instincts with confidence > 0.7 on first observation
