# Polyagent DevContainer

DevContainer template for running multiple AI coding agents (Claude Code · Codex CLI · Antigravity CLI) in parity on the same project. The container is workspace-scoped, not a security sandbox — see [REFERENCE.md § Privilege boundary](REFERENCE.md#privilege-boundary) for the docker.sock / docker-group implications.

Single ground truth (`.claude/`) + per-vendor mirror (`.agents/rules`, `.agents/skills`, `.codex/`). Antigravity reuses the same mirror plus a small native layer in `.agents/` (a hook adapter that runs the Claude hooks, and a rule-folder registration). Adding a new vendor reuses the mirror pattern instead of rewriting governance.

Behavioral foundation: [Karpathy 4-rule](https://github.com/forrestchang/andrej-karpathy-skills) (Think Before Coding · Simplicity First · Surgical Changes · Goal-Driven Execution) auto-loaded for Claude (`@import` in `CLAUDE.md`); for Codex, `AGENTS.md` instructs an explicit `Read` of the rule files under `.agents/rules/` at session start; Antigravity loads them automatically through their `trigger: always_on` frontmatter.

## Requirements

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker Engine with Compose v2 (both paths)
- [VS Code](https://code.visualstudio.com/) + [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (path A only)

## Quick start

```bash
git clone https://github.com/mememade-github/polyagent-devcontainer.git my-project
cd my-project
cp .devcontainer/.env.example .devcontainer/.env
```

In `.devcontainer/.env`, `COMPOSE_PROJECT_NAME` is the project and volume prefix
(for example, `my-project`), and `CONTAINER_NAME` is the container name used by
`docker exec` below (for example, `my-project-dev`). Both identifiers are unique
per instance; the other settings are listed in [Configuration](REFERENCE.md#configuration-devcontainerenv).

**A: VS Code.** Attach does not apply `devcontainer.json`.

```bash
code .
# VS Code: Ctrl+Shift+P → "Dev Containers: Reopen in Container"
# First build ~3-5 min.
```

**B: Docker Compose.** Run from the repository root:

```bash
docker compose --env-file .devcontainer/.env -f .devcontainer/docker-compose.yml build
docker compose --env-file .devcontainer/.env -f .devcontainer/docker-compose.yml up -d
docker exec -it my-project-dev bash
```

For settings, operations, and differences between A and B, see [DevContainer lifecycle](REFERENCE.md#devcontainer-lifecycle).

### Agents and first login

Run an agent inside the container:

```bash
claude --dangerously-skip-permissions
codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "<prompt>"
agy
```

On first run, `claude` prompts interactive login and Codex needs
`codex login --device-auth` once. For `agy`, sign in at the printed Google URL
and follow the terminal prompts. Gemini 4 Argon requires a paid Google AI Pro
or Ultra plan, excluding free trials. All three credentials persist in named volumes.

Codex compatibility and project trust details are covered in [Codex sandbox bypass](REFERENCE.md#codex-sandbox-bypass-devcontainer-only).

## What's included

| Component | Count | Notes |
|-----------|------:|-------|
| AI agents | 3 | Claude Code · Codex CLI · Antigravity CLI (`agy`) |
| Governance roles | 2 | evaluator, wip-manager (Claude agents; Codex skill/subprocess mirrors; Antigravity built-in `self` subagents) |
| Hooks | 4 / 4 / 4 | session-start, pre-commit-gate, pre-push-gate, refinement-gate (Antigravity runs the Claude hooks through `.agents/hooks/claude-hooks-adapter.sh`) |
| Skills | 5 | /refine, /status, /verify, karpathy-guidelines, typesafe-ai |
| Tools | 20+ | ripgrep, fd, fzf, jq, tmux, gh, docker CLI, uv |

For the optional TypeSafe API key, see [REFERENCE.md §TypeSafe (optional)](REFERENCE.md#typesafe-optional).

## Customizing for your project

After the first container start, ask any of the agents:

```
Initialize this project. Ask me about: project name, languages/frameworks,
required services, server info, test framework, CI/CD,
commit message language. Then update CLAUDE.md/AGENTS.md/PROJECT.md/
REFERENCE.md, .devcontainer/.env, and
.claude/rules/project/. Verify with .devcontainer/verify-template.sh.
```

During initialization, leave `.claude/settings.json`, `.codex/hooks.json`, `.agents/hooks.json`, `.agents/hooks/`, `.devcontainer/Dockerfile`, and agent frontmatter unchanged because they define hook, build, and role contracts. Keep the `trigger: always_on` frontmatter on the rule files and give every new rule in `.claude/rules/project/` the same three lines, or Antigravity silently skips that file; customize the six update targets named before “Verify with” in the prompt above, while `.devcontainer/verify-template.sh` is the verification command rather than an update target.

## Vendor parity sync

```bash
bash scripts/sync-agents-mirror.sh         # .claude/ → .agents/rules, .agents/skills (prunes deleted-source orphans)
bash scripts/sync-agents-mirror.sh --dry   # diff only
```

`.claude/` is the ground truth. `.agents/rules/` and `.agents/skills/` are
generated with matching content and file modes; do not edit them by hand. The
other `.agents/` files (`hooks.json`, `hooks/`, `rules.json`) are hand-maintained
Antigravity configuration that the sync never touches.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Build fails | `docker compose -f .devcontainer/docker-compose.yml build --no-cache` |
| Files invisible or container is unhealthy | A: use Reopen in Container. B: set `HOST_WORKSPACE_PATH` to a project path accessible to the Docker daemon. See [Configuration](REFERENCE.md#configuration-devcontainerenv). |
| Reopen menu missing | Install the Dev Containers extension |
| Claude re-auth needed | `docker volume ls \| grep claude-config` |
| Codex re-auth needed | `docker volume ls \| grep codex-config` |
| Antigravity re-auth needed or a rule is ignored | See [REFERENCE troubleshooting](REFERENCE.md#troubleshooting) |
| `.agents/` drift | `bash scripts/sync-agents-mirror.sh` |

## License & history

Licensed under the MIT License. See [LICENSE](LICENSE).

Renamed from `claude-devcontainer` on 2026-04-30 when Codex parity was generalized into the Polyagent model. Git history is preserved.
