# Codex Alternative Remediation Handoff

*Date: 2026-06-24 | Author: Codex | Base: `3e41f02` | Status: HANDOFF ONLY*

Executor: **Claude**. This document records Codex's alternative plan, verification contract, and implementation constraints. It intentionally does **not** apply system fixes.

## Scope

Inputs reviewed:

- `3e41f02` audit pair: `.audit/2026-06-24-claude-codex-agent-system-essence-audit.md` and `.audit/2026-06-24-remediation-and-alternatives.md`.
- Runtime/governance surfaces: `AGENTS.md`, `CLAUDE.md`, `.claude/`, `.agents/`, `.codex/`, `scripts/sync-agents-mirror.sh`, `scripts/meta/completion-checker.sh`, `.devcontainer/verify-template.sh`.
- Current worktree state: `main...origin/main [ahead 7]`; unrelated untracked audit files already exist and are not dispositioned here.

Non-scope:

- No push.
- No runtime code/config remediation by Codex in this pass.
- No `.audit/` policy decision; this file is a handoff artifact only.

## Tool Evidence

Reproduced findings:

- Rule activation mismatch: `CLAUDE.md` imports all six rules (`behavioral-core`, `audit-discipline`, `commit-discipline`, `destructive-ops-discipline`, `anchor-discipline`, `devcontainer-patterns`), while `AGENTS.md` session-start read list names only `behavioral-core` and `devcontainer-patterns`.
- H3 path proof: with `CLAUDE_PROJECT_DIR` unset, the verify skill command expands to `/scripts/meta/completion-checker.sh`; that path does not exist, while `$CODEX_PROJECT_DIR/scripts/meta/completion-checker.sh` exists.
- `refine` path binding count is currently 24 matches for `CLAUDE_PROJECT_DIR|.claude/` in both `.claude/skills/refine/SKILL.md` and `.agents/skills/refine/SKILL.md`; implementation must re-measure rather than rely on the older 22-count.
- `scripts/meta/completion-checker.sh` is internally robust only for its own location once invoked; the failing layer is the skill invocation path.
- `completion-checker.sh` writes `.claude/.last-verification.*`; Codex pre-commit compensates by touching `.codex/state/last-verification.*` after running it. A manual Codex `/verify` path therefore remains semantically weaker unless state-dir handling is fixed.
- Security docs have no non-audit, non-security consumers by `rg` after excluding `.claude/security/**`, `.agents/security/**`, and `.audit/**`.
- `scripts/sync-agents-mirror.sh --dry` reports `0 change(s) detected`, but its dry-run intentionally filters destination-only files with `grep -v "^Only in $DST_SUB"`.
- `verify-template.sh` counts six rule files but its explicit `EXPECTED_RULES` list omits `anchor-discipline`; H2 remediation must close that guard too.

## DAQ Contract For Claude

Each remediation commit should satisfy these gates:

1. **Define** the broken invariant before editing. Example: "Codex verify skill resolves project root without `CLAUDE_PROJECT_DIR`."
2. **Add or update a guard** in the same commit. Prefer `.devcontainer/verify-template.sh` when the invariant is template-wide.
3. **Verify both axes**: positive behavior still works; regression fixture proves the old failure mode fails the gate.
4. **Sync if `.claude/` changed**: run `bash scripts/sync-agents-mirror.sh`, then `bash scripts/sync-agents-mirror.sh --dry`.
5. **Run full local verification**: `bash .devcontainer/verify-template.sh`, `bash scripts/meta/completion-checker.sh`, syntax checks for edited shell scripts, and `git diff --check`.
6. **Use external container proof** for hook/runtime/path changes. Because `/workspaces` is a 9p mount, translate the host workspace path per `.agents/rules/devcontainer-patterns.md` before mounting.

## Codex Alternative Position

Claude's proposed ordering is directionally sound, but Codex changes two implementation rules:

