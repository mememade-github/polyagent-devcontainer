---
name: refine
description: Autonomous exploratory improvement loop — thin orchestrator with fresh-context agents
argument-hint: "<task-description> [--max-iter N] [--threshold 0.85] [--project PATH] [--agent TYPE]"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# /refine — Autonomous Exploratory Improvement Loop

Thin orchestrator: the main agent drives a modify→evaluate→keep/discard loop;
all heavy work (audit, modify, evaluate) runs in **fresh subagents** per
iteration so the orchestrator context stays minimal. **Exploratory, not
corrective** — each iteration rediscovers the highest-priority remaining gap and
improves it; the loop converges as gaps resolve, not by retrying one fix.

## Arguments

- `<task-description>` (required) — what to improve (may be broad).
- `--max-iter N` (default 10) · `--threshold T` (default 0.85) ·
  `--project PATH` (default: resolved root) · `--agent TYPE` (default
  general-purpose, used for the Modify step).

## Step 0a: Vendor and path resolution

Marker/attempts/output paths resolve to match whichever host's Stop-hook gate is
watching, so the mirrored Codex copy works without `$CLAUDE_PROJECT_DIR`:

```bash
PROJECT="${PROJECT:-${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}}"
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  AGENT_VENDOR=claude
elif [ -n "${CODEX_PROJECT_DIR:-}" ] || [ "${CODEX_CI:-}" = "1" ] || [ -n "${CODEX_THREAD_ID:-}" ]; then
  AGENT_VENDOR=codex
elif [ "${AGENT_VENDOR:-}" != "claude" ] && [ "${AGENT_VENDOR:-}" != "codex" ]; then
  echo "ERROR: cannot identify Claude or Codex host; set AGENT_VENDOR=claude|codex" >&2
  exit 2
fi

if [ "$AGENT_VENDOR" = "codex" ]; then
  STATE_DIR="$PROJECT/.codex/state"; MARKER="$STATE_DIR/refinement-active"
  ATTEMPTS_DIR="$STATE_DIR/refinement/attempts"
else
  STATE_DIR="$PROJECT/.claude";      MARKER="$STATE_DIR/.refinement-active"
  ATTEMPTS_DIR="$STATE_DIR/agent-memory/refinement/attempts"
fi
OUTPUT="$STATE_DIR/.refine-output"; EVAL_JSON="$STATE_DIR/.refine-eval.json"
```

`CODEX_PROJECT_DIR` is optional in real Codex sessions, so `CODEX_CI` and
`CODEX_THREAD_ID` are also authoritative host signals. These paths match the
Claude and Codex `refinement-gate.sh` markers exactly.

## Step 0b: Fresh-role isolation

- **Claude**: use a fresh `Agent` subagent for Audit, Modify, and Evaluate.
- **Codex**: invoke `scripts/meta/run-isolated-role.sh` separately for `audit`,
  `modify`, and `evaluate`. The helper starts a new `codex exec --ephemeral`
  process every time with `--ignore-user-config --disable hooks`; authentication
  still comes from `CODEX_HOME`, while user config and project hooks cannot
  pollute or recursively trigger child automation. Evaluate starts outside the
  repository to prevent recursive AGENTS.md loading. Audit and Evaluate receive
  only read-only evidence; Modify receives the Gap Report and task scope. Never
  use the parent Codex context as its own evaluator. Codex subagents are
  supported, but the subprocess remains intentional here because the evaluator
  must receive an exact, minimal evidence channel in interactive and
  non-interactive runs.
- In a DevContainer where bubblewrap is unavailable, the child may use
  `--dangerously-bypass-approvals-and-sandbox`. This is a compatibility fallback,
  not a security boundary: the helper rejects Audit/Evaluate if HEAD, the index,
  or any tracked/untracked project-tree file changes, including guarded
  gitignored files, missing tracked files, file mode, and symlink state.
  High-churn generated paths such as `.codex/state`, refinement attempts,
  dependency caches, and build outputs are excluded. The single authorized
  output file is excluded from that comparison.

## Step 0c: Pre-flight

- **Git must be completely clean**, including untracked files, because DISCARD
  removes files created by the current iteration. `git status --porcelain` must
  be empty or the run aborts.
- **Stale marker** — if `$MARKER` exists, abort (previous crash); remove it
  manually after confirming no other refine session is running.

```bash
TASK_ID="refine-$(date +%Y%m%d-%H%M%S)"
THRESHOLD="${THRESHOLD:-0.85}"; MAX_ITER="${MAX_ITER:-10}"
ATTEMPTS="$ATTEMPTS_DIR/$TASK_ID.jsonl"; mkdir -p "$ATTEMPTS_DIR"
```

## Step 1: Discover → Verification Contract

Rediscover ground truth every run (no cached config). Read the project
(Glob/Read/Grep), then build a Contract:

| Mode | When | Evaluator | Scoring |
|---|---|---|---|
| `objective` | tests/build/lint exist | none | verify_cmd → parse → number |
| `tool-augmented` | checks definable / no infra | evaluator subagent | checks[] + diff explore |
| `calibrated` | no objective metric (last resort) | evaluator subagent | rubric anchors |

Prefer `objective`. If a project-local `.refine/score.sh` exists (JSON out:
`{"score":0-1,"feedback":"...","metrics":{"<id>":"pass|fail"}}`) it is
authoritative. Validate: run `verify_cmd` once — output must parse and the
baseline must NOT already be perfect (else add stricter checks or raise the
threshold). Freeze the Contract into `$MARKER` (immutable thereafter):

