---
name: refine
description: Autonomous iterative refinement loop — thin orchestrator with fresh-context agents
argument-hint: "<task-description> [--max-iter N] [--threshold 0.85] [--project PATH] [--agent TYPE]"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# /refine — Autonomous Iterative Refinement Loop

Thin orchestrator: main agent drives the loop; all heavy work runs in fresh subagents per iteration.

## Arguments

- `<task-description>`: What to improve (required)
- `--max-iter N`: Maximum iterations (default: 10)
- `--threshold T`: Target score 0.0-1.0 (default: 0.85)
- `--project PATH`: Project path (default: CLAUDE_PROJECT_DIR)
- `--agent TYPE`: Agent type for modifications (default: general-purpose)

## State

Attempt history in a single JSONL file — no external scripts:

```
.claude/agent-memory/refinement/attempts/$TASK_ID.jsonl
```

Each line: `{"score":0.8,"result":"KEEP: added validation","feedback":"fix edge cases"}`

Three inline operations cover all needs:
```bash
# Record:  echo '{"score":...,"result":"...","feedback":"..."}' >> $ATTEMPTS
# Best:    jq -s 'sort_by(.score)|last|.score//0' $ATTEMPTS
# Count:   wc -l < $ATTEMPTS
```

## Protocol

### Step 0: Initialize

```bash
TASK_ID="refine-$(date +%Y%m%d-%H%M%S)"
PROJECT="${PROJECT:-$CLAUDE_PROJECT_DIR}"
THRESHOLD="${THRESHOLD:-0.85}"
MAX_ITER="${MAX_ITER:-10}"
ATTEMPTS="$PROJECT/.claude/agent-memory/refinement/attempts/$TASK_ID.jsonl"
mkdir -p "$(dirname "$ATTEMPTS")"
```

### Step 1: Discover (zero-memory ground-truth)

Read the project and construct a Verification Contract.

**Every /refine run rediscovers from scratch. No cached config. Ground truth only.**

1. **Read the project** — Glob, Read, Grep to understand structure.
2. **Find verification infrastructure** (in priority order):
   a. **Check for `.refine/score.sh`** — project-local scorer plugin (checked BEFORE other infrastructure).
      Projects can provide `.refine/score.sh` as a domain-specific scorer with JSON interface:
      `{"score": 0.0-1.0, "feedback": "...", "metrics": {...}}`.
      The project owns and evolves this scorer — it is the authoritative metric source when present.
   b. Test suites, build systems, linters, type checkers, verification scripts
3. **Construct the Verification Contract**:

```json
{
  "mode": "objective|tool-augmented|calibrated",
  "verify_cmd": "<command that produces measurable output>",
  "parse": "<how to extract the metric>",
  "metric": "<metric name>",
  "direction": "higher|lower|zero",
  "checks": ["<optional: {desc, tool, cmd, expect} for tool-augmented>"],
  "discovery_log": "<what you found and why>"
}
```

| Mode | When | Evaluator | Scoring |
|---|---|---|---|
| `objective` | Tests/build/lint exist | None | verify_cmd → parse → number |
| `tool-augmented` | Checks definable or no infra | evaluator subagent | checks[] + diff explore → score |
| `calibrated` | No objective metric (last resort) | evaluator subagent | `rubrics/default.yml` anchors |

4. **No infrastructure?** (tool-augmented): write tests that FAIL in current state (TDD RED).
5. **Calibrated mode gate** — before entering calibrated mode, the orchestrator MUST document in `discovery_log` the reason why objective and tool-augmented modes are impossible, list what alternatives were attempted (e.g. search for tests, probe for .refine/score.sh, check build tools), and confirm no `.refine/score.sh` exists. If any objective or tool-augmented path exists but was skipped, the Contract is invalid.
6. **No objective metric?** (calibrated): use `rubrics/default.yml` — last resort only.
7. **Validate**: run verify_cmd once. Must produce parseable output. Baseline must NOT be perfect.
8. **Freeze** into `.refinement-active`:

```bash
cat > .claude/.refinement-active <<MARKER
{
  "task_id": "$TASK_ID",
  "threshold": $THRESHOLD,
  "max_iterations": $MAX_ITER,
  "started": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "contract": { ... }
}
MARKER
```

**Contract is IMMUTABLE after this point.**

### Step 2: Baseline

Redirect output to file — autoresearch `> run.log 2>&1` pattern:

```bash
bash -c "<Contract.verify_cmd>" > .claude/.refine-output 2>&1
SCORE=<parse from .claude/.refine-output — only the number enters context>
echo "{\"score\":$SCORE,\"result\":\"Baseline\",\"feedback\":\"initial\"}" >> "$ATTEMPTS"
```