- **Guard-first, not doc-first.** H2/H3 must update verification guards before or with the docs/skills. Otherwise the system can claim remediation while the exact regression remains mechanically invisible.
- **Semantic parity over byte parity.** `.agents/` byte equality is not enough. If a mirrored body mentions a vendor runtime (`CLAUDE_PROJECT_DIR`, `.claude`, sub-agent isolation), the fix must either make the source vendor-neutral or make the Codex delta explicit and verified.

Preferred implementation style:

- Edit `.claude/` and root governance files as ground truth, then sync to `.agents/`.
- Keep `scripts/sync-agents-mirror.sh` as a simple mirror unless a specific vendor delta cannot be represented in vendor-neutral source.
- Do not introduce a sync-time rewrite layer for H3 in the first pass; it is more complex than the current need and creates a second source of truth.

## Recommended Worklist

### P0 - Verification Spine First

Before functional remediation, update `verify-template.sh` so future fixes are measurable:

- H2 guard: assert `AGENTS.md` read list contains all six rule files, including `anchor-discipline`.
- H2 guard: assert `CLAUDE.md` imports the same six rule files and `.agents/rules/` mirrors all six.
- H3 guard: assert verify skill command no longer hard-codes only `$CLAUDE_PROJECT_DIR`.
- H3 guard: simulate `env -u CLAUDE_PROJECT_DIR CODEX_PROJECT_DIR=/workspaces` and prove the resolved completion-checker path exists.
- Sync guard: make `--dry` surface destination-only files as orphan candidates without deleting them.

Rationale: these guards are not optional polish. They turn the audit findings into regression-detectable invariants.

### P1 - H2 Rule Activation

Implement Claude recommendation A with one correction:

- Update `AGENTS.md` wording so it no longer says "all behavioral rules must live inline here" while relying on explicit reads.
- Add all six `.agents/rules/*.md` to the Codex session-start read list.
- Preserve the current concise root document; do not paste the full rule bodies inline unless a later runtime test proves Codex skips explicit reads.

Verification:

- Positive: `rg` shows all six rules in both `CLAUDE.md` imports and `AGENTS.md` read list.
- Regression: remove or omit `anchor-discipline` in a test branch and confirm `verify-template.sh` fails.

### P2 - H3 Vendor-Neutral Paths And State

Accept Claude recommendation A, but treat project-root and state-dir as two separate invariants:

- Project root fallback should resolve `CLAUDE_PROJECT_DIR`, then `CODEX_PROJECT_DIR`, then `git rev-parse --show-toplevel`, then `pwd`.
- State dir must resolve to `.claude` under Claude and `.codex/state` under Codex. Do not only fix `PROJECT_DIR`.
- `verify` should invoke `scripts/meta/completion-checker.sh` through the resolved project root, not a raw `$CLAUDE_PROJECT_DIR` literal.
- `completion-checker.sh` should understand `CODEX_PROJECT_DIR` and either write the correct vendor marker or document that Codex pre-commit owns the marker. Prefer writing/refreshing the correct marker when invoked from Codex so manual `/verify` is meaningful.
- `refine` must not write Codex runtime state into `.claude` unless the selected mode is explicitly Claude-only.

Verification:

- Positive: with `CLAUDE_PROJECT_DIR=/workspaces`, all resolved paths match current Claude behavior.
- Positive: with `env -u CLAUDE_PROJECT_DIR CODEX_PROJECT_DIR=/workspaces`, verify/refine/status/wiki resolve project root under `/workspaces` and Codex state under `.codex/state`.
- Regression: with both vars unset inside the repo, fallback resolves through `git rev-parse` rather than `/scripts/...`.

### P3 - H1 Refine Integrity

Accept C+A, but enforce through mode selection rather than prose alone:

- Codex may run objective mode when a deterministic scorer/verify command exists.
- Codex must refuse or explicitly downgrade tool-augmented/calibrated modes unless a real isolated subprocess protocol is implemented.
- Keep H1-B process isolation deferred. It is the only full parity path, but it is a separate feature and needs prompt-hygiene tests.