```bash
cat > "$MARKER" <<EOF
{"task_id":"$TASK_ID","threshold":$THRESHOLD,"max_iterations":$MAX_ITER,"contract":{ <mode,verify_cmd,parse,metric,direction,checks,discovery_log> }}
EOF
```

## Step 2: Baseline

```bash
bash -c "<Contract.verify_cmd>" > "$OUTPUT" 2>&1
SCORE=<parse .score>; GAPS=<failing check IDs, or []>
echo "{\"score\":$SCORE,\"gaps\":$GAPS,\"result\":\"Baseline\",\"feedback\":\"initial\"}" >> "$ATTEMPTS"
```

## Step 3: Audit (fresh Explore subagent — read-only)

Spawn a fresh Explore role (Claude Agent or Codex ephemeral subprocess) given:
project, task context,
`$OUTPUT`, `$ATTEMPTS`, current GAPS. It must: identify which checks fail; read
`$ATTEMPTS` to skip already-resolved gaps; gather evidence across code/config/
infra to find the TRUE root cause (code adapting to an infra limit is a
workaround, not a fix); flag any **regression** (a previously-passing check now
failing) as highest priority; select ONE gap cluster (1–3 related gaps). Returns
a Gap Report: `PRIORITY_GAP / EVIDENCE / ROOT_CAUSE / REGRESSION / REMAINING`.

This separation forces evidence-before-modification and prevents 0→1.0 bulk jumps.

## Step 4: Modify (fresh subagent — focused)

Spawn a fresh Modify role with: task, Contract summary, the
Gap Report, `$ATTEMPTS` path. Rules: address **only** the `PRIORITY_GAP`; use the
evidence (don't assume); `git add` changed files; return ONE line (what changed +
which gap). The main agent never reads code or edits directly.

## Step 5: Evaluate

**objective mode** (no evaluator):
```bash
timeout 300 bash -c "<Contract.verify_cmd>" > "$OUTPUT" 2>&1
SCORE=<parse .score>; GAPS=<failing IDs>; SUGGESTION=<parse .feedback>
# parse failure or timeout → SCORE=0
```

**tool-augmented / calibrated** — spawn a fresh evaluator role with **ONLY**:
Contract JSON, `git diff --cached`, calibration anchors (calibrated only), and
"read `$ATTEMPTS` for previous scores", plus the `$EVAL_JSON` output path. It
writes its full report to `$EVAL_JSON` and returns ONLY
`{"score":N,"suggestion":"one line"}`. The helper reserves `$EVAL_JSON` for that
authored report, captures Codex's final message in a separate temporary file,
prints the final message to stdout, and fails if the report is absent or empty.

**Context isolation (load-bearing):** the evaluator MUST NOT receive the task
description, the modifier's reasoning, or *why* changes were made. On Codex,
  run the evaluator with
  `bash "$PROJECT/scripts/meta/run-isolated-role.sh" evaluate "$PROJECT" <prompt-file> "$EVAL_JSON"`
  — never in-session.

## Step 6: Keep or Discard

```bash
PREV_BEST=$(jq -s 'sort_by(.score)|last|.score//0' "$ATTEMPTS" 2>/dev/null || echo 0)
```
- `SCORE > PREV_BEST` → **KEEP**: `git commit -m "refine: $TASK_ID iter $N — score $SCORE"`
- else → **DISCARD**: list iteration-created untracked paths with
  `git clean -nd`, restore tracked files with
  `git restore --staged --worktree -- .`, then remove only those listed paths
  with path-scoped `git clean -fd -- <paths>`.
- `SCORE >= THRESHOLD` → also **ACCEPT** (exit after recording).

## Step 7: Record + Terminate

```bash
echo "{\"score\":$SCORE,\"gaps\":$GAPS,\"result\":\"<KEEP|DISCARD>: $SUMMARY\",\"feedback\":\"$SUGGESTION\"}" >> "$ATTEMPTS"
ITERATION=$(wc -l < "$ATTEMPTS")
```
- `SCORE >= THRESHOLD` → **ACCEPT** · `ITERATION >= MAX_ITER` → **STOP** · else → return to **Step 3**.
- **Always `rm -f "$MARKER"` on every exit path** (ACCEPT / STOP / error), then
  report best: `jq -s 'sort_by(.score)|last' "$ATTEMPTS"`. Do not ask permission
  between iterations.

## Design principles

1. **Exploratory over corrective** — discover the next gap, don't just fix the stated one.
2. **Thin orchestrator** — heavy work in fresh subagents; only scores + one-liners enter main context.
3. **Audit→Modify separation** — evidence-before-modification is structurally enforced.
4. **Context reset per iteration**; output to file, not context.
5. **Generator ≠ Evaluator** — context-isolated scoring (Anthropic GAN principle); the agent that modified code never writes or modifies its own scorer in the same iteration.
6. **Metric over judgment** — objective if available; calibrated is last resort.
7. **Baseline must not be perfect** — the Contract must be able to register improvement.
8. **Scorer notes** — prefer graduated checks over binary pass/fail (binary → wasteful 0→1.0 jumps); evolve `score.sh` only *between* runs.
9. **No dead data** — store only `{score, gaps, result, feedback}` per attempt.
