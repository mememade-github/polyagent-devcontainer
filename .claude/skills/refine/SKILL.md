---
name: refine
description: Autonomous exploratory improvement loop — thin orchestrator with fresh-context agents
argument-hint: "<task-description> [--max-iter N] [--threshold 0.85] [--project PATH] [--agent TYPE]"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# /refine — Autonomous Exploratory Improvement Loop

Thin orchestrator: main agent drives the loop; all heavy work runs in fresh subagents per iteration.

**Exploratory, not corrective.** Each iteration discovers remaining gaps, then improves the
highest-priority one. The loop converges as gaps are resolved, not by retrying the same fix.

## Arguments

- `<task-description>`: What to improve (required — can be broad: "production-level quality")
- `--max-iter N`: Maximum iterations (default: 10)
- `--threshold T`: Target score 0.0-1.0 (default: 0.85)
- `--project PATH`: Project path (default: CLAUDE_PROJECT_DIR). When `--project PATH` is used, all marker and state files (`.refinement-active`, attempts JSONL, `.refine-output`) are created relative to that PATH, not CLAUDE_PROJECT_DIR.
- `--agent TYPE`: Agent type for modifications (default: general-purpose)

## State

Attempt history in a single JSONL file — no external scripts:

```
.claude/agent-memory/refinement/attempts/$TASK_ID.jsonl
```

Each line: `{"score":0.4,"gaps":["R3","R7","R12"],"result":"KEEP: fixed search placeholder","feedback":"R3 resolved; R7,R12 remain"}`

Three inline operations cover all needs:
```bash
# Record:  echo '{"score":...,"gaps":[...],"result":"...","feedback":"..."}' >> $ATTEMPTS
# Best:    jq -s 'sort_by(.score)|last|.score//0' $ATTEMPTS
# Count:   wc -l < $ATTEMPTS
```

## Protocol

### Step 0: Initialize (pre-flight checks)

**Pre-flight git state check**: before starting the loop, verify git status is clean.
If uncommitted or modified changes exist, **stash or abort** — DISCARD uses `git checkout` which destroys unsaved work.

```bash
# Pre-flight: fail if dirty working tree
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: uncommitted/dirty changes — stash or commit before /refine"
  exit 1  # abort to protect unsaved modifications
fi

# Check for stale .refinement-active marker from a previous crash/abort
if [ -f .claude/.refinement-active ]; then
  echo "WARNING: stale .refinement-active marker already exists (previous crash?)"
  echo "Remove it manually after verifying no other refine session is running."
  exit 1
fi

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
      If `.refine/score.sh` hits an error, fails, or crashes internally, the scorer must still output `{"score":0}` — it should never crash silently or produce no output.
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
SCORE=<parse .score from .refine-output JSON>
# Extract failing check IDs from metrics: keys where value is "fail"
GAPS=$(jq -r '.metrics // {} | to_entries | map(select(.value=="fail")) | map(.key)' .claude/.refine-output)
# If score.sh doesn't output metrics, GAPS=[] and Audit agent discovers gaps from feedback text
echo "{\"score\":$SCORE,\"gaps\":$GAPS,\"result\":\"Baseline\",\"feedback\":\"initial\"}" >> "$ATTEMPTS"
```

**GAPS extraction**: The scorer's `metrics` field maps check IDs to "pass"/"fail". GAPS is the list of IDs where value is "fail". When `metrics` is absent, GAPS defaults to `[]` and the Audit agent (Step 3) discovers gaps by reading the feedback text and investigating the codebase.

### Step 3: Audit (fresh subagent — gap discovery)

> **This is the exploratory core.** Each iteration rediscovers what remains to improve.

