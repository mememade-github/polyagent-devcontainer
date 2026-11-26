# Polyagent DevContainer

DevContainer template for running multiple AI coding agents (Claude Code · Codex CLI · Antigravity CLI) in parity on the same project. The container is workspace-scoped, not a security sandbox — see [REFERENCE.md § Privilege boundary](REFERENCE.md#privilege-boundary) for the docker.sock / docker-group implications.

Shared duties live in one hand-maintained `AGENTS.md` that all three agents read. `.claude/` is the source of the rules, skills, and roles from which `scripts/sync-agents-mirror.sh` generates `.agents/rules` and `.agents/skills`. `.codex/` and a small native layer in `.agents/` (a hook adapter that runs the Claude hooks, and a rule-folder registration) are hand-maintained per vendor. Adding a new vendor reuses `AGENTS.md` and the generated copies instead of rewriting governance.

Behavioral foundation: four rules adapted from [andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (Think Before Coding · Simplicity First · Surgical Changes · Goal-Driven Execution), kept in `AGENTS.md` with the other shared duties. Claude reads `AGENTS.md` through `@AGENTS.md` in `CLAUDE.md`; Codex and Antigravity read `AGENTS.md` directly. Project rules in `.claude/rules/project/` load automatically for Claude, through `.agents/rules.json` for Antigravity, and for Codex because `AGENTS.md` tells it to read them at session start.

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
and follow the terminal prompts. Some models require a paid Google AI Pro or
Ultra plan and may not be included in free trials; after sign-in,
`agy models` lists the available models. All three credentials persist in named volumes.

Codex compatibility and project trust details are covered in [Codex sandbox bypass](REFERENCE.md#codex-sandbox-bypass-devcontainer-only).

## What's included

| Component | Contents |
|-----------|----------|
| AI agents | Claude Code · Codex CLI · Antigravity CLI (`agy`) |
| Governance roles | evaluator, wip-manager (Claude agents; Codex skill/subprocess mirrors; Antigravity built-in `self` subagents) |
| Hooks | session-start, pre-push-gate (Antigravity runs the Claude hooks through `.agents/hooks/claude-hooks-adapter.sh`) |
| Skills | /status, /verify, typesafe-ai |
| Tools | ripgrep, fd, fzf, jq, tmux, gh, docker CLI, uv, and the others in [Pre-installed tools](REFERENCE.md#pre-installed-tools) |

For the optional TypeSafe API key, see [REFERENCE.md §TypeSafe (optional)](REFERENCE.md#typesafe-optional).

## Customizing for your project

After the first container start, ask any of the agents:

```
Initialize this project. Ask me about: project name, languages/frameworks,
required services, server info, test framework, CI/CD,
commit message language. Then update CLAUDE.md/AGENTS.md/PROJECT.md/
REFERENCE.md, .devcontainer/.env, and
.claude/rules/project/. Then run .devcontainer/verify-template.sh and report
what it ran, what failed, and what did not run.
```

During initialization, leave `.claude/settings.json`, `.codex/hooks.json`, `.agents/hooks.json`, `.agents/hooks/`, `.devcontainer/Dockerfile`, and agent frontmatter unchanged because they define hook, build, and role contracts. Start every rule file in `.claude/rules/project/` with the three frontmatter lines `---`, `trigger: always_on`, `---`, or Antigravity silently skips that file; customize the six update targets named before “Then run” in the prompt above, while `.devcontainer/verify-template.sh` is a check command rather than an update target. It checks the hook scripts and the fast checks only, not the content you write during initialization.

## Vendor parity sync

After editing `.claude/`, run `bash scripts/sync-agents-mirror.sh` (`--dry` only
reports drift). See [Polyagent parity](REFERENCE.md#polyagent-parity).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Files invisible or container is unhealthy | A: use Reopen in Container. B: set `HOST_WORKSPACE_PATH` to a project path accessible to the Docker daemon. See [Configuration](REFERENCE.md#configuration-devcontainerenv). |
| Reopen menu missing | Install the Dev Containers extension |

For a failed build, re-authentication, an ignored Antigravity rule, `.agents/`
drift, and other symptoms, see [REFERENCE troubleshooting](REFERENCE.md#troubleshooting).

## License & history

Licensed under the MIT License. See [LICENSE](LICENSE).

Formerly `claude-devcontainer`; Git history is preserved.
