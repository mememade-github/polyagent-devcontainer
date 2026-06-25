# Execution record — Codex CLI auto-update feature (DAG R/V/Audit)

> Companion to the frozen audit anchor
> [`2026-06-24-codex-config-audit-anchor.md`](2026-06-24-codex-config-audit-anchor.md).
> The anchor stays frozen (anchor-discipline P1); this file is the execution log.
>
> **Role note (E6 revoked by user dictation):** the auditor-only boundary was
> conditional on Codex executing. Codex hit a token limit, so the user
> reassigned execution to Claude ("Codex 토큰 이슈로 당신이 수행 … 실제 실행은
> 클로드가"). The *decision* (the DAG) was still made by Codex/user; Claude is the
> executor of that decided plan. Cycle performed: 연구조사 → 계획 → 실행 → 감사.

## 1. Essence

Codex CLI was frozen at the image-build snapshot while Claude self-updates every
start → version drift. Feature: symmetric auto-update for Codex in
`setup-env.sh`, opt-out via `SKIP_CODEX_UPDATE=1`. (Audit node F13 / Codex DAG
R1–R4.)

## 2. Research — decisive finding (why mechanism ≠ `codex update`)

Mirroring `claude update` → `codex update` would have shipped a **no-op**:

```
$ codex update           # codex-cli 0.130.0, run as vscode
Updating Codex via `npm install -g @openai/codex`...
npm error code EACCES  path /usr/lib/node_modules/@openai  errno -13
Error: `npm install -g @openai/codex` failed (exit 243)
```

`codex update`'s built-in updater installs to the **default** global prefix
`/usr/lib/node_modules` (root-owned; `vscode` cannot write). The Dockerfile
(line 98–99) installs codex to `--prefix ${HOME}/.npm-global` **specifically so
it stays updatable without root** (Dockerfile comment line 95–96). Correct
mechanism therefore mirrors the **Dockerfile**, not `codex update`:

```
npm install -g --prefix "${HOME}/.npm-global" @openai/codex@latest
```

Verified live on host devcontainer (vscode): `0.130.0 -> 0.142.0`, exit 0, PATH
intact. Latest published at audit time = 0.142.0 (drift was real).

## 3. Changes (3 files, 1 concern — Codex auto-update)

| File | Change |
|------|--------|
| `.devcontainer/setup-env.sh` | `STEP_TOTAL` 4→5; new `[4/5] Codex CLI version` step (prefix-npm mechanism, soft-fail, `SKIP_CODEX_UPDATE=1`); symlink step renumbered `[5/5]`. Inline comment records the `codex update` EACCES rationale so it is not "simplified" back. |
| `REFERENCE.md` | Lifecycle box 4→5 steps; "5 steps run"; rolling-policy bullet for Codex update + why-not-`codex update`; reproducibility note adds `SKIP_CODEX_UPDATE=1`. |
| `.devcontainer/verify-template.sh` | New "Phase 1b" regression guard: asserts `STEP_TOTAL=5`, both SKIP vars, and `@openai/codex@latest` mechanism persist (so a future edit that drops the step or reverts to `codex update` FAILs verify — audit §2 counter-test). |

**Deliberately NOT changed (surfaced, not silently omitted):**
- **README.md** — documents *neither* CLI's update lifecycle today; adding only
  Codex's breaks symmetry, adding both duplicates REFERENCE (Karpathy R2/R3 +
  DRY). REFERENCE owns the lifecycle; README delegates to it.
- **Mirror sync** — not run: no `.claude/` file was touched (edits are
  `.devcontainer/` + root docs). `sync --dry` left clean.
- **AGENTS.md / CLAUDE.md / PROJECT.md** — none document the setup lifecycle, so
  no parity edit is warranted for this feature.

## 4. Verification (INTEGRITY — executed, not asserted)

| Check | Result |
|-------|--------|
| `bash -n setup-env.sh` / `verify-template.sh` | OK |
| `verify-template.sh` (PROJECT_DIR=/workspaces) | **37 PASS / 0 FAIL** (Phase 1b all green) |
| **External container** (`polyagent-devcontainer:latest`, user=vscode, new script `docker cp`'d, codex downgraded to 0.130.0) | `[4/5] Codex CLI version... 0.130.0 -> 0.142.0`; after=0.142.0 persisted |
| Container — `SKIP_CODEX_UPDATE=1` | `Skipped (SKIP_CODEX_UPDATE=1), current: codex-cli 0.142.0` |
| Container — 5-step lifecycle renumber | `[1/5]…[5/5]` all correct |

Side effect: host devcontainer's codex CLI is now 0.142.0 (the feature working;
harmless, desired).

## 5. Separate concerns — executed as independent commits (전체 수행, user go)

Each committed independently (commit-discipline), not bundled with the feature:
- **config.toml hygiene + F2 root cause** -> commit `7f6e14a`. Stripped the
  runtime-state leak (nux/migrations); setup-env step 5 symlink->copy so Codex
  no longer writes into the tracked file. Kept model/effort/trust_level (user's
  intentional config). Container-verified (migrate + no-leak).
- **`.cursor` vendor removal** -> commit `c77d9bf`. Resolves F19. Deleted the
  mirror file + scrubbed every reference (README x3, CLAUDE x2, audit-discipline
  + .agents mirror, karpathy-consistency-check oracle). Verified: consistency
  PASS, sync --dry clean, 0 residual cursor refs (hidden incl).
- **variants/datascience** -> removed (moved to session scratchpad, reversible).
  Untracked/gitignored -> no repo/commit change.

## 6. Status

All four concerns **executed + verified**. Three independent commits on `main`
(not pushed): `9416fa3` (feature), `7f6e14a` (config/F2), `c77d9bf` (cursor).
Integrated container test (steps 4+5 together, as vscode): 0.130.0 -> 0.142.0,
symlink -> copy, no leak. verify-template 37/0, karpathy-consistency PASS.
Remaining: `.audit/` trail is untracked (gitignore vs commit — user decision).

*Last updated: 2026-06-24*