Verification:

- Positive: Codex objective-mode refine can run with a deterministic command and does not call evaluator scoring.
- Regression: Codex calibrated/tool-augmented refine without isolation exits with an explicit unsupported-mode message.
- Claude regression: Claude agent-based refine still documents and uses evaluator isolation.

### P4 - M1 Security Docs Truthfulness

Accept A:

- Replace unconditional lifecycle/enforcement claims with "manual reference checklist; not automated" where no runner exists.
- Leave hook rows marked active/enforced only where a shell hook actually implements behavior.
- Do not delete `security/` in this pass.

Verification:

- Positive: `rg` for unconditional "executed and passed" lifecycle claims returns none outside explicit manual-context text.
- Regression: existing self-check snippets in the security docs still pass.

### P5 - M2 Anchor Compression

Accept A only with preservation constraints:

- Preserve frozen anchor file, grep-matrix/equivalent gap check, user-attestation gate, and termination conditions.
- Remove or appendix non-load-bearing ceremony.
- Keep a short rationale explaining why this rule is deliberately small.

Verification:

- Positive: line count drops to the agreed target range and preserved concepts grep-present.
- Regression: replay the original thesis-substitution scenario described in the rule source note; the compressed rule must still catch it.

### P6 - Low-Risk Hygiene

Implement after HIGH/MED items:

- L1: make sync dry-run report destination-only files as orphan candidates. Do not delete them automatically.
- L2: correct docs to state the refine multi-file warning depends on `.refine/score.sh`.
- L3: remove `Agent` from wiki allowed-tools if the body still has no agent-dispatch path.
- L4: leave `.audit/` policy undecided unless the user explicitly chooses track vs ignore.

Verification:

- L1 positive: create a temporary destination-only file under `.agents/` and confirm `--dry` reports it; remove the temp file after proof.
- L1 regression: `--dry` still reports source-side content drift.
- L3 positive: frontmatter no longer grants `Agent`; regression: wiki documented flows still require no `Agent`.

### P7 - Deferred Items

Do not implement these in the first Claude execution pass unless the user explicitly expands scope:

- M3-A: extracting `refine` wiki-authoring and scorer-evolution into a wiki/refine-learning path. Current risk is medium and mostly inert-by-default; it is larger than the H1/H3 integrity fixes.
- H1-B: process-isolated Codex evaluator subprocess. This is the full-parity path, but it requires prompt-boundary and intent-leak tests.
- H3-B: sync-time rewrite layer. Reserve it for cases where vendor-neutral source makes Claude behavior worse.
- L1-A: automatic pruning/deletion of destination-only mirror files. Visibility is acceptable first; deletion remains approval-gated.

## Commit Discipline

Recommended commit split:

1. `test(verify): guard agent-system semantic parity regressions`
2. `docs(codex): load all mirrored governance rules`
3. `fix(skills): resolve project and state paths across Claude and Codex`
4. `fix(refine): enforce Codex objective-only integrity mode`
5. `docs(security): mark eval registry as manual reference`
6. `docs(rules): compress anchor discipline to load-bearing core`
7. `fix(sync): surface destination-only mirror orphans in dry-run`
8. `docs(governance): align refine warning and wiki tool scope`
9. Deferred only if explicitly approved: M3 extraction, H1-B process isolation, H3-B sync rewrite, L1-A pruning.

If a guard and its fix are inseparable, combine them only with an explicit `Coupling:` line.

## Final Gate Before Claude Hands Back

Claude should report:

- Commit hashes and touched paths for each concern.
- Exact command outputs for `verify-template`, `completion-checker`, `sync --dry`, shell syntax checks, and external container proof.
- Whether `.audit/` policy was left unchanged.
- Any deviation from this plan, with the invariant that forced the deviation.
