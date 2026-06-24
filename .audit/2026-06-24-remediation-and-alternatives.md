# Remediation & Alternatives — Agent-System Essence Audit

*Date: 2026-06-24 · Author: Claude (Opus 4.8) · Companion to: `2026-06-24-claude-codex-agent-system-essence-audit.md`*
*Status: PROPOSALS — none applied. System fixes require explicit "수정"; this is record-not-action. Handoff target: **Codex (이어 작업)**.*

## How to read this

For each finding: **root cause (logical)** → **alternatives** (each with logical basis + cost/blast-radius, per `destructive-ops-discipline §1`) → **recommendation + 논리적 근거** → **2-axis verification** (positive + regression, per `audit-discipline §2`). Karpathy R1 demands alternatives be surfaced, not silently picked; R2 demands the minimum mechanism; R3 demands the change be surgical.

**Cross-cutting root pattern (H1–H3):** all three are *byte-identical mirroring of vendor-coupled artifacts*. The fix family is to either make an artifact **vendor-neutral** (H3) or make the **vendor-delta explicit** (H1/H2) — never to let byte-equality masquerade as behavior-equality. The mirror model should split assets into **portable** (rules prose, karpathy) vs **vendor-coupled** (anything referencing `$CLAUDE_PROJECT_DIR`, `.claude/` paths, or sub-agent isolation).

---

## H1 — refine keep/discard loses epistemic integrity on Codex

**Root cause (logical):** the keep/discard decision is `f(evaluator_score)` (refine:240–262). That score is trustworthy *only if* the evaluator cannot see the generator's intent (refine:247–251; refine:587 names the self-validation anti-pattern). On Codex the evaluator is an **in-context skill** (no second context window — `.agents/agents/` absent), so the forbidden intent is already present in the scoring agent → score is self-graded → the decision is invalid.

| # | Alternative | Logical basis | Cost / blast-radius |
|---|---|---|---|
| A | Restrict Codex refine to **objective mode** (pure `verify_cmd`, no model judgment) | Objective score = deterministic command exit code, judgment-free → isolation is irrelevant → integrity holds *by construction* | Low (config + doc); Codex loses subjective/calibrated scoring |
| B | **Process-isolated** evaluator: Codex spawns `codex exec` subprocess fed ONLY `{diff, contract}` | Re-creates isolation at the OS-process boundary (separate context) — restores full parity | High (orchestration, prompt-hygiene to prevent intent leak, bwrap-bypass); medium-high blast |
| C | **Document the limit**: mark calibrated/tool-augmented refine "Claude-only"; Codex degrades to objective + discloses | The actual defect is the *undocumented false guarantee*; declaring it converts a hidden gap into a stated constraint | ~Doc only; tiny blast |

**Recommendation: C now + A as the enforced Codex default; B deferred.** 논리적 근거: the harm is a guarantee the runtime cannot honor — the minimal *correct* fix removes the guarantee (C) and enforces the only integrity-preserving mode (A); both are near-zero cost and fully restore correctness. B is the *only* path to subjective-scoring parity, but its cost is high and the need is unproven → R2 forbids building it before it's needed.
**Verify (2-axis):** positive — on Codex, calibrated refine now refuses/declares instead of silently self-grading; regression — on Claude all three modes work unchanged (isolation intact, score still independent).

---

## H2 — four of six discipline rules are DARK on a default Codex session

**Root cause:** CLAUDE.md @imports 6 rules (L98–103); AGENTS.md session-start Read-list names only 2 (L146–147); no Codex hook/config injects the other 4; and AGENTS.md:3 ("all behavioral rules must live inline here") contradicts the 2-of-6 reality.

| # | Alternative | Logical basis | Cost / blast-radius |
|---|---|---|---|
| A | Add audit/commit/destructive-ops/anchor to **AGENTS.md session-start Read-list** | Mirrors Claude's @import-6; restores the parity the system already claims | ~4 lines; Codex loads ≈+350 governance lines/session; tiny blast |
| B | **Inject via the Codex session-start hook** (as it already injects MEMORY.md) | Hook injection is *guaranteed* (not model-discretion) → strongest activation | Per-session context bloat; hook complexity; medium blast |
| C | Keep lean **but DECLARE** the exclusion (only 2 rules, document why) | If the lean default is a conscious R2 choice, the fix is to make the decision explicit, not to load more | Codex genuinely lacks the guards — unacceptable for destructive-ops on the sandbox-bypassed vendor |

**Recommendation: A (and fix the AGENTS.md:3 self-contradiction).** 논리적 근거: the four disciplines encode guards whose expected value (preventing rare-but-costly failures — an un-alternatived `rm -rf`/`git push --force`, a thesis-substitution) exceeds the ~350-line context cost; and **destructive-ops being DARK on the sandbox-bypassed vendor is the highest-stakes cell in the matrix**, which disqualifies C for that rule. A is simpler than B (R2) and sufficient — a model reliably Reads a short explicit list. Escalate to B only if Codex sessions are observed skipping the Read.
**Verify:** positive — a fresh Codex session can cite destructive-ops before an `rm -rf` (probe); regression — Claude @import still 6; AGENTS.md:3 no longer self-contradicts.

