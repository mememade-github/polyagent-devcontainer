# Execution Plan — Agent-System Essence Remediation (merged: Claude + Codex)

*Date: 2026-06-24 · Author: Claude (Opus 4.8) · Base: `3e41f02` · Inputs: Claude remediation doc + Codex handoff (`2026-06-24-codex-alternative-remediation-handoff.md`)*
*Status: **PLAN ONLY** — no system file modified. Execution requires explicit "수정". Then local commit (no push) for Codex re-audit.*

## A. Adopted from Codex (agreement)

- **Guard-first**: every behavior fix lands with a `verify-template.sh` regression guard so the fix is mechanically locked (the 97abd11/Phase-1e pattern).
- **Semantic parity > byte parity**: a mirrored body that names a vendor runtime (`CLAUDE_PROJECT_DIR`, `.claude/`, sub-agent isolation) must be made vendor-neutral *or* its Codex delta made explicit and verified.
- **DAQ 6-gate per commit**: Define invariant → add/update guard (same commit) → verify both axes → sync → full local verification → external-container proof for runtime/path/hook changes.
- **Edit `.claude/` + root governance as ground truth, then sync**; keep `sync-agents-mirror.sh` a simple mirror; no sync-time rewrite layer for H3 in pass 1.
- **Deferred set** unchanged: M3-A, H1-B (process-isolated evaluator), H3-B (sync rewrite), L1-A (auto-prune).

## B. Two corrections re-verified by execution (Codex was right)

- **C1 — verify-template rule guard is incomplete.** `verify-template.sh:158` `EXPECTED_RULES` lists 5, **omits `anchor-discipline`** (`:164` "all 5 portable rules"). The count guard (`:169 -eq 6`) catches deletion but never asserts anchor *by name*. → H2 guard must enumerate all 6.
- **C2 — H3 is two invariants, not one.** `refine` has 22 `.claude/` literals, **mostly STATE paths** (`.refinement-active`, `agent-memory/*`, `.refine-output`, `.refine-eval.json`, `scorer-evolution.jsonl`); `status:59` reads `.claude/.last-verification.*`. Under Codex these must resolve to `.codex/state`, not just a fixed `$PROJECT`. So H3 = **{project-root resolver} + {state-dir resolver}**.

## C. Material refinement to Codex's plan (my bidirectional-audit finding)

**Codex's "P0 = all guards first, as a standalone commit" self-blocks the pre-commit gate.** A guard asserting a *not-yet-true* invariant (e.g. "AGENTS.md lists 6 rules", "verify resolves without `$CLAUDE_PROJECT_DIR`") makes `verify-template.sh` FAIL; the pre-commit gate runs `verify-template` via `completion-checker.sh` and **exits 2 → the guard-only commit is blocked.** (Marker-freshness can mask it for ≤600 s, but that is gaming the gate; the next stale-marker run blocks.)

**Rule:** classify each guard by whether its invariant is true *now*:

| Guard | True now? | Commit placement |
|---|---|---|
| anchor-discipline ∈ EXPECTED_RULES | ✅ (file exists) | **Standalone P0** |
| CLAUDE.md imports 6 | ✅ | **Standalone P0** |
| `.agents/rules` mirrors 6 | ✅ | **Standalone P0** |
| AGENTS.md read-list lists 6 | ❌ (lists 2) | **Couple with H2 fix** |
| verify/refine resolve w/o `$CLAUDE_PROJECT_DIR` | ❌ | **Couple with H3 fix** |
| state-dir → `.codex/state` under Codex | ❌ | **Couple with H3 fix** |
| Codex refine objective-only | ❌ | **Couple with H1 fix** |
| sync `--dry` surfaces orphans | ❌ (filtered) | **Couple with L1 fix** |

Coupled commits carry an explicit `Coupling:` line (guard ↔ fix are inseparable: reverting one re-opens the regression). This *replaces* Codex's separate "commit 1 = all guards".

