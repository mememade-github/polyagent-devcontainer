# REFERENCE.md — Commands & Procedures

> Actionable commands, configuration, and troubleshooting.
> For domain context, see [PROJECT.md](PROJECT.md).

## Privilege boundary

This template is **not** a security sandbox. The container mounts the
host's `/var/run/docker.sock` and the in-container user is in the
`docker` group, which Docker's official documentation describes as
equivalent to host root: anyone inside the container can launch
privileged containers, mount the host filesystem, and execute as root
on the host. This is required so that commands like
`docker compose build` and `devcontainer up` from inside the container
target the *host* daemon (not Docker-in-Docker).

Treat the container as a workspace boundary, not a trust boundary. Do
not run untrusted code or untrusted MCP tools inside it expecting
isolation from the host. If host-level isolation matters, run the
DevContainer inside a VM or on a dedicated machine.

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
| `HOST_WORKSPACE_PATH` | *(empty)* | docker-compose.yml volumes | HOST path for cross-namespace bind mounts (see `.claude/rules/devcontainer-patterns.md`) |

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
Dockerfile ENTRYPOINT → entrypoint.sh (every container start)
  └── setup-env.sh (idempotent; postCreateCommand runs it once on first build)
        [1/5] Permissions   — Docker socket ownership, git core.filemode,
                              git safe.directory, command-history setup
        [2/5] SSH            — chmod 700/600/644 on ~/.ssh keys (optional)
        [3/5] Claude CLI     — `claude update` (skip with SKIP_CLAUDE_UPDATE=1)
        [4/5] Codex CLI      — `npm i -g --prefix ~/.npm-global @openai/codex@latest`
                              (skip with SKIP_CODEX_UPDATE=1)
        [5/5] Codex config   — copy /workspaces/.codex/config.toml into ~/.codex/

postStartCommand (every start, devcontainer.json)
  git config core.filemode false
```

Both `docker compose up` and VS Code "Reopen in Container" route through
`entrypoint.sh`, so the 5 steps run regardless of how the container was started.

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
- **Codex CLI**: `npm install -g @openai/codex` into `~/.npm-global`
  (latest published, unpinned). The image and startup script set npm's global
  prefix to the same directory so `codex doctor` and runtime updates agree.
- **`claude update`**: runs on every container start (`setup-env.sh` step 3),
  unless `SKIP_CLAUDE_UPDATE=1` is set.
- **Codex update**: every container start re-runs `npm install -g --prefix
  ~/.npm-global @openai/codex@latest` (`setup-env.sh` step 4), unless
  `SKIP_CODEX_UPDATE=1` is set. Codex's built-in `codex update` is **not** used:
  it targets the root-owned default npm prefix (`/usr/lib/node_modules`) and
  fails as the unprivileged `vscode` user.

Same git commit may produce different installed versions on different days.
For reproducible images, pin: replace the Claude installer URL with a tagged
release, set `npm install -g @openai/codex@<version>`, and export
`SKIP_CLAUDE_UPDATE=1` and `SKIP_CODEX_UPDATE=1` in `devcontainer.json`.

## Agent system

### Sub-agents (Claude side, 2)

| Agent | Purpose | Invocation |
|-------|---------|------------|
| evaluator | Context-isolated quality evaluation | After changes; within `/refine` |
| wip-manager | Multi-session task tracker | When task spans sessions |

### Hooks

Claude (4): `session-start.sh`, `pre-commit-gate.sh`, `pre-push-gate.sh`, `refinement-gate.sh`.

Codex (4): `session-start.sh`, `pre-commit-gate.sh`, `pre-push-gate.sh`, `refinement-gate.sh` (Codex CLI does not expose Edit/Write matchers).

### Skills (4)

| Skill | Description |
|-------|-------------|
| /refine | Autonomous iterative refinement loop |
| /status | Workspace status |
| /verify | Pre-commit verification |
| karpathy-guidelines | Reference handle for the Karpathy 4 rules (`SKILL.md` + `EXAMPLES.md`) |

## Polyagent parity

```bash
bash scripts/sync-agents-mirror.sh         # .claude/ → .agents/ generated mirror
bash scripts/sync-agents-mirror.sh --dry   # diff only
```

`.claude/` is ground truth; `.agents/` is generated. The sync copies content (`cp -R`) and **prunes** `.agents/` entries whose `.claude/` source was deleted (deletion propagation), so the mirror tracks deletions, not just additions.

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
| Hook test fails | `export CLAUDE_PROJECT_DIR=/workspaces` (Codex: `CODEX_PROJECT_DIR`) |
| Git permission errors | `git config core.filemode false` |
| `.agents/` drift | `bash scripts/sync-agents-mirror.sh` |

---

*Last updated: 2026-04-30*
