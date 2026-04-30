# CLAUDE.md — Project Workspace

Behavioral foundation: [`.claude/rules/behavioral-core.md`](.claude/rules/behavioral-core.md) (Karpathy 4 rules — auto-imported below).

The same 4 rules are also exposed as a skill at [`.claude/skills/karpathy-guidelines/`](.claude/skills/karpathy-guidelines/) (`SKILL.md` + `EXAMPLES.md`) so the evaluator agent and explicit invocations can reference them as a handle. Cursor mirror: [`.cursor/rules/karpathy-guidelines.mdc`](.cursor/rules/karpathy-guidelines.mdc). Source: [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (MIT).

## Identity

- **Workspace**: `/workspaces/`
- **Environment**: Dev Container (Ubuntu 22.04, user=vscode)

## Project structure

```
/workspaces/                        # Project root
├── CLAUDE.md                       # Governance — Claude (this file)
├── AGENTS.md                       # Governance — Codex (delta only; references this file)
├── PROJECT.md                      # Domain context (customize per project)
├── REFERENCE.md                    # Commands and procedures
├── .claude/                        # Claude Code agent system (ground truth)
│   ├── settings.json               # Hooks & environment
│   ├── agents/                     # 2 agents (evaluator, wip-manager)
│   ├── hooks/                      # 6 hook scripts
│   ├── skills/                     # 4 /command skills (refine, status, verify, wiki) + karpathy-guidelines
│   └── rules/                      # Standard rules + project/ subdirectory
├── .agents/                        # Codex agent assets (mirror of .claude/, generated)
├── .codex/                         # Codex CLI configuration
│   ├── config.toml                 # Sandbox, approval policy
│   ├── hooks.json                  # Event hooks
│   ├── hooks/                      # 4 hook scripts
│   └── state/                      # Runtime markers (gitignored)
├── .cursor/                        # Cursor mirror (rules/karpathy-guidelines.mdc)
├── scripts/
│   └── sync-agents-mirror.sh       # .claude/ → .agents/ one-way sync (preserve-extras)
└── .devcontainer/                  # Container configuration
```

## Core principle: INTEGRITY

Every claim must be verified by execution before statement. Don't say "tests pass" without running them. Don't say "build succeeds" without building. Don't say "works" without testing.

## Destructive operations (approval required)

`rm -rf`, `mv`/`cp` overwriting existing files, `git push --force`, `git reset --hard`, `DROP`/`DELETE` on databases — never run without explicit user approval.

## Automated workflow (mandatory)

These rules are enforced by hooks; no user commands required.

1. **Session start**: hook reports current branch, active WIP tasks, environment. If WIP tasks exist, read the WIP `README.md` and resume immediately. Otherwise wait for user instruction. Always check auto memory (`MEMORY.md`) for known issues.
2. **Change evaluation**:
   - *Meaningful changes* → use `/refine` (modify → evaluate → keep/discard loop). The pre-commit hook emits a non-blocking WARNING when `/refine` marker is absent for multi-file commits.
   - *Trivial changes* (typo, single config line) → direct edit.
   - Never self-evaluate. Delegate to the **evaluator** agent.
3. **Pre-commit gate**: `pre-commit-gate.sh` runs verification for affected code before any `git commit`. All checks must pass; no `--no-verify`.
4. **Multi-session tasks**: tasks likely to span sessions create a WIP via the **wip-manager** agent at `wip/task-YYYYMMDD-description/README.md`. Auto-resumed on next session start. Delete when complete.
5. **Agent delegation**: `evaluator` after changes (1-pass review; within `/refine`); `wip-manager` when work spans sessions.

## Coding rules

1. **Read first** — read existing code before modifying.
2. **Keep it simple** — minimum code for the task.
3. **Follow patterns** — match existing style.
4. **Protect secrets** — never commit credentials.
5. **Verify** — build and test before claiming success.
6. **Fix root causes** — no workarounds, no ignoring errors.
7. **Explicit failure** — every operation must succeed or fail visibly.

## Polyagent parity

| Vendor | Source of truth | Mirror |
|--------|-----------------|--------|
| Claude Code | `CLAUDE.md`, `.claude/` | — |
| Codex CLI | (mirror) | `AGENTS.md`, `.agents/`, `.codex/` |

Sync after editing `.claude/`:

```bash
bash scripts/sync-agents-mirror.sh         # update mirror
bash scripts/sync-agents-mirror.sh --dry   # diff only
```

`.agents/` is generated; do not edit by hand.

## Communication

- **Language**: customize per team. Default leaves the responding language to the user. Override here in derived projects (e.g., `Always respond in Korean`).

## Environment

- **Ports**: `.devcontainer/.env` (`PORT_APP`, `PORT_API`, `PORT_DB`, `PORT_EXTRA`).
- **Claude Code**: native binary (`~/.local/bin/claude`, auto-updated).
- **Codex CLI**: npm global (`~/.npm-global/bin/codex`).
- **Node.js**: Node 22 LTS installed for Codex CLI. Additional version installed if `PROJECT_NODE_VERSION` is set.
- **Persistent volumes**: `~/.claude`, `~/.codex`, `/commandhistory`.
- **9p mount**: `core.filemode=false` (auto-applied by `postStartCommand`).

## Extended reference

@.claude/rules/behavioral-core.md
@.claude/rules/audit-discipline.md
@.claude/rules/commit-discipline.md
@.claude/rules/destructive-ops-discipline.md
@PROJECT.md
@REFERENCE.md

---

*Last updated: 2026-04-30*
