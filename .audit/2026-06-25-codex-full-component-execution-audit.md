# Codex Full-Component Execution Audit

*Date: 2026-06-25 | Base: `71708fb` | Scope: all live project components |
Status: COMPLETE, LOCAL ONLY, NO PUSH*

## 1. Purpose verdict

The project purpose is a single DevContainer template that runs Claude Code and
Codex CLI against one governance source while preserving vendor-specific runtime
semantics. After remediation, every live component has one of four direct roles:

1. governance;
2. execution or lifecycle enforcement;
3. generated vendor parity;
4. executable verification.

The removed `security/` framework and `wiki` skill remain correctly removed:
they had no executing consumers. Their useful invariant, flat frontmatter
validation, now lives in the executable oracle instead of a 1,446-line manual
framework.

## 2. Exhaustive census

| Surface | Audited elements | Execution evidence |
|---|---|---|
| Governance | `CLAUDE.md`, `AGENTS.md`, `PROJECT.md`, `README.md`, `REFERENCE.md` | count/path/claim cross-check; six-rule import/load checks |
| Rules | 6 Claude + 6 Codex mirrors | named presence, byte parity, Karpathy oracle, positive/regression fixtures |
| Skills | refine, status, verify, karpathy-guidelines + mirrors | path/state commands, marker round-trips, schema checks |
| Agents | evaluator, wip-manager + converted Codex skills | exact frontmatter schema, isolated evaluator execution, local-only WIP contract |
| Hooks | Claude 4 + Codex 4 | 15 event fixtures: block/pass/JSON/no-side-effect axes |
| Config | Claude settings, Codex config, Codex hooks | JSON/TOML parse, registration paths, live Codex parser |
| Scripts | sync, completion, consistency, status, isolated-role helper | direct execution and injected fault fixtures |
| DevContainer | Dockerfile, entrypoint, setup, verify, compose, devcontainer config, env example | fresh image build and boot; Compose/devcontainer parse |
| Runtime state | `.claude` and `.codex/state` markers | both-vendor verify/refine round-trips |

Negative space: no push was performed; remote CI and GUI-only VS Code extension
behavior were not exercised. Model-quality behavior beyond the supplied
contracts remains probabilistic; wiring and isolation are mechanically guarded.

## 3. Findings and remediation

| ID | Severity | Finding | Remediation |
|---|---|---|---|
| F1 | HIGH | Real Codex sessions had `CODEX_PROJECT_DIR` unset; refine selected `.claude`, so the Codex Stop gate stayed dead. | Detect `CODEX_CI`/`CODEX_THREAD_ID`; vendor-specific state for refine/status/completion. |
| F2 | HIGH | Codex evaluator isolation was prose-only; Audit/Modify were still in-process and evaluator output path was not passed. | Added executable `run-isolated-role.sh`; three fresh roles; explicit ignored `$EVAL_JSON`; mutation detection. |
| F3 | HIGH | Evaluate started in `/workspaces`, reloaded `AGENTS.md`, and recursively launched another evaluator. | Evaluate now starts in an ephemeral directory with `--skip-git-repo-check`; offline cwd guard added. |
| F4 | HIGH | Sync deletion propagation missed nested files, root conflicts, and file/directory conflicts. | Build expected tree first, pre-prune all type conflicts, copy, then assert zero drift. |
| F5 | HIGH | Sync accepted symlink-bearing trees and could mutate before rejection. | Source/destination symlink rejection occurs before destination creation or copy. |
| F6 | MEDIUM | Verify counted six rules but named only five; four Codex rules were previously dark. | All six are named, imported, explicitly loaded, and byte-compared. |
| F7 | MEDIUM | Removing `security/` also removed its only useful schema invariant. | Exact flat frontmatter key sets, scalar values, names, and delimiters are executable checks. |
| F8 | MEDIUM | WIP completion required push and triggered from file count, contradicting local-only work. | Trigger by session span; local commit is sufficient unless push is requested. |
| F9 | MEDIUM | `.codex/hooks.json` used unsupported `$comment`; Codex emitted a parse warning. | Removed unsupported metadata; live parser is clean. |
| F10 | LOW | Codex Stop hook created refinement directories without an active marker. | Defer directory creation until marker validation. |
| F11 | LOW | Status claimed all repositories although this is a single-repository base template, and marker glob missed Claude dotfiles. | Scope made explicit; vendor marker prefix is quoted and tested. |
| F12 | LOW | Docs called AGENTS a delta and sync `preserve-extras`; config was called a permanent source despite seed-only behavior. | Claims aligned to self-contained AGENTS, exact mirror, and config seed semantics. |

## 4. Execution evidence

Local final:

- `completion-checker.sh`: **80 PASS / 0 FAIL**
- `karpathy-consistency-check.sh`: **PASS**
- `sync-agents-mirror.sh --dry`: **0 changes**
- hook event fixture: **15 PASS / 0 FAIL**
- Claude/Codex verify markers: **PASS**
- Claude/Codex refine marker-to-Stop-gate round-trips: **PASS**
- JSON/TOML, Compose, DevContainer configuration: **PASS**
- all shell syntax and `git diff --check`: **PASS**

Injected counter-tests:

- real `sk-` secret blocked; hyphenated task identifier allowed;
- nested/top-level mirror orphan detected and pruned;
- root and nested file/directory conflicts reconciled to zero drift;
- source/destination symlinks rejected before mutation;
- fake Audit mutation detected;
- three separate ephemeral role invocations observed;
- evaluator output verified gitignored;
- Evaluate child verified outside the project root.

External final:

- image: `polyagent-devcontainer:audit-20260625`
  (`sha256:d5c48e06109b404920779c16b16e8ae80f4a37c61ab87163cb517795d558f350`)
- fresh entrypoint: **5/5 setup steps**
- `verify-template.sh`: **80 PASS / 0 FAIL**
- sync dry-run: **0 changes**
- both vendor markers, Codex refine gate, shell syntax, and config seed: **PASS**

Isolated evaluator:

- first pass found missing real-env H3 coverage, incomplete exact sync, weak
  frontmatter evidence, and status/evaluator contract gaps; all reproduced;
- second pass found output-path, pre-mutation, and fixture-strength gaps; all
  reproduced;
- a later real run exposed evaluator recursion through project `AGENTS.md`; the
  process was stopped and F3 fixed;
- the final post-fix LLM response was blocked by Codex usage quota, but the child
  workdir, non-recursion, mutation guard, and external 80/0 path were executed.

## 5. Commits

| Commit | Concern |
|---|---|
| `13d1a8d` | WIP local-only completion and narrower tools |
| `fac9c72` | Codex config seed semantics |
| `eb78d0e` | vendor state and isolated Codex roles |
| `c016da9` | helper executable mode for clean checkouts |
| `26cc537` | supported Codex hooks schema |
| `19cbb56` | exact mirror and executable parity oracle |
| `6c61814` | evaluator recursion prevention |

## 6. Final assessment

**PASS.** All current live component classes are purpose-aligned and have an
executed consumer or an executable integrity guard. The remaining risk is not a
known wiring defect: LLM role quality is probabilistic, and DevContainer Codex
children use sandbox bypass because nested bubblewrap is unavailable. The
container boundary plus before/after Git-state checks limit that risk.
