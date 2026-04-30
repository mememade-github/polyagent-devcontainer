# REFERENCE.md — Commands & Procedures

> Actionable commands, configuration, and troubleshooting.
> For domain context, see [PROJECT.md](PROJECT.md).

## Configuration (`.devcontainer/.env`)

All user-tunable values live in `.devcontainer/.env`.

| Variable | Default | Used by | Purpose |
|----------|---------|---------|---------|
| `COMPOSE_PROJECT_NAME` | `polyagent-devcontainer` | docker-compose.yml | Docker namespace |
| `CONTAINER_NAME` | `polyagent-dev` | docker-compose.yml | Container name |
| `IMAGE_NAME` | `polyagent-devcontainer` | docker-compose.yml | Image name |
| `IMAGE_TAG` | `latest` | docker-compose.yml | Image tag |
| `TZ` | `UTC` | docker-compose.yml | Timezone |
| `PROJECT_NODE_VERSION` | *(empty)* | Dockerfile ARG | Project Node.js version (empty = not installed) |
| `PORT_APP` | `31000` | docker-compose.yml ports | App / dev server |
| `PORT_API` | `31080` | docker-compose.yml ports | API |
| `PORT_DB` | `31432` | docker-compose.yml ports | Database |
| `PORT_EXTRA` | `31379` | docker-compose.yml ports | Redis / queue / etc. |
| `HOST_WORKSPACE_PATH` | *(empty)* | docker-compose.yml volumes | HOST path for cross-namespace bind mounts (see `.claude/rules/devcontainer-patterns.md`) |

## Ports

| Variable | Default | `devcontainer.json` | Use |
|----------|--------:|---------------------|-----|
| `PORT_APP`   | 31000 | `forwardPorts[0]` | App, dev server |
| `PORT_API`   | 31080 | `forwardPorts[1]` | API |
| `PORT_DB`    | 31432 | `forwardPorts[2]` | Database |
| `PORT_EXTRA` | 31379 | `forwardPorts[3]` | Redis, queue |

When changing ports, update both `.env` and `forwardPorts` and rebuild.

## Runtime isolation

```
AI agent infrastructure (kept separate from project code):
  Claude Code → native binary (~/.local/bin/claude, auto-updated)
  Codex CLI   → npm global (~/.npm-global/bin/codex)
  Node.js     → Node 22 LTS for Codex CLI infrastructure
  Python      → system python3 + uv (general development)

Project code (when PROJECT_NODE_VERSION is set):
  Node.js → project-node (nvm alias, .nvmrc auto-applied)
  Python  → install via deadsnakes / pyenv / etc.
  Other   → Go, Rust, etc. installed freely.

Aliases:
  project-node → Node ${PROJECT_NODE_VERSION}
  default      → project-node
```

## DevContainer lifecycle

```
postCreateCommand (setup-env.sh — once)
  [1/3] permissions (Docker socket, git filemode, command history)
  [2/3] SSH (when host keys are bound)
  [3/3] Claude CLI version sync

postStartCommand (every start)
  git config core.filemode false
```

## Persistent volumes

| Volume | Mount | Purpose |
|--------|-------|---------|
| `claude-config-${devcontainerId}` | `~/.claude` | Claude Code auth (survives rebuild) |
| `codex-config-${devcontainerId}` | `~/.codex`  | Codex CLI auth (survives rebuild) |
| `command-history-${devcontainerId}` | `/commandhistory` | Shell history |

## Pre-installed tools

| Category | Tools |
|----------|-------|
| Shell | tmux, zsh, fzf, jq, tree, htop |
| Search | ripgrep (rg), fd-find (fd) |
| Git | git, git-lfs, gh |
| Container | docker CLI, docker compose v2, devcontainer CLI |
| Editor | vim, nano |
| Network | curl, wget, openssh-client |
| Claude | Claude Code CLI |
| Codex | Codex CLI (npm global), AGENTS.md, `.codex/` hooks |
| Node.js | Node 22 LTS, npm, npx |
| Python | python3, uv, ruff, pytest, mypy |