## D. Phase plan (each: invariant → edits → guard → 2-axis verify → sync → commit)

### P0 — Spine (standalone; all assertions true now)
- **Edits:** `verify-template.sh` — add `anchor-discipline` to `EXPECTED_RULES` (5→6, fix "all 5"→"all 6"); add explicit asserts "CLAUDE.md @imports all 6" and "`.agents/rules/` mirrors all 6".
- **Verify:** positive — `bash verify-template.sh` → 62/0 (was 59, +3); regression — in a scratch copy rename `anchor-discipline.md`, guard FAILs.
- **Commit:** `test(verify): assert all six governance rules present, imported, mirrored (incl. anchor-discipline)`.

### P1 — H2 rule activation (coupled)
- **Invariant:** a default Codex session loads all six discipline rules.
- **Edits:** `AGENTS.md` — (a) fix L3 contradiction ("all behavioral rules must live inline here" → "load via explicit Read at session start; bodies live in `.agents/rules/`"); (b) L146-147 read-list → all six rule files. + same-commit guard: assert AGENTS.md read-list block names all 6.
- **Verify:** positive — `rg` shows 6 in both CLAUDE.md imports and AGENTS.md read-list, `verify-template` passes; regression — omit `anchor-discipline` from the list in scratch → `verify-template` FAILs.
- **Sync:** none (`AGENTS.md` is root; `.agents/rules` unchanged). **Commit (Coupling):** `docs(codex): load all six governance rules at session start`.

### P2 — H3 vendor-neutral paths + state (coupled; external-container proof)
- **Invariant 1 (root):** `PROJECT_ROOT = ${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}`.
- **Invariant 2 (state):** `STATE_DIR = .claude` when `CLAUDE_PROJECT_DIR` set, else `.codex/state` when `CODEX_PROJECT_DIR` set.
- **Edits:** `refine/SKILL.md` (22 sites — root + state), `status/SKILL.md:59` (marker glob → STATE_DIR), `wiki/SKILL.md` (3 refine-coupled paths → STATE_DIR), `verify/SKILL.md:26` (invoke via PROJECT_ROOT, not raw `$CLAUDE_PROJECT_DIR`). `completion-checker.sh` — understand `CODEX_PROJECT_DIR` and write the correct vendor marker (so manual Codex `/verify` is meaningful), or document Codex pre-commit owns it (prefer writing correct marker). + same-commit guards: G-H3a no bare `$CLAUDE_PROJECT_DIR` in skill invocation; G-H3b `env -u CLAUDE_PROJECT_DIR CODEX_PROJECT_DIR=/workspaces` → resolved completion-checker path exists; G-H3c state resolves to `.codex/state` under Codex.
- **Verify:** positive — `CLAUDE_PROJECT_DIR=/workspaces` → every resolved path identical to today; `env -u CLAUDE_PROJECT_DIR CODEX_PROJECT_DIR=/workspaces` → root `/workspaces`, state `.codex/state`; regression — both unset in-repo → resolves via `git rev-parse`, never `/scripts/...`. **External-container proof** (9p host-path translation per devcontainer-patterns).
- **Sync:** `.claude/skills` changed → `sync-agents-mirror.sh` + `--dry` = 0. **Commit (Coupling):** `fix(skills): resolve project root and state dir across Claude and Codex`. (Re-measure literal count at edit time — Codex measured 24 incl. `CLAUDE_PROJECT_DIR`; do not trust the 22.)

### P3 — H1 refine integrity (coupled)
- **Invariant:** on Codex, keep/discard never rides a self-graded score.
- **Edits:** `refine/SKILL.md` — branch on vendor: objective mode (deterministic `verify_cmd`) allowed on Codex; calibrated/tool-augmented → explicit unsupported-mode refusal/downgrade; mark those modes "Claude-only (requires sub-agent isolation)." + guard asserting the constraint text + (if testable) a fixture that calibrated-on-Codex exits unsupported.
- **Verify:** positive — Codex objective refine runs, no evaluator scoring; regression — Codex calibrated without isolation → explicit unsupported message; Claude regression — agent-isolated refine unchanged. **Sync.** **Commit (Coupling):** `fix(refine): enforce Codex objective-only integrity mode`.

