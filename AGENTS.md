# AGENTS.md — Shared governance for Claude Code, Codex CLI, and Antigravity CLI

## Context

- Workspace: `/workspaces/`; environment: Ubuntu 22.04 DevContainer, user `vscode`.
- In this DevContainer, bubblewrap cannot create user namespaces; Codex shell execution uses `--dangerously-bypass-approvals-and-sandbox` as a compatibility fallback, not a security boundary.
- This file is the single hand-maintained source of the shared duties and behavioral rules for all three vendors; `CLAUDE.md` imports it for Claude Code. `.claude/` is the source of the rules, skills, and agent roles that `scripts/sync-agents-mirror.sh` copies into the generated `.agents/rules/` and `.agents/skills/`. `.agents/hooks.json`, `.agents/hooks/`, and `.agents/rules.json` are hand-maintained Antigravity configuration, and `.codex/` holds hand-maintained Codex configuration.
- Claude is native/auto-updated at `~/.local/bin/claude`; Codex is npm-global at `~/.npm-global/bin/codex`; Antigravity (`agy`) is a self-updating native binary at `~/.local/bin/agy`; `PROJECT_NODE_VERSION` adds project Node; 9p `postStartCommand` sets `core.filemode=false`; project rules: `.claude/rules/project/`; Git helpers: `scripts/git/`.
- Claude Code reads this file and [PROJECT.md](PROJECT.md) through the imports in `CLAUDE.md` and loads `.claude/rules/`, including `.claude/rules/project/`, by itself. Codex loads only this file and does not follow `@` imports: on Codex, at session start, read [PROJECT.md](PROJECT.md) and every `.md` file under `.agents/rules/project/`, including subfolders. Antigravity loads `.agents/rules/project/` through `.agents/rules.json`; on Antigravity, read [PROJECT.md](PROJECT.md) at session start. Read [REFERENCE.md](REFERENCE.md) when the task needs commands, configuration, or troubleshooting.

## Trust model: advisory gates

The container and its host-mounted `docker.sock` are not a security sandbox (see [REFERENCE.md](REFERENCE.md) §Privilege boundary). Hooks are policy tripwires: they block only positive matches and fail open on ambiguity. Positive matches are commit bypass (`--no-verify`/`-n`), credential patterns in command text or push configuration, force push, or a missing/stale marker. `completion-checker.sh` writes a per-branch marker; the pre-commit gate accepts it by existence and age (under 24 hours), not by content fingerprint. Do not commit credentials or run untrusted code expecting host isolation.

Codex command hooks run only after project trust and `/hooks` review; changed hooks require review. Until then, run the gates manually; use `--dangerously-bypass-hook-trust` only for automation that independently vets them. Codex hook matchers inspect `Bash`; accepted editor tool names are `Bash`, `apply_patch`, `Edit`, and `Write`.

## Automated workflow

- At session start, if the hook reports WIP and the current request permits resuming saved work, read the relevant WIP `README.md` and continue its first actionable item. Otherwise follow the current request, and wait only if no task has been supplied.
- The request or approved plan sets scope. Keep changes surgical; report unrelated issues. Commit tests only when requested or customary here; keep scratch checks outside the repository.
- Base judgments, actions, and reports on actual facts relevant to authorized requirements; substantiate behavioral claims by executing the relevant behavior and observing results at the claimed boundary. Substantiate structural claims (path, symbol, reference) by reading the source. This does not expand the request's check scope or repository-defined tier timing.
- String searches, pattern/byte/count comparisons, syntax passes, and completed checklists establish only the properties actually checked; do not substitute these formal results for evidence of meaning, compliance, or behavior they did not examine.
- Create, retain, or enforce checks only to obtain relevant evidence for authorized requirements, and make them gates only when those requirements are prerequisites for the work they block.
- On failure, distinguish an actual requirement violation, a faulty or inapplicable check, and missing evidence; act within scope on what is established, and report what remains unobserved.
- Ground progress and completion claims in tool results from this session. State failed or skipped checks plainly.
- Get explicit approval before `rm -rf`, overwriting `mv`/`cp`, `git push --force`, `git reset --hard`, or database `DROP`/`DELETE`.
- Fix root causes — diagnose across infra/config/deploy/code; no workarounds.
- Explicit failure — every operation must succeed or fail visibly.
- Before a meaningful change, state the authorized requirement and acceptance conditions; make trivial edits directly. A change is meaningful when it alters behavior, a duty, an interface, an operating procedure, or a generation relationship, including in documentation alone; a typo fix that changes no meaning is a trivial edit. For that change, have an evaluator in a fresh context, never the modifier's, judge the actual diff against those conditions using observed evidence and the permitted inputs in the evaluator role (`.claude/agents/evaluator.md`, generated as `.agents/skills/evaluator/SKILL.md`), using a fresh **evaluator** subagent on Claude Code, `scripts/meta/run-isolated-role.sh evaluate` on Codex, or a fresh built-in `self` subagent on Antigravity. The evaluation is incomplete when no fresh evaluator context can be created, when the evaluator leaves no report, or when its report does not judge the actual diff; report it as incomplete and do not treat the change as evaluated. Repeat only for an evidenced gap in the authorized outcome; no count, score, or pass rate decides acceptance.
- Invoke `status` for repository/worktree/WIP/upstream/marker state and `verify` for pre-commit checks.
- For work likely to span sessions, manage the work at `wip/task-YYYYMMDD-description/README.md` with the wip-manager role (the **wip-manager** agent on Claude Code; load `.agents/skills/wip-manager/SKILL.md` on Codex and Antigravity); delete the WIP directory when complete.
- Before an agent-issued commit, `bash scripts/meta/completion-checker.sh` must pass; it is environment-independent across fresh clones and temp checkouts. Never bypass verification. Run the docker-backed `.devcontainer/verify-template.sh` on demand, not per commit.

## Antigravity

Keep `trigger: always_on` frontmatter on source rules; `.agents/rules.json` registers `.agents/rules/project`, and any deeper rule folder must be registered there.

## Mirror and communication

Edit `.claude/`, then run `bash scripts/sync-agents-mirror.sh`; use `--dry` to check drift. Do not edit `.agents/rules/` or `.agents/skills/` by hand; the sync leaves the other `.agents/` files untouched. Codex uses skill names and descriptions for discovery; Claude-specific role metadata such as tools, model, and color does not configure the Codex role. Respond in the user's language unless this file sets a team language.

## Behavioral rules

The four rules and the closing check below are adapted from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) as packaged in [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (MIT). The other duties in this file are this template's own.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

State assumptions that affect the approach. If different readings would materially change the result, present them or ask. Say when a simpler approach is sufficient.

### 2. Simplicity First

Implement only requested behavior. Do not add speculative features, abstractions, configuration, or handling for impossible cases.

### 3. Surgical Changes

Read before editing, match existing style, and change only lines traceable to the request. Leave unrelated cleanup alone; remove only orphans your change creates.

### 4. Goal-Driven Execution

Turn the request into verifiable outcomes and run the relevant checks before claiming completion. Never claim tests, builds, or behavior passed without tool evidence.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
