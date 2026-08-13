# CLAUDE.md — Project Workspace

Behavioral foundation: [`.claude/rules/behavioral-core.md`](.claude/rules/behavioral-core.md) (Karpathy 4 rules — auto-imported below), also exposed as a skill at [`.claude/skills/karpathy-guidelines/`](.claude/skills/karpathy-guidelines/) (`SKILL.md`) so the evaluator agent and explicit invocations can reference it as a handle. Source: [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (MIT).

## Identity

- **Workspace**: `/workspaces/`
- **Environment**: Dev Container (Ubuntu 22.04, user=vscode)

## Project structure

```
/workspaces/                        # Project root
├── CLAUDE.md                       # Governance — Claude (this file)
├── AGENTS.md                       # Governance — Codex (self-contained mirror)
├── PROJECT.md                      # Domain context (customize per project)
├── REFERENCE.md                    # Commands and procedures
├── .claude/                        # Claude Code agent system (ground truth)
│   ├── settings.json               # Hooks & environment
│   ├── agents/                     # 2 agents (evaluator, wip-manager)
│   ├── hooks/                      # 4 hook scripts
│   ├── skills/                     # 4 skills (refine, status, verify, karpathy-guidelines)
│   └── rules/                      # Standard rules + project/ subdirectory
├── .agents/                        # Codex agent assets (mirror of .claude/, generated)
├── .codex/                         # Codex CLI configuration (config.toml, hooks.json, hooks/, state/)
├── scripts/                        # meta/ (completion-checker, …), git/, sync-agents-mirror.sh
└── .devcontainer/                  # Container configuration + verify-template.sh acceptance suite
```

## Core principle: INTEGRITY

Every claim must be verified by execution before statement. Don't say "tests pass" without running them. Don't say "build succeeds" without building. Don't say "works" without testing.

## Destructive operations (approval required)

`rm -rf`, `mv`/`cp` overwriting existing files, `git push --force`, `git reset --hard`, `DROP`/`DELETE` on databases — never run without explicit user approval.

## Trust model: advisory gates

The hooks are a **policy tripwire, not a security sandbox** (see REFERENCE.md §Privilege boundary). Gate semantics, identical for both vendors:

- **Positive-match blocks only** — a gate blocks (exit 2) only on a positively identified violation: a `--no-verify`/`-n` commit bypass, a secret pattern in staged content or push configuration, a force push, or a missing/stale verification marker.
- **Fail-open on ambiguity** — on any parse failure, internal error, or unrecognized command shape, the gate allows (exit 0). It never fails closed on its own uncertainty.
- **Marker = existence + age** — `completion-checker.sh` writes a per-branch marker file; the pre-commit gate accepts it if it exists and is younger than 24 hours. No content fingerprinting.

## Automated workflow (mandatory)

1. **Session start**: hook reports current branch, active WIP tasks, environment. If WIP tasks exist, read the WIP `README.md` and resume immediately. Otherwise wait for user instruction. Always check auto memory (`MEMORY.md`) for known issues.
2. **Change evaluation**: *meaningful changes* → `/refine` (modify → evaluate → keep/discard loop); *trivial changes* (typo, single config line) → direct edit. Never self-evaluate — delegate to the **evaluator** agent.
3. **Pre-commit verification**: run `scripts/meta/completion-checker.sh` before committing — fast and environment-independent (works in fresh clones, CI, and temp checkouts); it writes the marker the pre-commit gate checks. All checks must pass; `--no-verify` is never permitted. The full docker-backed acceptance suite `.devcontainer/verify-template.sh` runs on demand and in CI, not per commit.
4. **Multi-session tasks**: create a WIP via the **wip-manager** agent at `wip/task-YYYYMMDD-description/README.md`. Auto-resumed on next session start. Delete when complete.

## Coding rules

1. **Read first** — read existing code before modifying.
2. **Keep it simple** — minimum code for the task.
3. **Follow patterns** — match existing style.
4. **Protect secrets** — never commit credentials.
5. **Verify** — build and test before claiming success.
6. **Fix root causes** — no workarounds, no ignoring errors.
7. **Explicit failure** — every operation must succeed or fail visibly.

## Polyagent parity

`.claude/` is the ground truth; `.agents/` and `.codex/` are the Codex mirror. Sync after editing `.claude/`:

```bash
bash scripts/sync-agents-mirror.sh         # update mirror
bash scripts/sync-agents-mirror.sh --dry   # diff only
```

`.agents/` is generated; do not edit by hand.

## Communication

- **Language**: customize per team. Default leaves the responding language to the user. Override here in derived projects (e.g., `Always respond in Korean`).

## Environment

- **Claude Code**: native binary (`~/.local/bin/claude`, auto-updated). **Codex CLI**: npm global (`~/.npm-global/bin/codex`).
- **Node.js**: Node 22 LTS installed for Codex CLI. Additional version installed if `PROJECT_NODE_VERSION` is set.
- **Persistent volumes**: `~/.claude`, `~/.codex`, `/commandhistory`.
- **9p mount**: `core.filemode=false` (auto-applied by `postStartCommand`).

## Extended reference

@.claude/rules/behavioral-core.md
@.claude/rules/devcontainer-patterns.md
@PROJECT.md
@REFERENCE.md