Spawn an **Audit agent** (Explore subagent type — read-only tools: Read, Grep, Glob, Bash) with:
```
Project: <PROJECT path>
Task context: <original task description>
Scorer output file: <PROJECT>/.claude/.refine-output
Attempts file: <$ATTEMPTS path>
Current GAPS: <$GAPS array from last evaluation>

PROTOCOL:
1. Read .claude/.refine-output to identify which checks are FAILING (metrics with "fail" value).
2. Read $ATTEMPTS to see which gaps were addressed in prior iterations — avoid re-diagnosing resolved gaps.
3. For each failing check, read the relevant source code, config, or service state to gather EVIDENCE.
   - Code checks: Read the referenced file:line, understand the expected vs actual state.
   - Service checks: Describe what the check expects (do NOT run destructive commands).
4. REGRESSION CHECK: compare current GAPS to previous iteration's GAPS.
   If a previously-passing check now fails, flag it as REGRESSION (highest priority).
5. Rank remaining failures: REGRESSION > CRITICAL (health, API) > STANDARD (integration) > COSMETIC (branding).
6. Select the single highest-priority cluster (1-3 related gaps that share a root cause).

RETURN FORMAT (structured text, not JSON):
PRIORITY_GAP: <gap ID(s)> — <one-line description>
EVIDENCE: <what you observed — actual file content, config values, error messages>
ROOT_CAUSE: <why it fails — diagnosed from evidence, not assumed>
REGRESSION: <yes/no — did any previously-passing check regress?>
REMAINING: <count and list of unresolved gaps>
```

The Audit agent's return enters the main context as the **Gap Report**.

**Why a separate Audit step?**
- Prevents the Modifier from trying to fix everything at once (0→1.0 jumps)
- Forces evidence gathering before modification — structurally enforced by agent separation
- Each iteration focuses on one priority cluster → gradual, stable convergence
- Regression detection: previously passing checks that now fail are flagged as highest priority
- Read-only tools: the Audit agent inspects but cannot modify code

### Step 4: Modify (fresh subagent — focused improvement)

**Always spawn a fresh agent.** The main agent never reads code or sees edits.

Spawn Agent with prompt:
```
Task: <original task description>
Contract: mode=<mode>, metric=<metric>, direction=<direction>
Gap Report: <from Step 3 — PRIORITY_GAP, EVIDENCE, ROOT_CAUSE>
Attempts file: <$ATTEMPTS path>

RULES:
1. Address ONLY the PRIORITY_GAP identified in the Gap Report.
   Do NOT fix other gaps — they will be addressed in future iterations.
2. Use the EVIDENCE and ROOT_CAUSE from the audit to guide your fix.
   Do NOT assume — verify against actual state before changing code.
3. Read the attempts file to avoid approaches that scored low.
4. Run `git add` on changed files.
5. Return ONE LINE: what you changed and which gap it addresses.
```

If `--agent TYPE` specified, spawn that agent type instead of general-purpose.

The modifier's 1-line return is the only thing added to the main context.

### Step 5: Evaluate (output to file — score only enters context)

**objective mode** (no evaluator):
```bash
timeout 300 bash -c "<Contract.verify_cmd>" > .claude/.refine-output 2>&1
SCORE=<parse .score from .refine-output JSON>
GAPS=$(jq -r '.metrics // {} | to_entries | map(select(.value=="fail")) | map(.key)' .claude/.refine-output)
SUGGESTION=<parse .feedback from .refine-output JSON>
# Parse failure → SCORE=0, GAPS=[]
# Timeout on verify_cmd execution → treat as SCORE=0 (default 300s, adjust per project)
```

**Timeout for verify/score command execution**: always wrap verify_cmd with `timeout` to prevent hangs (e.g. build loops, network waits). Default 300 seconds.

**JSON extraction from mixed output**: scorer stdout may contain warnings or debug lines before the JSON result. To parse robustly, extract the last line of JSON from output — use `tail -1` or `grep -o '{.*}'` to filter the final JSON object, then parse with `jq`.

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

### Step 6: Keep or Discard

```bash
PREV_BEST=$(jq -s 'sort_by(.score)|last|.score//0' "$ATTEMPTS" 2>/dev/null || echo "0")
```

