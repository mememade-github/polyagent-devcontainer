# AGENTS.md — Codex CLI governance

> Codex CLI mirror of [CLAUDE.md](CLAUDE.md). Codex CLI auto-loads this file on session start, so all behavioral rules must live inline here — Codex does not follow `@import` or cross-file references automatically. The same rules in Claude form are at [CLAUDE.md](CLAUDE.md).

## Behavioral foundation

Karpathy 4-rule: [`.agents/rules/behavioral-core.md`](.agents/rules/behavioral-core.md) (Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution). Load explicitly with the `Read` tool at session start.

Skill mirror: [`.agents/skills/karpathy-guidelines/`](.agents/skills/karpathy-guidelines/) (`SKILL.md` + `EXAMPLES.md`). Source: [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (MIT).

## Identity

- **Workspace**: `/workspaces/`
- **Environment**: Dev Container (Ubuntu 22.04, user=vscode)

## Project structure

```
/workspaces/                        # Project root
├── AGENTS.md                       # Governance — Codex (this file)
├── CLAUDE.md                       # Governance — Claude (mirror)
├── PROJECT.md                      # Domain context (customize per project)
├── REFERENCE.md                    # Commands and procedures
├── .codex/                         # Codex CLI configuration
│   ├── config.toml                 # MCP, sandbox, approval policy
│   ├── hooks.json                  # Event hook registrations
│   ├── hooks/                      # 4 hook scripts
│   └── state/                      # Runtime markers (gitignored)
├── .agents/                        # Codex agent assets (mirror of .claude/)
│   ├── rules/                      # Behavioral rules
│   ├── security/                   # Trust boundary, registry mirror
│   └── skills/                     # Skill mirror + agent-as-skill conversions
├── .claude/                        # Claude Code agent system (ground truth)
└── .devcontainer/                  # Container configuration
```

## Core principle: INTEGRITY

Every claim must be verified by execution before statement. Don't say "tests pass" without running them. Don't say "build succeeds" without building. Don't say "works" without testing.

## Destructive operations (approval required)

Never execute without explicit user approval: `rm -rf`, `mv`/`cp` overwriting existing files, `git push --force`, `git reset --hard`, `DROP`/`DELETE` on databases.

## Automated workflow (mandatory)

Enforced by hooks (`.codex/hooks.json`); no user commands required.

### Session start (SessionStart hook)

- Hook injects: current branch, active WIP tasks, environment info.
- If WIP tasks exist, read the WIP `README.md` and resume work immediately.
- Otherwise wait for user instruction.
- Always check auto memory (`MEMORY.md`) for known issues.

### Change evaluation

- *Meaningful changes* → use the `refine` skill (`.agents/skills/refine/`) — modify → evaluate → keep/discard loop, not optional.
- *Trivial changes* (typo, single config line) → direct edit, no evaluation needed.
- Never self-evaluate. Delegate to the `evaluator` skill (`.agents/skills/evaluator/`).

### Pre-commit gate (PreToolUse hook)

Before any `git commit`:
1. Run verification for affected code (auto-detected by file type).
2. All checks must pass; no `--no-verify`.

### Multi-session tasks

- Tasks likely to span sessions → invoke the `wip-manager` skill at `wip/task-YYYYMMDD-description/README.md`.
- Auto-resumed on next session start.
- Delete the WIP directory when complete.

### Skill delegation

Codex CLI does not yet support file-based custom sub-agent declarations, so the responsibilities of Claude's sub-agents are absorbed as skills:

| Skill | When to invoke |
|-------|----------------|
| refine | Meaningful changes requiring iterative refinement |
| evaluator | After changes (1-pass review); within the `refine` loop |
| wip-manager | When a task spans sessions |
| status | Workspace status snapshot |
| verify | Pre-commit verification |

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

- **Ports**: `.devcontainer/.env` (`PORT_APP`, `PORT_API`, `PORT_DB`, `PORT_EXTRA`).
- **Claude Code**: native binary (`~/.local/bin/claude`, auto-updated).
- **Codex CLI**: npm global (`~/.npm-global/bin/codex`).
- **Node.js**: Node 22 LTS for MCP infrastructure. Additional version installed if `PROJECT_NODE_VERSION` is set.
- **Persistent volumes**: `~/.claude`, `~/.codex`, `/commandhistory`.
- **9p mount**: `core.filemode=false` (auto-applied by `postStartCommand`).
- **MCP**: Context7, Serena (managed at the DevContainer level).

## Codex-specific paths

| Path | Purpose |
|------|---------|
| `.codex/config.toml` | MCP servers, sandbox/approval policy |
| `.codex/hooks.json` | Event hook registrations |
| `.codex/hooks/` | 4 hook scripts (session-start, pre-commit-gate, pre-push-gate, refinement-gate) |
| `.codex/state/` | Runtime markers (gitignored) |
| `.agents/rules/` | Behavioral-rule mirror of `.claude/rules/` |
| `.agents/skills/` | Skill mirror of `.claude/skills/` plus Codex-side conversions of `.claude/agents/*` |
| `.agents/security/` | Trust boundary, registry mirror |

## Vendor constraints

| Constraint | Workaround |
|------------|------------|
| `Edit`/`Write` not available as PreToolUse matcher | Use `Bash(...)` patterns only |
| No sub-agent isolation | Absorb agents as skills (`.agents/skills/`) |
| `frontmatter.tools` / `model` / `color` ignored | Body is preserved; vendor ignores extras |
| No `@import` in AGENTS.md | This file must be self-contained; cross-file refs require explicit `Read` |

## Mirror sync

`.claude/` is the ground truth. After editing it:

```bash
bash scripts/sync-agents-mirror.sh         # regenerate .agents/
bash scripts/sync-agents-mirror.sh --dry   # diff only
```

Do not edit `.agents/` by hand.

## Behavioral rules to load on session start

Codex CLI does not auto-follow file references, so explicitly `Read` these:

- [.agents/rules/behavioral-core.md](.agents/rules/behavioral-core.md) — Karpathy 4-rule.
- [.agents/rules/devcontainer-patterns.md](.agents/rules/devcontainer-patterns.md) — DevContainer DinD avoidance and volume-mount path translation.

## Domain context

- [PROJECT.md](PROJECT.md) — domain context (services, infrastructure)
- [REFERENCE.md](REFERENCE.md) — commands, environment variables, ports, troubleshooting

---

*Last updated: 2026-04-30*
