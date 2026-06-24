# Polyagent DevContainer

DevContainer template for running multiple AI coding agents (Claude Code · Codex CLI) in parity on the same project. The container is workspace-scoped, not a security sandbox — see [REFERENCE.md § Privilege boundary](REFERENCE.md#privilege-boundary) for the docker.sock / docker-group implications.

Single ground truth (`.claude/`) + per-vendor mirror (`.agents/`, `.codex/`). Adding a new vendor reuses the mirror pattern instead of rewriting governance.

Behavioral foundation: [Karpathy 4-rule](https://github.com/forrestchang/andrej-karpathy-skills) (Think Before Coding · Simplicity First · Surgical Changes · Goal-Driven Execution) auto-loaded for Claude (`@import` in `CLAUDE.md`) and inlined for Codex (`AGENTS.md`).

## Requirements

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [VS Code](https://code.visualstudio.com/) + [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

## Quick start

```bash
git clone https://github.com/mememade-github/polyagent-devcontainer.git my-project
cd my-project
code .
# VS Code: Ctrl+Shift+P → "Dev Containers: Reopen in Container"
# First build ~3-5 min.
```

Run an agent inside the container:

```bash
claude --dangerously-skip-permissions
codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "<prompt>"
```

The `--dangerously-bypass-approvals-and-sandbox` flag is needed because Codex's bubblewrap sandbox cannot create user namespaces inside Docker. The DevContainer is itself the isolation boundary. See [REFERENCE.md](REFERENCE.md) for details.

## What's included

| Component | Count | Notes |
|-----------|------:|-------|
| AI agents | 2 | Claude Code · Codex CLI |
| Sub-agents (Claude) | 2 | evaluator, wip-manager |
| Hooks | 4 / 4 | session-start, pre-commit-gate, pre-push-gate, refinement-gate |
| Skills | 5 | /refine, /status, /verify, /wiki, karpathy-guidelines |
| Tools | 20+ | ripgrep, fd, fzf, jq, tmux, gh, docker CLI, uv |

## Customizing for your project

After the first container start, ask either agent:

```
Initialize this project. Ask me about: project name, languages/frameworks,
required services, server info, test framework, CI/CD,
commit message language. Then update CLAUDE.md/AGENTS.md/PROJECT.md/
REFERENCE.md, .devcontainer/.env, and
.claude/rules/project/. Verify with .devcontainer/verify-template.sh.
```

Files **not** to edit by hand: `.claude/settings.json`, `.codex/hooks.json`, `.devcontainer/Dockerfile`, agent frontmatter.

## Vendor parity sync

```bash
bash scripts/sync-agents-mirror.sh         # .claude/ → .agents/ overlay (preserve-extras)
bash scripts/sync-agents-mirror.sh --dry   # diff only
```

`.claude/` is the ground truth. `.agents/` is generated; do not edit by hand.

## VS Code: Reopen in Container vs. Attach

Always use **Reopen in Container** (`Ctrl+Shift+P`). Attach connects to a running container without applying `devcontainer.json` (workspace path, extensions, port forwarding), which breaks the template.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Build fails | `docker compose build --no-cache` |
| Files invisible | Use Reopen in Container, not Attach |
| Reopen menu missing | Install the Dev Containers extension |
| Claude re-auth needed | `docker volume ls \| grep claude-config` |
| Codex re-auth needed | `docker volume ls \| grep codex-config` |
| `.agents/` drift | `bash scripts/sync-agents-mirror.sh` |

## License & history

Renamed from `claude-devcontainer` on 2026-04-30 when Codex parity was generalized into the Polyagent model. Git history is preserved.
