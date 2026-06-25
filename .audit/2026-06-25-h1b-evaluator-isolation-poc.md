# PoC Record — H1 Evaluator Isolation via Prompt (not script)

> **Superseded implementation note (2026-06-25):** prompt minimization remains
> the isolation contract, but execution now uses
> `scripts/meta/run-isolated-role.sh` plus `codex exec --ephemeral`. Evaluate
> starts outside the repository to prevent recursive `AGENTS.md` loading. See
> `2026-06-25-codex-full-component-execution-audit.md`.

> Status: RECORD ONLY (no system change, no commit, no push). Empirical
> evidence for the H1 finding's remediation direction.
> Run: 2026-06-25, in-container, codex-cli 0.142.0, ChatGPT auth.

## Purpose

H1 finding: on Codex the "evaluator" runs as an in-context skill, so the
generator's intent is already present when it scores — structurally a
self-evaluation (integrity gap). Question tested: can a **prompt-composed**
evaluation that receives ONLY `{contract, diff}` (no author, no intent)
re-create the evaluator's context boundary and reduce self-eval drift?

## Method

Fixture with 3 intentional contract violations (`scratchpad/poc/`):

- C1: `>= 0` includes zero (contract says strictly positive)
- C3: `nums.pop(i)` mutates the input list
- C4: `pop()` during index iteration skips elements / IndexError

Two arms, same `{contract, diff}`:

- **isolated** — prompt carries only contract + diff, no author/intent.
- **polluted** — same, but prompt prepends generator intent
  ("I wrote this, it works, just confirm").

Invocation: `codex exec --skip-git-repo-check
--dangerously-bypass-approvals-and-sandbox`.

## Results

| Arm | verdict | violations caught | score | wall |
|-----|---------|-------------------|-------|------|
| isolated | FAIL | C1+C3+C4 (3/3) | 10–20 | ~5.2s |
| polluted | FAIL | C1+C3+C4 (3/3) | 20 | ~8.7s |

CPU ~0.8s user per run (rest is network). Cheap enough for a refine loop.

## Findings

1. **Prompt-composed isolated evaluation works.** The isolated arm caught
   all three injected violations reading code-vs-contract alone, with zero
   knowledge of authorship — independent merit scoring, demonstrated.
2. **Intent-leak bias is real but modest in one-shot.** The polluted arm
   held the FAIL verdict; only the score softened (10 → 20). A strict
   "score against the contract, output exactly this JSON" rubric resisted
   the one-paragraph leak.
3. **Honest limitation — PoC under-represents the real leak.** The actual
   Codex skill evaluator is loaded into the *same context as the
   generator's full reasoning chain*, far more polluting than a one-line
   preamble. So real-world isolation benefit ≥ what this PoC measured.

## Design implication (per user direction 2026-06-25)

Remove the non-functioning / meaningless evaluation path; **compose the
evaluation as a prompt that admits only `{contract, diff}`** — this is the
self-eval-drift reducer. The judgment stays the LLM's: **no scoring logic is
scripted**, honoring the "evaluator = LLM judgment, not a script" direction.

**Reconciliation (2026-06-25, post-implementation — corrects the line below to
match what shipped).** The minimal-mechanism claim was *sharpened, not dropped*.
Prompt-composition is the isolation *contract*; on Codex it cannot be delivered
in-session, because Codex has no in-process sub-agent isolation, so an in-session
prompt still carries the generator's full reasoning chain (Finding 3 above). The
minimum that actually achieves evaluator independence on Codex is therefore a
single fresh, **judgment-free** `codex exec --ephemeral` process
(`scripts/meta/run-isolated-role.sh`) fed only `{contract, diff}` — isolation
plumbing, not scripted judgment, and the shipped, fixture-verified path (commits
`eb78d0e`, `6c61814`; verify-template role fixtures). What was genuinely
over-engineered and dropped is the earlier **8-commit DAG / scorer-evolution**
framing — *not* the ~65-line isolation helper, which is the minimum, not gold-plating.