---

## H3 — refine/verify/status/wiki hard-code `$CLAUDE_PROJECT_DIR` / `.claude/`

**Root cause:** vendor-coupled paths in a byte-identical mirror; under Codex `$CLAUDE_PROJECT_DIR` is empty (REFERENCE.md:181) → `refine` `PROJECT=''`, `verify:26` → `bash "/scripts/…"` (absolute, nonexistent) → fails (runtime-proven). **§4 precision:** the break is at the **skill invocation path**, not `completion-checker.sh` (which is already var-robust, completion-checker.sh:13) — so the edit lands on the skill caller sites only; the script needs no change.

| # | Alternative | Logical basis | Cost / blast-radius |
|---|---|---|---|
| A | **Vendor-neutral fallback chain**: `${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git rev-parse --show-toplevel)}}` + resolved `$STATE_DIR` (.claude vs .codex/state) | Correct under both vendors *and* standalone; Claude behavior byte-unchanged (R3 surgical); `git rev-parse` terminal fallback is robust | Edit ≈22 sites in refine + verify/status/wiki, re-sync; medium-mechanical, fully testable |
| B | **Sync-time rewrite** (`.claude/`→`.codex/`, `CLAUDE_`→`CODEX_`) in sync-agents-mirror.sh | Keeps ground-truth Claude-pure; centralizes the transform | Deliberately breaks byte-parity (the very illusion that hid this bug — acceptable) + adds a transform layer (new failure modes); changes the parity contract |
| C | Neutral `$AGENT_PROJECT_DIR` exported by each vendor's session hook | Cleanest abstraction — one var, vendor sets it | Both hooks + all skills must adopt; larger refactor |

**Recommendation: A.** 논리적 근거: smallest change that is correct on both vendors, preserves Claude byte-for-byte (R3), and the terminal `git rev-parse` makes it robust even outside both harnesses. B is architecturally clean but discards byte-parity *and* introduces a transform layer (more surface to fail) — defer unless A's per-site edits prove unmaintainable. C over-abstracts for the present need (R2). **Note:** the `$STATE_DIR` (.claude vs .codex/state) must resolve too, not just `$PROJECT`.
**Verify:** positive — `env -u CLAUDE_PROJECT_DIR CODEX_PROJECT_DIR=/workspaces` → skill resolves to /workspaces + .codex/state; regression — with `CLAUDE_PROJECT_DIR` set, every resolved path identical to today.

---

## M1 — security/ is 10/10 vestigial and asserts unexecuted enforcement (INTEGRITY self-violation)

**Root cause:** registry.md:8,13 asserts a lifecycle gate ("eval suite executed and passed") and eval-suites imply a test gate, but no executor exists (self-admitted "documentation only — no automation," registry.md:59,71). This contradicts CLAUDE.md's core principle "*every claim verified by execution before statement.*"

| # | Alternative | Logical basis | Cost / blast-radius |
|---|---|---|---|
| A | **Honest re-wording**: every enforcement verb → "manual reference checklist; not automated" (make ALL files consistent with the ones that already say so) | The defect is claim-vs-reality; the cheapest *correct* fix aligns the claim to reality → restores INTEGRITY at doc-cost | Doc edits; tiny blast |
| B | **Make them LIVE**: build an eval-suite runner + registry-state automation (CI/hook) | Deliver what the docs claim → a real control plane | HIGH (machine-readable suites, runner, CI); large blast |
| C | **Delete** the 0/10-live surface + parity-table lines | R2/R3 — dead doc that contradicts the core principle is net-negative; removal kills the contradiction + the mirror cost | Loses the audit-map artifact; small blast (nothing consumes it) — **but destructive: narrower option A exists** |

**Recommendation: A (keep the docs, make every enforcement verb honest).** 논리적 근거: the harm is the *false enforcement claim*, not the existence of reference docs; aligning claims to reality (A) restores INTEGRITY without building unrequested machinery (B) or destroying the audit map (C). Per `destructive-ops-discipline §1`, deletion (C) must be *preceded* by the narrower alternative — so A is correct-first; if after A the docs are judged value-less, C becomes a separate, approval-gated decision.
**Verify:** positive — `rg` for unconditional enforcement verbs in security/ = 0 after rewrite; regression — the 4 self-check bash blocks (each greps itself) still pass; parity-table counts unchanged.

---

## M2 — anchor-discipline is an R2 self-violation (123 lines / 7 protocols)

**Root cause:** a rule reverse-engineered from a real failure has grown into the over-elaboration its own cited yardstick forbids (behavioral-core:27 "if it could be 50, rewrite it").

| # | Alternative | Logical basis | Cost / blast-radius |
|---|---|---|---|
| A | **Compress to the irreducible core** (frozen-anchor file + grep-matrix gate + user-attestation gate + quick-answer-stop); move AUD-IDs / nested taxonomies / per-response ceremony to a linked appendix | R2 minimum mechanism; a model actually loads-and-applies ~30 lines vs skims 123; the load-bearing protocol survives | Rewrite, with care not to amputate P1 (frozen file) / P4 (attestation) — the parts that fixed the real 27%-anchor-hit failure; small blast (DARK on Codex anyway) |
| B | **Keep as-is, DECLARE** it a deliberate heavyweight exception with rationale | If the full protocol genuinely prevents the costly 20-iteration thesis-substitution, length may be justified — but then declare the R2 exception (its own §1 spirit) | None |