### Step 3: Modify (fresh subagent — context reset)

**Always spawn a fresh agent.** The main agent never reads code or sees edits.

Spawn Agent with prompt:
```
Task: <original task description>
Contract: mode=<mode>, metric=<metric>, direction=<direction>
Previous suggestion: <SUGGESTION from last Step 4, or "first iteration">
Attempts file: <$ATTEMPTS path>

Read the attempts file to see previous scores and feedback.
Avoid approaches that scored low. Build on approaches that scored high.
Make targeted changes. Run `git add` on changed files.
Return ONE LINE: what you changed.
```

If `--agent TYPE` specified, spawn that agent type instead of general-purpose.

The modifier's 1-line return is the only thing added to the main context.

### Step 4: Evaluate (output to file — score only enters context)

**objective mode** (no evaluator):
```bash
bash -c "<Contract.verify_cmd>" > .claude/.refine-output 2>&1
SCORE=<parse from .claude/.refine-output>
SUGGESTION=""
# Parse failure → SCORE=0
```

**tool-augmented / calibrated mode** (evaluator subagent):

Spawn the `evaluator` agent with ONLY:
- Frozen Contract JSON
- `git diff --cached` (or `git diff`)
- Calibration anchors (calibrated mode only)
- Instruction: "Read `$ATTEMPTS` for previous scores."

The evaluator writes full report to `.claude/.refine-eval.json` and returns ONLY:
```
{"score": 0.85, "suggestion": "one line of feedback"}
```

Parse: `SCORE` + `SUGGESTION` from the evaluator's return.

**Context isolation** — evaluator MUST NOT receive:
- The original `/refine` task description
- The modifier's reasoning
- Why changes were made

### Step 5: Keep or Discard

```bash
PREV_BEST=$(jq -s 'sort_by(.score)|last|.score//0' "$ATTEMPTS" 2>/dev/null || echo "0")
```

| Condition | Action |
|---|---|
| `SCORE > PREV_BEST` | **KEEP**: `git commit -m "refine: $TASK_ID iteration $N — score $SCORE"` |
| `SCORE <= PREV_BEST` | **DISCARD**: `git checkout -- .` |
| `SCORE >= THRESHOLD` | **ACCEPT**: exit loop |

### Step 6: Record

```bash
echo "{\"score\":$SCORE,\"result\":\"<KEEP|DISCARD>: $SUMMARY\",\"feedback\":\"$SUGGESTION\"}" >> "$ATTEMPTS"
```

### Step 7: Check Termination

```bash
ITERATION=$(wc -l < "$ATTEMPTS" 2>/dev/null || echo "0")
```

| Condition | Action |
|---|---|
| `SCORE >= THRESHOLD` | **ACCEPT** — `rm -f .claude/.refinement-active`, report |
| `ITERATION >= MAX_ITER` | **STOP** — `rm -f .claude/.refinement-active`, report best |
| Otherwise | Continue to Step 3 |

On exit: `jq -s 'sort_by(.score)|last' "$ATTEMPTS"`

### Next Iteration

Return to **Step 3** with:
- Same task description
- Updated SUGGESTION from latest Step 4
- Modifier reads $ATTEMPTS itself in its fresh context

**Continue iterating. Do not ask for permission.**

## Discovery Protocol

1. **Zero-memory** — rediscover from scratch every run
2. **Contract is immutable** — once frozen, no modification
3. **Metric over judgment** — objective if available; calibrated is last resort
4. **Baseline must not be perfect** — Contract must distinguish improvement
5. **Generated tests must fail** — TDD RED principle
6. **Parse failure = score 0** — treat as crash, DISCARD

## Design Principles

1. **Thin orchestrator** — main agent is loop driver only; heavy work in fresh subagents
2. **Context reset per iteration** — modifier and evaluator get fresh context each time
3. **Output to file, not context** — `verify_cmd > .refine-output 2>&1` (autoresearch pattern)
4. **Contract as prepare.py** — Discovery builds it, loop uses it immutably
5. **Generator ≠ Evaluator** — context-isolated (Anthropic GAN principle)
6. **Zero-memory discovery** — every run reads project ground truth
7. **Metric over judgment** — numbers from tools, not LLM opinion
8. **NEVER STOP** — iterate until threshold or max_iter
9. **No dead data** — only store what has a consumer (score, result, feedback)
10. **Self-contained** — SKILL.md + evaluator agent + rubric fallback. Portable with `.claude/`
