# Polyagent DevContainer

DevContainer template for running multiple AI coding agents (Claude Code · Codex CLI · Antigravity CLI) in parity on the same project. The container is workspace-scoped, not a security sandbox — see [REFERENCE.md § Privilege boundary](REFERENCE.md#privilege-boundary) for the docker.sock / docker-group implications.

Single ground truth (`.claude/`) + per-vendor mirror (`.agents/rules`, `.agents/skills`, `.codex/`). Antigravity reuses the same mirror plus a small native layer in `.agents/` (a hook adapter that runs the Claude hooks, and a rule-folder registration). Adding a new vendor reuses the mirror pattern instead of rewriting governance.

Behavioral foundation: [Karpathy 4-rule](https://github.com/forrestchang/andrej-karpathy-skills) (Think Before Coding · Simplicity First · Surgical Changes · Goal-Driven Execution) auto-loaded for Claude (`@import` in `CLAUDE.md`); for Codex, `AGENTS.md` instructs an explicit `Read` of the rule files under `.agents/rules/` at session start; Antigravity loads them automatically through their `trigger: always_on` frontmatter.

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
agy
```

On first run, `claude` prompts interactive login and Codex needs
`codex login --device-auth` once. For `agy`, sign in at the printed Google URL
and follow the terminal prompts. Gemini 4 Argon requires a paid Google AI Pro
or Ultra plan, excluding free trials. All three credentials persist in named volumes.

The `--dangerously-bypass-approvals-and-sandbox` flag is needed because Codex's
bubblewrap sandbox cannot create user namespaces inside Docker. It is only a
compatibility workaround: because `docker.sock` is mounted,
the DevContainer is not a security or trust boundary. On first interactive
Codex use, trust the project and review project hooks with `/hooks`; changed
hooks require review again. See [REFERENCE.md](REFERENCE.md) for details.

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

Upgrading an existing project: [UPGRADING.md](UPGRADING.md).

## Vendor parity sync

```bash
bash scripts/sync-agents-mirror.sh         # .claude/ → .agents/rules, .agents/skills (prunes deleted-source orphans)
bash scripts/sync-agents-mirror.sh --dry   # diff only
```

`.claude/` is the ground truth. `.agents/rules/` and `.agents/skills/` are
generated with matching content and file modes; do not edit them by hand. The
other `.agents/` files (`hooks.json`, `hooks/`, `rules.json`) are hand-maintained
Antigravity configuration that the sync never touches.

## VS Code: Reopen in Container vs. Attach

Always use **Reopen in Container** (`Ctrl+Shift+P`). Attach connects to a running container without applying `devcontainer.json` (workspace path, extensions, port forwarding), which breaks the template.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Build fails | `docker compose build --no-cache` |
| Files invisible or container is unhealthy | Use Reopen in Container, not Attach; for headless `docker compose`, set `HOST_WORKSPACE_PATH` to the host filesystem path |
| Reopen menu missing | Install the Dev Containers extension |
| Claude re-auth needed | `docker volume ls \| grep claude-config` |
| Codex re-auth needed | `docker volume ls \| grep codex-config` |
| Antigravity re-auth needed or a rule is ignored | See [REFERENCE troubleshooting](REFERENCE.md#troubleshooting) |
| `.agents/` drift | `bash scripts/sync-agents-mirror.sh` |

## License & history

Licensed under the MIT License. See [LICENSE](LICENSE).

Renamed from `claude-devcontainer` on 2026-04-30 when Codex parity was generalized into the Polyagent model. Git history is preserved.
