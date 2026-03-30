---
name: audit
description: Run automated compliance tests for the .claude/ agent system.
argument-hint: "[all|agents|hooks|governance|sync|docs] (default: all)"
user-invocable: true
allowed-tools: ["Bash", "Read"]
---

Run automated compliance tests for the `.claude/` agent system.

## Usage

| Mode | Command | Scope |
|------|---------|-------|
| `all` | `/audit` or `/audit all` | Run all test suites (run-all.sh) |
| `agents` | `/audit agents` | Agent definitions (13 checks) |
| `hooks` | `/audit hooks` | Hook scripts + settings.json (18 checks) |
| `governance` | `/audit governance` | Governance + knowledge + team patterns (14 checks) |
| `refinement` | `/audit refinement` | Refinement loop + evaluator (14 checks) |
| `sync` | `/audit sync` | Sync consistency across 3 targets |
| `docs` | `/audit docs` | Product documentation scan (inline, no dedicated test script) |

## Execution

```bash
# Run all tests
bash .claude/tests/run-all.sh

# Run individual suite
bash .claude/tests/test-agents.sh
bash .claude/tests/test-hooks.sh
bash .claude/tests/test-governance.sh
bash .claude/tests/test-refinement.sh
bash .claude/tests/test-sync.sh
```

For `/audit docs`, scan product CLAUDE.md/PROJECT.md/REFERENCE.md files under `products/`
and check: existence, required sections, line limits, no hardcoded tokens.

## Output Format

```
PASS: <check-id> <description> (<detail>)
FAIL: <check-id> <description> (<detail>)
SKIP: <check-id> <description> (<reason>)
---
TOTAL: N  PASS: N  FAIL: N  SKIP: N
```

## After Running

1. Report PASS/FAIL/SKIP counts per suite and grand total
2. List all FAIL items with details
3. For each FAIL, suggest specific fix (file path + change)
4. Reference `.claude/docs/hook-reference.md` for hook protocol details