**Recommendation: A, conservatively** — compress the meta-ceremony, *preserve* P1+P4 + the four termination conditions. 논리적 근거: behavioral-core:27 is unambiguous, and the rule's own essence (preserve the user thesis) is better served by something the model loads-and-applies than by 123 lines it skims; but because the rule encodes a real lesson, the compression must be **surgical, not amputation** (R3) — keep the load-bearing protocols. This is the one finding where the system's yardstick indicts the system itself, so fixing it has self-consistency value.
**Verify:** positive — line count ≤ ~50 with P1/P4/termination-conditions still grep-present; regression — replay the original ~27% scenario: does the compressed rule still catch thesis-substitution? If not, restore the cut piece.

---

## M3 — refine over-scopes a refinement loop into KB-authoring + meta-learning

**Root cause:** refine:298–452 embed a 145-line wiki-page authoring block + scorer-evolution — concerns independently revertable from keep/discard (commit-discipline reversibility test).

| # | Alternative | Logical basis | Cost / blast-radius |
|---|---|---|---|
| A | **Extract** Steps 7D+9 to the wiki skill / a separate refine-learning skill; refine calls `/wiki ingest` | R3 + DRY — wiki logic already exists in wiki/SKILL.md; refine duplicating it is the coupling smell | Refactor + interface; medium blast |
| B | **Explicit opt-in flag**, leave in place (already inert-by-default) | Cheaper than extraction; preserves current behavior | Minimal |

**Recommendation: A if the learning loop is valued; B as interim.** 논리적 근거: a refinement loop's single concern is keep/discard; KB-authoring is a different concern — but it is inert-by-default and low-urgency, so B (an explicit gate) is an acceptable interim while A is scheduled. MED, not urgent.
**Verify:** positive — refine core (Steps 0–6) runs standalone with the wiki block extracted; regression — wiki-coupled flow still produces the same pages via `/wiki ingest`.

---

## LOW

| # | Finding | Recommended alternative | 논리적 근거 |
|---|---|---|---|
| L1 | sync additive-only; `--dry` blind to dest-only | **B**: drop the `grep -v "Only in DST"` so dry-run reports dest-only as "orphan candidates" (visibility). Defer actual `--prune`/`rsync --delete` (A) behind approval | The live risk is the *blindness*, not the copy semantics; B fixes exactly that at zero blast-radius; A is destructive-adjacent → approval-gate it |
| L2 | pre-commit Layer 2 dormant (`.refine/score.sh` not shipped) | **A**: correct CLAUDE.md §2 to state the warning is conditional on the scorer existing (vs B: ship a default scorer to activate it) | Claim-vs-reality → default to honest docs unless the multi-file warning is actually wanted by default |
| L3 | wiki declares `Agent` tool, never spawns | **A**: remove `Agent` from wiki allowed-tools | R2 / least-privilege; the body never uses it — surgical 1-line removal |
| L4 | `.audit/` not gitignored | **Decide policy**: track this turn's report for the handoff, but choose track-vs-ignore for `.audit/` generally (prior precedent = untracked) | Cross-audit working dir; trivial either way — flag for user/Codex decision, don't silently pick |

---

## Codex handoff worklist (ordered by severity × inverse-cost)

> Each `[수정]` item requires the user's explicit "수정" before *applying* (record-not-action). Codex's "이어 작업" = audit these alternatives and/or implement the approved subset, then commit locally (no push) for Claude to re-audit.

1. **H2-A** — add 4 disciplines to AGENTS.md Read-list + fix L3-of-AGENTS.md:3 contradiction. *(highest value/cost; ~4 lines)* `[수정]`
2. **H3-A** — vendor-neutral path + state-dir resolution in refine/verify/status/wiki; re-sync; verify under both env conditions. `[수정]`
3. **H1-C+A** — declare calibrated/tool-augmented refine Claude-only; enforce objective-only on Codex. `[수정]`
4. **M1-A** — honest re-wording of security/ enforcement claims (restore INTEGRITY). `[수정]`
5. **M2-A** — compress anchor-discipline, preserving P1/P4 + termination conditions. `[수정]`
6. **L3-A, L2-A, L1-B** — trivial least-privilege / doc-truth / dry-run-visibility fixes. `[수정]`
7. **Deferred** (higher cost or lower urgency): M3-A, H1-B (process-isolated evaluator), H3-B (sync-time rewrite), L1-A (sync prune).

**Sequencing logic:** items 1–3 close the three HIGH essence gaps (the byte-vs-behavior illusions); 4–5 restore the system's self-consistency (it should obey the principles it audits by); 6 is cheap hygiene; 7 is deferred until the cheaper fixes prove insufficient (R2 — don't build the expensive version first). Every fix carries a 2-axis verification above (positive + regression) so each can be proven, per `audit-discipline §2`.