| Condition | Action |
|---|---|
| `SCORE > PREV_BEST` | **KEEP**: `git commit -m "refine: $TASK_ID iteration $N — score $SCORE"` |
| `SCORE <= PREV_BEST` | **DISCARD**: `git checkout -- . && git clean -fd` (remove untracked files too) |
| `SCORE >= THRESHOLD` | **ACCEPT**: exit loop |

### Step 7: Record

```bash
echo "{\"score\":$SCORE,\"gaps\":$GAPS,\"result\":\"<KEEP|DISCARD>: $SUMMARY\",\"feedback\":\"$SUGGESTION\"}" >> "$ATTEMPTS"
```

### Step 8: Check Termination

```bash
ITERATION=$(wc -l < "$ATTEMPTS" 2>/dev/null || echo "0")
```

| Condition | Action |
|---|---|
| `SCORE >= THRESHOLD` | **ACCEPT** — `rm -f .claude/.refinement-active`, report |
| `ITERATION >= MAX_ITER` | **STOP** — `rm -f .claude/.refinement-active`, report best |
| Otherwise | Continue to Step 3 |

**Mandatory: clean up `.refinement-active` on every exit path.** Whether the loop ends by ACCEPT, STOP, or error, you must always `rm -f .claude/.refinement-active` before reporting results.

On exit: `jq -s 'sort_by(.score)|last' "$ATTEMPTS"`

### Next Iteration

Return to **Step 3** (Audit) with:
- Same task description
- Fresh audit of current state (what gaps remain after the last modification?)
- Modifier reads $ATTEMPTS itself in its fresh context

**Continue iterating. Do not ask for permission.**

## Convergence Model

The exploratory loop produces **gradual convergence**, not sudden jumps:

```
Iteration 0 (Baseline):  score=0.20  gaps=[R1,R3,R5,R7,R10,R12,R16]  (7 gaps)
Iteration 1 (KEEP):      score=0.35  gaps=[R3,R5,R7,R10,R16]          (5 gaps — R1,R12 resolved)
Iteration 2 (KEEP):      score=0.55  gaps=[R5,R7,R16]                 (3 gaps — R3,R10 resolved)
Iteration 3 (DISCARD):   score=0.50  gaps=[R5,R7,R10,R16]             (regression: R10 returned)
Iteration 4 (KEEP):      score=0.70  gaps=[R7,R16]                    (2 gaps)
Iteration 5 (KEEP):      score=0.90  gaps=[]                          (ACCEPT)
```

Key properties:
- **Monotonic gap resolution**: each KEEP iteration resolves 1-3 gaps
- **Regression detection**: if a previously-passing check fails, DISCARD protects progress
- **Focused scope**: modifier addresses one cluster per iteration, preventing unstable bulk changes
- **Audit trail**: attempts JSONL records which gaps were open at each step

**Anti-pattern detection (enforced in Step 6):**

After a KEEP, if the score jumped from baseline to >= threshold in a single iteration:
```
JUMP = SCORE - BASELINE_SCORE
if JUMP >= 0.5 and ITERATION == 1:
  # Log warning in attempts JSONL
  echo '{"warning":"single-iteration-convergence","jump":'$JUMP'}' >> "$ATTEMPTS"
  # Do NOT block — the improvement is real. But signal scorer quality concern.
```

This signals one of:
- Scorer checks are too coarse (binary pass/fail → no gradient) — add weighted/graduated checks
- Modifier scope is unconstrained (fixing everything at once) — Audit step should have constrained it
- Task is too narrowly scoped for the iterative loop — use direct edit instead of /refine

## Discovery Protocol

1. **Zero-memory** — rediscover from scratch every run
2. **Contract is immutable** — once frozen, no modification
3. **Metric over judgment** — objective if available; calibrated is last resort
4. **Baseline must not be perfect** — Contract must distinguish improvement.
   Recalibration: if baseline is perfect (1.0), add stricter checks or introduce additional criteria to lower the baseline score before proceeding.
   If baseline already meets or exceeds the threshold (e.g., 0.93 >= 0.85), threshold must be raised above baseline or the scorer refined with more granular checks to lower the baseline — otherwise there is nothing to improve.
