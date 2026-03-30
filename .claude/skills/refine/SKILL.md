---
name: refine
description: Autonomous iterative refinement loop — autoresearch pattern with Opus rubric evaluation
argument-hint: "<task-description> [--max-iter N] [--threshold 0.85] [--project PATH] [--agent TYPE]"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# /refine — Autonomous Iterative Refinement Loop

Autoresearch pattern: modify → verify → evaluate → keep/discard → repeat.

Core mapping from [autoresearch](https://github.com/karpathy/autoresearch):

| autoresearch | /refine |
|---|---|
| `prepare.py` (immutable evaluation) | `rubrics/default.yml` (immutable rubric) |
| `val_bpb` (single scalar metric) | Opus score (0.0-1.0) |
| `uv run train.py` (run experiment) | Claude runs tools (Bash, Read, Grep) |
| `grep "^val_bpb:" run.log` (read result) | Claude reads tool output as evidence |
| `new < old` → keep | `new > prev_best` → keep |
| `git reset` → discard | `git checkout -- .` → discard |

## Arguments

- `<task-description>`: What to improve (required)
- `--max-iter N`: Maximum iterations (default: 10)
- `--threshold T`: Target score 0.0-1.0 (default: 0.85)
- `--project PATH`: Project path (default: CLAUDE_PROJECT_DIR)
- `--agent TYPE`: Agent to spawn for code changes (default: none — main agent acts directly)

## Protocol

### Step 0: Initialize

```bash
TASK_ID="refine-$(date +%Y%m%d-%H%M%S)"
PROJECT="${PROJECT:-$CLAUDE_PROJECT_DIR}"
THRESHOLD="${THRESHOLD:-0.85}"
MAX_ITER="${MAX_ITER:-10}"
REFINE_DIR="${PROJECT}/.claude/skills/refine"

# refinement-gate marker (Stop hook checks this)
echo "{\"task_id\":\"$TASK_ID\",\"threshold\":$THRESHOLD,\"max_iterations\":$MAX_ITER,\"started\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > .claude/.refinement-active
```

### Step 1: Baseline (attempt 0)

Evaluate the current state BEFORE any changes. This establishes the baseline score.

1. **Read the project** — understand what exists (Read, Glob, Grep)
2. **Run verification tools** — whatever is appropriate for this project:
   - Python: `ruff check`, `mypy`, `pytest`
   - TypeScript: `npm test`, `npm run build`
   - Claude system: `bash .claude/tests/run-all.sh`
   - Documents: read content, check structure
   - Use your judgment. Run what makes sense. Do NOT invent tools that don't exist.
3. **Read the rubric** — `cat "$REFINE_DIR/rubrics/default.yml"`
4. **Evaluate** — score each rubric dimension against the evidence you gathered.
   Apply the rubric evaluation protocol (see Evaluation section below).
5. **Record baseline**:
```bash
bash "$REFINE_DIR/memory-ops.sh" add \
  --task "$TASK_ID" --agent "baseline" --score "$BASELINE_SCORE" \
  --result "Initial state" --feedback "<one-line summary of current state>"
```

### Step 2: Modify (autoresearch pattern)

**If `--agent` specified**: Spawn the agent with the task description.
**If no `--agent`** (default): Act directly — read code, make changes with Edit/Write.

After modification, `git add` changed files (do NOT commit yet — commit only on keep).

### Step 3: Evaluate (the immutable evaluation — prepare.py analog)

This is the critical step. Like autoresearch's `prepare.py`, the rubric is IMMUTABLE.

#### 3a. Collect evidence using YOUR tools

Run whatever tools are appropriate. Examples (not prescriptive):
- `git diff HEAD` — see what changed
- `bash -c "cd $PROJECT && pytest tests/ -q"` — run tests
- `bash -c "cd $PROJECT && ruff check src/"` — lint
- Read specific files to check correctness

The tool outputs ARE your evidence. No separate evidence-collection script.

#### 3b. Read the immutable rubric

```bash
cat "$REFINE_DIR/rubrics/default.yml"
```

#### 3c. Score each dimension

For EACH dimension in the rubric:
1. Read the anchor criteria
2. Match evidence to an anchor level (0.0, 0.25, 0.5, 0.75, 1.0)
3. **MUST cite specific evidence** — tool output line, file:line, or diff hunk
4. If no evidence can be cited → score is 0.0

Output evaluation as JSON:
```json
{
  "correctness": {"score": 0.75, "evidence": "pytest: 10 passed, 1 failed (test_edge_case)"},
  "improvement": {"score": 0.75, "evidence": "diff: added error handling for zero division"},
  "completeness": {"score": 0.5, "evidence": "handles main case, missing timeout scenario"},
  "consistency": {"score": 1.0, "evidence": "follows existing snake_case convention"}
}
```

#### 3d. Compute final score

Weighted average per rubric dimension weights → single float (0.0-1.0).

### Step 4: Keep or Discard (binary decision)

```bash
PREV_BEST=$(bash "$REFINE_DIR/memory-ops.sh" best --task "$TASK_ID" | jq -r '.score // "0"')
```

| Condition | Action | autoresearch analog |
|-----------|--------|---------------------|
| `SCORE > PREV_BEST` | **KEEP** — `git commit -m "refine: $TASK_ID iteration $N — score $SCORE"` | `val_bpb` improved → keep commit |
| `SCORE <= PREV_BEST` | **DISCARD** — `git checkout -- .` | `val_bpb` worse → `git reset` |
| `SCORE >= THRESHOLD` | **ACCEPT** — exit loop | N/A (autoresearch runs forever) |

### Step 5: Record

```bash
bash "$REFINE_DIR/memory-ops.sh" add \
  --task "$TASK_ID" --agent "${AGENT:-self}" --score "$SCORE" \
  --result "<one-line: what changed, KEEP/DISCARD>" \
  --feedback "<evaluation summary with key evidence>"
```

### Step 6: Check Termination

```bash
ITERATION=$(bash "$REFINE_DIR/memory-ops.sh" count --task "$TASK_ID")
```

| Condition | Action |
|-----------|--------|
| `SCORE >= THRESHOLD` | **ACCEPT** — remove marker, report success |
| `ITERATION >= MAX_ITER` | **STOP** — remove marker, report best result |
| Otherwise | Continue to Step 7 |

On ACCEPT or STOP:
```bash
rm -f .claude/.refinement-active
bash "$REFINE_DIR/memory-ops.sh" best --task "$TASK_ID"
```

### Step 7: Trajectory + Next Iteration

```bash
TRAJECTORY=$(bash "$REFINE_DIR/trajectory.sh" --task "$TASK_ID" --max 5)
```

Return to **Step 2** with trajectory as context. Use it to:
- Avoid repeating failed approaches (DISCARD entries)
- Build on successful attempts (KEEP entries)
- Focus on dimensions with lowest scores

**Continue iterating. Do not ask for permission to continue.**

## Evaluation Protocol (self-evaluation bias defense)

These rules are IMMUTABLE — they correspond to autoresearch's `prepare.py` being unmodifiable.

1. **Rubric is law** — score ONLY against anchor criteria in `rubrics/default.yml`. No subjective judgment.
2. **Evidence-first** — every dimension score MUST cite specific tool output or file:line. No evidence = 0.0.
3. **No interpolation** — score must be one of {0.0, 0.25, 0.5, 0.75, 1.0}. No 0.6 or 0.8.
4. **Evaluate the DIFF** — judge changes made, not the entire codebase.
5. **Tool output trumps intuition** — if tests fail, correctness cannot be 1.0 regardless of code quality.
6. **Trajectory calibrates** — past scores set expectations. A score higher than all previous attempts needs stronger evidence.

## Design Principles

1. **autoresearch core**: modify → verify → evaluate → keep/discard. Git is the safety net.
2. **Opus as prepare.py**: Claude evaluates against immutable rubric, citing tool evidence.
3. **No arbitrary scripts**: Claude's native tools (Bash, Read, Edit, Grep) are the only instruments.
4. **Binary decision**: score > prev_best → keep, else → discard. No complex formulas.
5. **NEVER STOP**: iterate until threshold or max_iter. Do not pause for confirmation.
6. **Self-contained**: SKILL.md + rubric + memory-ops + trajectory. Portable with `.claude/`.
