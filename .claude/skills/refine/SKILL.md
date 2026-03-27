---
name: refine
description: Iterative refinement loop for code-producing agents with deterministic scoring
argument-hint: "<agent-type> <task-description> [--max-iter N] [--threshold 0.8] [--project PATH]"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# /refine — Deterministic Iterative Refinement Loop

Runs a code-producing agent in a loop with deterministic quality scoring.
Each iteration: run agent → score via tools → record → build trajectory → re-run with feedback.

## Arguments

- `<agent-type>`: One of the code-producing agents (see Step 0a)
- `<task-description>`: What the agent should accomplish
- `--max-iter N`: Maximum iterations (default: 5)
- `--threshold T`: Target score 0.0-1.0 (default: 0.85)
- `--project PATH`: Project path for verification (default: auto-detect)

## Protocol

### Step 0a: Agent Type Check

Only code-producing agents can be refined — they produce executable output with deterministic reward signals.

```
CODE_PRODUCING_AGENTS: build-error-resolver, tdd-guide, refactor-cleaner, e2e-runner
```

If the requested agent is NOT in the list above:
- Respond: "Cannot refine `<agent>`. Only code-producing agents support deterministic refinement: build-error-resolver, tdd-guide, refactor-cleaner, e2e-runner. Other agents produce natural language judgments without measurable quality signals."
- Do NOT create the `.refinement-active` marker.
- Stop immediately.

### Step 0b: Infrastructure Check

The refinement data layer (scripts/refinement/) is only installed in <workspace>.
Other projects receive the /refine skill via .claude/ sync but lack the infrastructure.

```bash
SCRIPTS_DIR="${CLAUDE_PROJECT_DIR:-/workspaces}/scripts/refinement"
```

If `$SCRIPTS_DIR` does not exist OR `verify-score.sh` is not present:
- Respond: "NOTE: Refinement infrastructure not found at `$SCRIPTS_DIR`. The /refine skill exists in this project's `.claude/` but the data layer (`scripts/refinement/`) is not installed. Run /refine from the <workspace> workspace, or copy `scripts/refinement/` to this project."
- Do NOT create the `.refinement-active` marker.
- Stop immediately.

### Step 0c: Initialize

```bash
TASK_ID="refine-$(date +%Y%m%d-%H%M%S)"
PROJECT="${PROJECT:-$(pwd)}"
THRESHOLD="${THRESHOLD:-0.85}"
MAX_ITER="${MAX_ITER:-5}"

# Create active marker (checked by refinement-gate.sh Stop hook)
echo "{\"task_id\":\"$TASK_ID\",\"threshold\":$THRESHOLD,\"max_iterations\":$MAX_ITER,\"started\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > .claude/.refinement-active
```

### Step 1: Run Agent

Spawn the target agent with the user's task description:

```
Agent(prompt=<task-description>, subagent_type=<agent-type>)
```

### Step 2: Score (100% Deterministic)

Run the verification pipeline — this is the ONLY source of scores. No LLM evaluation.

```bash
RESULT=$(bash scripts/refinement/verify-score.sh --project "$PROJECT" --score)
SCORE=$(echo "$RESULT" | jq -r '.score')
FEEDBACK=$(echo "$RESULT" | jq -r '.feedback')
```

### Step 2.5: Degradation Check

Compare current score against previous best. If the score dropped, warn about potential degradation.

```bash
PREV_BEST=$(bash scripts/refinement/memory-ops.sh best --task "$TASK_ID" | jq -r '.score // "0"')
```

If `SCORE < PREV_BEST`:
- Output: "**DEGRADATION DETECTED**: score dropped `$PREV_BEST` → `$SCORE`. This iteration's changes may have introduced regressions. Recommended: review changes with `git diff`, consider `git checkout -- .` to revert this iteration."
- The loop continues (warning only — the agent decides whether to act on it).

### Step 3: Record

Store the attempt with its score and structural feedback:

```bash
bash scripts/refinement/memory-ops.sh add \
  --task "$TASK_ID" \
  --agent "<agent-type>" \
  --score "$SCORE" \
  --result "<one-line summary of what changed>" \
  --feedback "$FEEDBACK"
```

### Step 4: Check Termination

```bash
ITERATION=$(bash scripts/refinement/memory-ops.sh count --task "$TASK_ID")
```

If `score >= threshold` OR `iteration >= max_iter`:
- Remove the active marker: `rm -f .claude/.refinement-active`
- Report final result: `bash scripts/refinement/memory-ops.sh best --task "$TASK_ID"`
- **DONE** — exit the loop.

### Step 5: Build Trajectory + Re-run

Build the improvement trajectory showing previous attempts (worst→best):

```bash
TRAJECTORY=$(bash scripts/refinement/trajectory.sh --task "$TASK_ID" --max 5)
```

Re-run the agent with the trajectory as context:

```
Agent(
  prompt="<original-task-description>

Previous attempts and their scores (worst to best):
$TRAJECTORY

Fix the specific issues shown in the feedback above. Focus on the remaining errors.",
  subagent_type=<agent-type>
)
```

Return to **Step 2**.

## Design Principles

1. **Code-producing agents only** — deterministic rewards exist only where output is executable code
2. **100% deterministic scoring** — verify-score.sh is the sole score source; no LLM evaluation
3. **Structural feedback** — raw tool errors (ruff, pytest, mypy) in CDATA, not summaries
4. **Zero environment dependencies** — jq + bash builtins only
5. **Existing system safety** — no `.refinement-active` marker = NOP for all hooks