### P4 — M1 security truthfulness (guard+fix)
- **Edits:** reword `security/` enforcement verbs → "manual reference checklist; not automated" where no runner exists; keep "active/enforced" only where a shell hook implements it; **do not delete** `security/`. + guard: no unconditional "executed and passed"/enforcement verb outside manual-context.
- **Verify:** positive — `rg` for unconditional lifecycle claims = none; regression — security self-check snippets still pass. **Sync.** **Commit:** `docs(security): mark eval registry/suites as manual reference`.

### P5 — M2 anchor compression (guard+fix)
- **Edits:** compress `anchor-discipline.md` preserving P1 frozen-anchor, P4 attestation gate, termination conditions; move non-load-bearing ceremony to an appendix; keep a 1-line "deliberately small" rationale. + guard: line count ≤ target AND preserved-concept markers grep-present.
- **Verify:** positive — line count + concepts present; regression — replay the thesis-substitution scenario from the rule's own source note; compressed rule still catches it. **Sync.** **Commit:** `docs(rules): compress anchor-discipline to load-bearing core`.

### P6 — Low-risk hygiene (guard+fix)
- **L1:** `sync-agents-mirror.sh --dry` reports dest-only as "orphan candidates" (drop the `grep -v "^Only in $DST"`); no auto-delete. + guard: temp dest-only file under `.agents/` → `--dry` reports it → remove temp; regression — `--dry` still reports source-side drift.
- **L2:** correct `CLAUDE.md §2` to state the multi-file `/refine` warning depends on `.refine/score.sh` existing.
- **L3:** remove `Agent` from `wiki/SKILL.md` allowed-tools (body has no dispatch). + guard: frontmatter no `Agent`.
- **L4:** leave `.audit/` policy undecided unless the user picks track-vs-ignore.
- **Commits:** `fix(sync): surface destination-only mirror orphans in dry-run`; `docs(governance): align refine warning and wiki tool scope`.

### P7 — Deferred (only on explicit scope expansion)
M3-A (extract refine wiki/scorer subsystems), H1-B (process-isolated Codex evaluator), H3-B (sync rewrite), L1-A (auto-prune).

## E. Commit sequence (revised — guard-coupling, not guard-all-first)

1. `test(verify): assert all six governance rules present, imported, mirrored` *(P0, standalone)*
2. `docs(codex): load all six governance rules at session start` *(P1, Coupling)*
3. `fix(skills): resolve project root and state dir across Claude and Codex` *(P2, Coupling, ext-container)*
4. `fix(refine): enforce Codex objective-only integrity mode` *(P3, Coupling)*
5. `docs(security): mark eval registry/suites as manual reference` *(P4)*
6. `docs(rules): compress anchor-discipline to load-bearing core` *(P5)*
7. `fix(sync): surface destination-only mirror orphans in dry-run` *(P6/L1, Coupling)*
8. `docs(governance): align refine warning and wiki tool scope` *(P6/L2+L3)*

All local; no push until the user says so. Each commit: pre-commit gate green + `sync --dry` = 0.

## F. Final handback contract (per Codex)
Report: commit hashes + touched paths per concern; exact outputs for `verify-template`, `completion-checker`, `sync --dry`, shell syntax checks (`bash -n`), `git diff --check`, and external-container proof; whether `.audit/` policy changed; any deviation + the invariant that forced it.

## G. Status & gate
PLAN ONLY. Nothing in `.claude/`/`.codex/`/`.agents/`/root governance changed this turn. **Execution is gated on an explicit "수정"**; on approval I execute P0→P6 in order, couple guards per §C, and hand back per §F. Deferred P7 only on explicit scope expansion.
