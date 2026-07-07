# AGENTS.md — Codex CLI governance

> Codex CLI mirror of [CLAUDE.md](CLAUDE.md). Codex auto-loads this file on session start but does not follow `@import` or cross-file references, so explicitly `Read` the rule files listed in *Behavioral rules to load on session start* (below) at the start of each session.

## Behavioral foundation

Karpathy 4-rule: [`.agents/rules/behavioral-core.md`](.agents/rules/behavioral-core.md) (Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution). Load explicitly with the `Read` tool at session start. Skill mirror: [`.agents/skills/karpathy-guidelines/`](.agents/skills/karpathy-guidelines/) (`SKILL.md` + `EXAMPLES.md`). Source: [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (MIT).

## Identity

- **Workspace**: `/workspaces/` · **Environment**: Dev Container (Ubuntu 22.04, user=vscode)

## Project structure

```
/workspaces/                        # Project root
├── AGENTS.md                       # Governance — Codex (this file)
├── CLAUDE.md                       # Governance — Claude (mirror)
├── PROJECT.md                      # Domain context (customize per project)
├── REFERENCE.md                    # Commands and procedures
├── .codex/                         # Codex CLI configuration (config.toml, hooks.json, hooks/, state/)
├── .agents/                        # Codex agent assets (mirror of .claude/): rules/ + skills/
├── .claude/                        # Claude Code agent system (ground truth)
├── scripts/                        # meta/ (completion-checker, …), git/, sync-agents-mirror.sh
└── .devcontainer/                  # Container configuration + verify-template.sh acceptance suite
```

## Core principle: INTEGRITY

Every claim must be verified by execution before statement. Don't say "tests pass" without running them. Don't say "build succeeds" without building. Don't say "works" without testing.

## Destructive operations (approval required)

Never execute without explicit user approval: `rm -rf`, `mv`/`cp` overwriting existing files, `git push --force`, `git reset --hard`, `DROP`/`DELETE` on databases.

## Trust model: advisory gates

The hooks are a **policy tripwire, not a security sandbox** (see REFERENCE.md §Privilege boundary). Blocking Codex command hooks run only after the project is trusted and the hook definitions are reviewed in `/hooks`; changed hooks are skipped until re-reviewed. Vetted non-interactive automation may use `--dangerously-bypass-hook-trust`; otherwise run the gates manually until hook trust is established. Gate semantics, identical for both vendors:

- **Positive-match blocks only** — a gate blocks (exit 2) only on a positively identified violation: a `--no-verify`/`-n` commit bypass, a secret pattern in staged content or push configuration, a force push, or a missing/stale verification marker.
- **Fail-open on ambiguity** — on any parse failure, internal error, or unrecognized command shape, the gate allows (exit 0). It never fails closed on its own uncertainty.
- **Marker = existence + age** — `completion-checker.sh` writes a per-branch marker file; the pre-commit gate accepts it if it exists and is younger than 24 hours. No content fingerprinting.

## Automated workflow (mandatory)

### Session start (SessionStart hook)

Hook injects current branch, active WIP tasks, and environment info. If WIP tasks exist, read the WIP `README.md` and resume work immediately; otherwise wait for user instruction. Always check auto memory (`MEMORY.md`) for known issues.

### Change evaluation

- *Meaningful changes* → use the `refine` skill (`.agents/skills/refine/`) — modify → evaluate → keep/discard loop.
- *Trivial changes* (typo, single config line) → direct edit, no evaluation needed.
- Never self-evaluate. On Codex, run the `evaluator` skill in a fresh `codex exec --ephemeral` subprocess via `scripts/meta/run-isolated-role.sh`; its contract requires an exact Contract/diff-only evidence channel, so do not evaluate in the parent context.

### Pre-commit gate (PreToolUse hook)

Before any agent-issued `git commit`: run `scripts/meta/completion-checker.sh` — fast and environment-independent (works in fresh clones, CI, and temp checkouts); it writes the marker the gate checks (existence + 24h age). All checks must pass; `--no-verify` is never permitted. The full docker-backed acceptance suite `.devcontainer/verify-template.sh` runs on demand and in CI, not per commit.

### Multi-session tasks

Tasks likely to span sessions → invoke the `wip-manager` skill at `wip/task-YYYYMMDD-description/README.md`. Auto-resumed on next session start; delete the WIP directory when complete.

### Role delegation

| Skill | When to invoke |
|-------|----------------|
| refine | Meaningful changes requiring iterative refinement |
| evaluator | After changes (1-pass review); within the `refine` loop |
| wip-manager | When a task spans sessions |
| status | Current-repository status, WIP, and environment snapshot |
| verify | Pre-commit verification |
| karpathy-guidelines | Karpathy 4-rule reference handle (direct invocation or via evaluator) |

## Coding rules

1. **Read first** — read existing code before modifying.
2. **Keep it simple** — minimum code for the task.
3. **Follow patterns** — match existing style.
4. **Protect secrets** — never commit credentials or API keys.
5. **Verify** — build and test before claiming success.
6. **Fix root causes** — diagnose across infra/config/deploy/code; no workarounds.
7. **Explicit failure** — every operation must succeed or fail visibly.

## Communication

- **Language**: customize per team. Default leaves the responding language to the user. Override here in derived projects (e.g., `Always respond in Korean`).

## Environment

- **Claude Code**: native binary (`~/.local/bin/claude`, auto-updated). **Codex CLI**: npm global (`~/.npm-global/bin/codex`).
- **Node.js**: Node 22 LTS installed for Codex CLI. Additional version installed if `PROJECT_NODE_VERSION` is set.
- **Persistent volumes**: `~/.claude`, `~/.codex`, `/commandhistory`. **9p mount**: `core.filemode=false` (auto-applied by `postStartCommand`).

## Vendor constraints

- Claude and Codex tool matcher names differ — Codex accepts `Bash`, `apply_patch`, `Edit`, and `Write`; the commit/push gates inspect `Bash` commands.
- Evaluator must not inherit parent intent — fresh `codex exec --ephemeral` subprocess with a minimal evidence prompt.
- Mirrored `SKILL.md` frontmatter (`tools`, `model`, `maxTurns`, `color`) is Claude-host metadata — body is preserved; Codex ignores extras.
- No `@import` in AGENTS.md — this file must be self-contained; cross-file refs require explicit `Read`.

## Mirror sync

`.claude/` is the ground truth; `.agents/` is generated — do not edit it by hand. After editing `.claude/`, run `bash scripts/sync-agents-mirror.sh` (append `--dry` for diff only).

## Behavioral rules to load on session start

- [.agents/rules/behavioral-core.md](.agents/rules/behavioral-core.md) — Karpathy 4-rule (Think / Simplicity / Surgical / Goal).
- [.agents/rules/devcontainer-patterns.md](.agents/rules/devcontainer-patterns.md) — DevContainer DinD avoidance and volume-mount path translation.
- Domain context: [PROJECT.md](PROJECT.md) (services, infrastructure) · [REFERENCE.md](REFERENCE.md) (commands, environment variables, troubleshooting).
