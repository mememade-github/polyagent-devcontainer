# AGENTS.md — Codex CLI governance

## Context

- Workspace: `/workspaces/`; environment: Ubuntu 22.04 DevContainer, user `vscode`.
- In this DevContainer, bubblewrap cannot create user namespaces; Codex shell execution uses `--dangerously-bypass-approvals-and-sandbox` as a compatibility fallback, not a security boundary.
- `.claude/` is ground truth; `.agents/` is its byte-faithful generated mirror, and `.codex/` holds Codex-specific configuration.
- Claude is native/auto-updated at `~/.local/bin/claude`; Codex is npm-global at `~/.npm-global/bin/codex`; `PROJECT_NODE_VERSION` adds project Node; 9p `postStartCommand` sets `core.filemode=false`; project rules: `.claude/rules/project/`; Git helpers: `scripts/git/`.
- Codex does not follow `@import`. At session start, read [`.agents/rules/behavioral-core.md`](.agents/rules/behavioral-core.md), [`.agents/rules/devcontainer-patterns.md`](.agents/rules/devcontainer-patterns.md), [PROJECT.md](PROJECT.md), and [REFERENCE.md](REFERENCE.md).

## Trust model: advisory gates

The container and its host-mounted `docker.sock` are not a security sandbox (see [REFERENCE.md](REFERENCE.md) §Privilege boundary). Hooks are policy tripwires: they block only positive matches and fail open on ambiguity. Positive matches are commit bypass (`--no-verify`/`-n`), secret patterns in staged content or push configuration, force push, or a missing/stale marker. `completion-checker.sh` writes a per-branch marker; the pre-commit gate accepts it by existence and age (under 24 hours), not by content fingerprint. Do not commit credentials or run untrusted code expecting host isolation.

Codex command hooks run only after project trust and `/hooks` review; changed hooks require review. Until then, run the gates manually; use `--dangerously-bypass-hook-trust` only for automation that independently vets them. Codex hook matchers inspect `Bash`; accepted editor tool names are `Bash`, `apply_patch`, `Edit`, and `Write`.

## Automated workflow

- At session start, check `MEMORY.md`; if the hook reports WIP, read each WIP `README.md` and resume the first actionable item. Otherwise wait for user instruction.
- Get explicit approval before `rm -rf`, overwriting `mv`/`cp`, `git push --force`, `git reset --hard`, or database `DROP`/`DELETE`.
- Fix root causes — diagnose across infra/config/deploy/code; no workarounds.
- Explicit failure — every operation must succeed or fail visibly.
- Use the `refine` skill for meaningful changes and direct editing for trivial ones. Run evaluation through `scripts/meta/run-isolated-role.sh` in a fresh `codex exec --ephemeral` context with the exact Contract/diff-only evidence channel, never the modifier's context.
- Invoke `status` for repository/worktree/WIP/upstream/marker state, `verify` for pre-commit checks, and `karpathy-guidelines` when writing, reviewing, or refactoring code.
- For work likely to span sessions, load `.agents/skills/wip-manager/SKILL.md` and use it to manage the work at `wip/task-YYYYMMDD-description/README.md`; delete the WIP directory when complete.
- Before an agent-issued commit, `bash scripts/meta/completion-checker.sh` must pass; it is environment-independent across fresh clones, CI, and temp checkouts. Never bypass verification. Run the docker-backed `.devcontainer/verify-template.sh` on demand and in CI, not per commit.

## Mirror and communication

Edit `.claude/`, then run `bash scripts/sync-agents-mirror.sh`; use `--dry` to check drift. Do not edit `.agents/` by hand. Mirrored skill frontmatter is Claude metadata that Codex ignores. Respond in the user's language unless this file sets a team language.

## Behavioral foundation

The rules derive from [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (MIT).
