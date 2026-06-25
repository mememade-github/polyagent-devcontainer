# Removal Record — `.claude/security/` + `.agents/security/` (20 files)

> Status: EXECUTED in working tree (git rm, staged), NOT committed (kept
> local pending convergence). Fully reversible: `git restore --staged
> --worktree .claude/security .agents/security`.
> Date: 2026-06-25. Authority: explicit user direction "제거" (×2).

## What was removed

`.claude/security/` (10) + `.agents/security/` mirror (10):
`registry.md`, `risk-registry.md`, `trust-boundary.md`,
`frontmatter-schema.md`, `eval-suites/{evaluator,refine,status,verify,
wiki,wip-manager}.md`.

## Why (sentence-level audit verdict, Karpathy-mapped)

- **`registry.md`** asserts a lifecycle gate — "reviewed → **tested**: eval
  suite executed and passed" — while every row reads "manual run pending"
  and the doc self-admits "documentation only — no automation". A claimed
  control that no code runs **directly violates CLAUDE.md's core INTEGRITY
  principle** ("every claim verified by execution before statement").
  Karpathy **R4 FAIL**.
- **`eval-suites/*` (6)** are manual scenarios with "No automated runner" —
  never executed. This is precisely the "동작하지 않는 의미 없는 평가"
  (non-functioning meaningless evaluation) the user named. **R4 FAIL.**
- **`risk-registry` / `trust-boundary` / `frontmatter-schema`** carry real
  content but their self-checks grep themselves (tautology), and **nothing
  in the live system references any of it** (grep-proven: zero external
  consumers). **R2** (complexity not needed) + the `.agents/security/`
  mirror describes Claude components Codex cannot use (**R3** — meaningless
  mechanical mirror).
- Net: the framework is **0/10 LIVE, 10/10 VESTIGIAL**; deleting it changes
  **zero** runtime behavior (confirmed by the prior 2026-06-24 audit too).

## Scope decision (destructive-ops-discipline §1/§4)

Alternatives surfaced before acting:
- (narrow) eval-suites/ only — rejected: registry's gate would dangle.
- (mid) eval-suites/ + registry — rejected: risk/trust/schema cross-
  reference each other → orphaned fragments.
- (whole) entire framework, both vendors — **chosen**: one cohesive unit
  (Alt B Phases 0–4), all unreferenced, removal avoids dangling cross-refs.
Blast radius mitigated: git-tracked → fully reversible; kept local (no push).

## Supersedes (honest contradiction note)

This **overrides** the prior audit's **M1-A** ("honest re-wording, do NOT
delete") and Codex's handoff ("do not delete security/ in this pass").
Basis: explicit user instruction "제거" (2026-06-25), treated as a
deliberate override of the conservative recommendation. Re-wording would
retain ~1400 lines of vendor-orthogonal, unwired docs solely to state
honestly that they do nothing — leaving the R2 violation in place. The
prior recommendations are point-in-time; this record supersedes them.

## Orphan cleanup (R3 — only orphans my change created)

- `PROJECT.md` parity table ×2 (dropped `,security` from both vendor cols)
- `AGENTS.md` structure tree + path table ×2 (removed security rows)
- `scripts/sync-agents-mirror.sh` ×2 (dropped `security` from SUB loop +
  mapping comment)

## Verification (re-executed, not asserted)

- live dangling `security/` refs: **0** (only `.audit/` history remains)
- `sync-agents-mirror.sh --dry`: **exit 0**, "0 change(s)" — mirror consistent
- `karpathy-consistency-check.sh`: **PASS ×3** — no regression
- `git status`: 20 deleted (staged) + 3 modified

## Evaluation direction going forward (per user)

The removed eval-suite/registry framework is replaced by **prompt-composed
isolated evaluation** ({contract, diff} only; no author/intent) — empirically
validated in `2026-06-25-h1b-evaluator-isolation-poc.md`. Prompt composition,
not unwired scripted gates, is the self-eval-drift reducer.