5. **Generated tests must fail** — TDD RED principle
6. **Parse failure = score 0** — treat as crash, DISCARD

## Scorer Design Guidelines

> Empirical: binary pass/fail checks produce 0→1.0 jumps in 1 iteration, underutilizing the iterative loop.

When `.refine/score.sh` exists or is being created, follow these principles:

### Granularity

Each check should produce **graduated scores**, not binary pass/fail. A check that can only be 0 or 1 provides no signal about partial progress.

| Anti-pattern | Improved |
|---|---|
| `if healthy; then pass; else fail` | `if healthy && fast; then pass; elif healthy; then partial(0.5); else fail` |
| 20 binary checks → average | Weighted checks with partial credit per check |

### Weighting

Not all checks are equal. Assign weights by severity:

```bash
# Example: weighted scoring
CRITICAL_WEIGHT=3   # health, API response, core function
STANDARD_WEIGHT=2   # integration, data flow
COSMETIC_WEIGHT=1   # branding, deprecated code, formatting

WEIGHTED_SUM=$((CRITICAL_PASS * CRITICAL_WEIGHT + STANDARD_PASS * STANDARD_WEIGHT + COSMETIC_PASS * COSMETIC_WEIGHT))
WEIGHTED_TOTAL=$((CRITICAL_TOTAL * CRITICAL_WEIGHT + STANDARD_TOTAL * STANDARD_WEIGHT + COSMETIC_TOTAL * COSMETIC_WEIGHT))
SCORE=$(awk "BEGIN {printf \"%.2f\", $WEIGHTED_SUM / $WEIGHTED_TOTAL}")
```

### Separation of Concerns

Separate **remote** (server/service) checks from **local** (code/file) checks. This enables:
- Running local checks without network access
- Isolating failures to network vs code issues
- Faster iteration when only code changes are needed

### Scorer Evolution

The scorer is **outside** the Contract — it can evolve between /refine runs.
Within a single /refine run, the Contract (which references `score.sh`) is immutable,
but the scorer itself improves across runs as the project matures:

```
Run 1: score.sh has R1-R4 (health, title, placeholder, user API)
Run 2: score.sh adds R5-R9 (conversation, static, endpoints)
Run 3: score.sh adds R10-R14 (code quality, branding, integration)
```

Each new run discovers the evolved scorer and builds a fresh Contract around it.

## Evidence-Before-Modification Principle

> Empirical: modifications without prior evidence gathering produce unstable fixes.

The Audit step (Step 3) ensures evidence is always gathered before modification.
The modifier subagent (Step 4) receives pre-gathered evidence in the Gap Report.

This is structurally enforced: the modifier CANNOT skip evidence gathering because
it receives evidence from a separate Audit agent, not from its own assumptions.

## Design Principles

1. **Exploratory over corrective** — discover gaps, then improve; don't just fix stated problems
2. **Thin orchestrator** — main agent is loop driver only; heavy work in fresh subagents
3. **Audit → Modify separation** — gap discovery and code modification are different agents with different contexts
4. **Context reset per iteration** — audit, modifier, and evaluator get fresh context each time
5. **Output to file, not context** — `verify_cmd > .refine-output 2>&1` (autoresearch pattern)
6. **Contract as prepare.py** — Discovery builds it, loop uses it immutably
7. **Generator ≠ Evaluator** — context-isolated (Anthropic GAN principle)
8. **Zero-memory discovery** — every run reads project ground truth
9. **Metric over judgment** — numbers from tools, not LLM opinion
10. **Gradual convergence** — one gap cluster per iteration, not bulk fixes
11. **NEVER STOP** — iterate until threshold or max_iter
12. **No dead data** — only store what has a consumer (score, gaps, result, feedback)
13. **Self-contained** — SKILL.md + evaluator agent + rubric fallback. Portable with `.claude/`
14. **Evidence before modification** — structurally enforced by Audit→Modify separation