### Tool versioning policy: rolling, not pinned

The template intentionally pulls latest releases at build/run time:
- **Claude Code**: `curl https://claude.ai/install.sh | bash` (latest at build).
- **Codex CLI**: `npm install -g @openai/codex` (latest published, unpinned).
- **`claude update`**: runs on every container start (`setup-env.sh` step 3),
  unless `SKIP_CLAUDE_UPDATE=1` is set.

Same git commit may produce different installed versions on different days.
For reproducible images, pin: replace the Claude installer URL with a tagged
release, set `npm install -g @openai/codex@<version>`, and export
`SKIP_CLAUDE_UPDATE=1` in `devcontainer.json`.

## Agent system

### Sub-agents (Claude side, 2)

| Agent | Purpose | Invocation |
|-------|---------|------------|
| evaluator | Context-isolated quality evaluation | After changes; within `/refine` |
| wip-manager | Multi-session task tracker | When task spans sessions |

### Hooks

Claude (6): `session-start.sh`, `pre-commit-gate.sh`, `pre-push-gate.sh`, `refinement-gate.sh`, `meta-evolution-guard.sh` (Meta-Evolution wrapper enforcement; self-disabling when CLAUDE.md has no `§6`), `sub-project-edit-guard.sh` (Edit/Write block on registered sub-projects; self-disabling when no `§6`).

Codex (4): `session-start.sh`, `pre-commit-gate.sh`, `pre-push-gate.sh`, `refinement-gate.sh` (Codex CLI does not expose Edit/Write matchers).

### Skills (4 + karpathy-guidelines)

| Skill | Description |
|-------|-------------|
| /refine | Autonomous iterative refinement loop |
| /status | Workspace status |
| /verify | Pre-commit verification |
| /wiki | Structured knowledge wiki (init, ingest, query, lint) |
| karpathy-guidelines | Reference handle for the Karpathy 4 rules (`SKILL.md` + `EXAMPLES.md`) |

## Polyagent parity

```bash
bash scripts/sync-agents-mirror.sh         # .claude/ → .agents/ overlay
bash scripts/sync-agents-mirror.sh --dry   # diff only
```

`.claude/` is ground truth; `.agents/` is generated. `cp -a` overlay preserves dest-only files (project-local extensions are not clobbered).

### Codex sandbox bypass (DevContainer only)

Codex CLI sandboxes commands with [bubblewrap](https://github.com/containers/bubblewrap), which requires unprivileged user namespaces. Docker kernel policy blocks namespace creation, so every shell call from the sandbox fails (`bwrap: No permissions to create a new namespace`).

| Environment | Sandbox works | Recommended |
|-------------|:-------------:|-------------|
| Host Linux directly | ✓ | (default) `--sandbox workspace-write` |
| **DevContainer** | ✗ (kernel) | `--dangerously-bypass-approvals-and-sandbox` |

The DevContainer is itself the isolation boundary. Outside containers, keep the default sandbox.

### Codex commands

```bash
codex login --device-auth                                                # auth (volume-persistent)
codex login status                                                       # auth status
codex                                                                    # interactive (loads AGENTS.md)
codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "<prompt>"
codex --version
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Build fails | `docker compose build --no-cache` |
| Claude re-auth needed | check named volume: `docker volume ls \| grep claude-config` |
| Codex re-auth needed | check named volume: `docker volume ls \| grep codex-config` |
| Wrong Node version | `nvm use` or create `.nvmrc` |
| Port collision | edit `.env` `PORT_*` + `devcontainer.json` `forwardPorts`, rebuild |
| Hook test fails | `export CLAUDE_PROJECT_DIR=/workspaces` (Codex: `CODEX_PROJECT_DIR`) |
| Git permission errors | `git config core.filemode false` |
| `.agents/` drift | `bash scripts/sync-agents-mirror.sh` |

---

*Last updated: 2026-04-30*
