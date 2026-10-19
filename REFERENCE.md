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

Template build and startup configuration lives in `.devcontainer/.env`. The tracked file is
`.devcontainer/.env.example`; copy it to `.devcontainer/.env` to customize
(compose defaults apply when `.env` is absent).

| Variable | Default | Used by | Purpose |
|----------|---------|---------|---------|
| `COMPOSE_PROJECT_NAME` | `polyagent-devcontainer` | docker-compose.yml | Docker namespace |
| `CONTAINER_NAME` | `polyagent-dev` | docker-compose.yml | Container name |
| `IMAGE_NAME` | `polyagent-devcontainer` | docker-compose.yml | Image name |
| `IMAGE_TAG` | `latest` | docker-compose.yml | Image tag |
| `TZ` | `UTC` | docker-compose.yml | Timezone |
| `TYPESAFE_API_KEY` | *(empty)* | `.devcontainer/.env` | Optional TypeSafe key; store only in `.devcontainer/.env`; load it in the command before a request |
| `DNS_PRIMARY` | `8.8.8.8` | docker-compose.yml dns | First DNS resolver; set to your network's DNS server if internal hostnames must resolve |
| `PROJECT_NODE_VERSION` | *(empty)* | Dockerfile ARG | Project Node.js version (empty = not installed) |
| `HOST_WORKSPACE_PATH` | *(empty)* | docker-compose.yml volumes | HOST path for cross-namespace bind mounts (see `.claude/rules/devcontainer-patterns.md`) |

## Runtime isolation

```
AI agent infrastructure (kept separate from project code):
  Claude Code → native binary (~/.local/bin/claude, auto-updated)
  Codex CLI   → npm global (~/.npm-global/bin/codex)
  Antigravity → native binary (~/.local/bin/agy, self-updating)
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
        [1/6] Permissions   — Docker socket ownership, git core.filemode,
                              git safe.directory, command-history setup
        [2/6] SSH            — chmod 700/600/644 on ~/.ssh keys (optional)
        [3/6] Claude CLI     — `claude update` (skip with SKIP_CLAUDE_UPDATE=1)
        [4/6] Codex CLI      — reconcile PATH-first launcher, then refresh the
                              real ~/.npm-global/bin/codex with npm --prefix
                              (skip with SKIP_CODEX_UPDATE=1)
        [5/6] Codex config   — validate project config; preserve user config without copying
        [6/6] Antigravity    — `agy update`; a failure prints a WARN and the
                              output tail and keeps the installed binary
                              (skip with SKIP_AGY_UPDATE=1)

postStartCommand (every start, devcontainer.json)
  git config core.filemode false
```

Both `docker compose up` and VS Code "Reopen in Container" route through
`entrypoint.sh`, so the 6 steps run regardless of how the container was started.
The container healthcheck requires all three agent CLIs (`--version` only: no
login, no network call) and a recognizable
`/workspaces` project marker (`.git`, `AGENTS.md`, `CLAUDE.md`, `README.md`, or
`.devcontainer/`). A container with an empty or mis-mounted workspace stays
`unhealthy` instead of reporting a false green status.

## Persistent volumes

| Volume | Mount | Purpose |
|--------|-------|---------|
| `claude-config` | `~/.claude` | Claude Code auth (survives rebuild) |
| `codex-config` | `~/.codex`  | Codex CLI auth (survives rebuild) |
| `gemini-config` | `~/.gemini` | Antigravity login token, settings, conversations, plugins (survives rebuild) |
| `antigravity-secrets` | `~/.config/antigravity` | Antigravity plugin and MCP secrets (`plugin-secrets.json`) |
| `command-history` | `/commandhistory` | Shell history |

> Named volumes are prefixed by `COMPOSE_PROJECT_NAME` and shared identically by
> both entry paths (`docker compose up` and VS Code "Reopen in Container").
> Change `COMPOSE_PROJECT_NAME` in `.devcontainer/.env` to isolate volumes per instance.
> The image creates the mount points as `vscode`, so new volumes are `vscode`-owned.

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
| Antigravity | Antigravity CLI (`agy`), AGENTS.md, `.agents/hooks.json` adapter, `.agents/rules.json` |
| Node.js | Node 22 LTS, npm, npx |
| Python | python3, uv, ruff, pytest, mypy |

### Tool versioning policy: rolling, not pinned

The template intentionally pulls latest releases at build/run time:
- **Claude Code**: `curl https://claude.ai/install.sh | bash` (latest at build).
- **Codex CLI**: `npm install -g --prefix ~/.npm-global @openai/codex`
  into `~/.npm-global` (latest published, unpinned). The image installs a
  PATH-first `codex` launcher (`/usr/local/bin/codex-launcher`) that updates
  through the same explicit prefix, then re-execs the real
  `~/.npm-global/bin/codex` binary. The template does not persistently mutate
  npm's global prefix.
- **Antigravity CLI**: `curl -fsSL https://antigravity.google/cli/install.sh | bash`
  (latest at build; the installer checks the manifest sha512).
- **`claude update`**: runs on every container start (`setup-env.sh` step 3),
  unless `SKIP_CLAUDE_UPDATE=1` is set.
- **Codex update**: every container start reconciles the launcher symlinks and
  delegates refresh to `/usr/local/bin/codex-launcher --update-only`, which
  updates the real binary with `npm install -g --prefix ~/.npm-global
  @openai/codex@latest`, unless `SKIP_CODEX_UPDATE=1` is set. The same launcher
  performs the preflight before every new `codex` process. Codex's built-in
  `codex update` is **not** used: it targets the root-owned default npm prefix
  (`/usr/lib/node_modules`) and fails as the unprivileged `vscode` user.
- **Antigravity updates**: `agy update` runs on every container start
  (`setup-env.sh` step 6), unless `SKIP_AGY_UPDATE=1` is set. The CLI also
  updates in the background during sessions. The healthcheck uses
  `agy --version`, which does not start the updater.

Same git commit may produce different installed versions on different days.
For reproducible images, pin the rolling sources: replace the Claude installer
URL with a tagged release, set `npm install -g @openai/codex@<version>`, and
`npm install -g @devcontainers/cli@<version>` (the Antigravity installer has
no version option), and pin the apt packages, the pip
tools (`ruff`/`pytest`/`mypy`), and Node to an
exact version (`setup_22.x` already fixes only the major), and pin the base
image to a digest or fully-qualified version tag — `ubuntu-22.04` is a rolling
alias that gets rebuilt. The `docker compose` plugin and `uv`
are already version-pinned. The tracked compose file passes only `TZ`.
To skip startup refresh, pass `SKIP_CLAUDE_UPDATE=1`, `SKIP_CODEX_UPDATE=1`, or
`SKIP_AGY_UPDATE=1` before startup through compose `environment:` in a local override.
`exec -e` affects only the new process and cannot change an earlier startup step.

## Agent system

### Governance roles (2)

| Agent | Purpose | Invocation |
|-------|---------|------------|
| evaluator | Context-isolated quality evaluation | After changes; within `/refine` |
| wip-manager | Multi-session task tracker | When task spans sessions |

Current Codex supports in-process subagents and project
`.codex/agents/*.toml`. The template mirrors these Claude role bodies as Codex
skills for portable discovery; evaluator runs still use a fresh
`codex exec --ephemeral` process to carry the exact Contract/diff-only input
boundary in interactive and non-interactive flows.
`.agents/skills/` is Codex's native repo skills root: Codex skill discovery
consumes the mirror directly, so do not delete it as a mere convention. Mirrored
`SKILL.md` frontmatter (`tools`, `model`, `maxTurns`, `color`) is Claude-host
metadata that Codex ignores.
Antigravity discovers seven mirrored skills, including the two governance roles.
`/refine` invokes a fresh built-in `self` for each role; Step 0b of the
[refine skill](.agents/skills/refine/SKILL.md#step-0b-fresh-role-isolation) specifies
role text and permitted evidence. Children retain rules and hooks, exclude the
parent conversation, and need no `.agents/agents/*.md` definition file.

### Hooks

Claude (4): `session-start.sh`, `pre-commit-gate.sh`, `pre-push-gate.sh`, `refinement-gate.sh`.

Codex (4): `session-start.sh`, `pre-commit-gate.sh`, `pre-push-gate.sh`,
`refinement-gate.sh`. Codex matchers support `Bash`, `apply_patch`, `Edit`, and
`Write`; these commit/push gates intentionally inspect `Bash` commands.

Antigravity runs the adapter after workspace trust. `.agents/hooks.json` registers
SessionStart, PreToolUse (`run_command`), and Stop, calling
`.agents/hooks/claude-hooks-adapter.sh` from `.agents/`. The unmodified Claude
hooks receive `CLAUDE_PROJECT_DIR` set to the git root of the command's `Cwd`:

| agy event | Claude hook | agy answer |
|-----------|-------------|------------|
| PreToolUse `run_command` | `pre-commit-gate.sh`, then `pre-push-gate.sh` | exit 2 → `{"decision":"deny","reason":<stderr>}`; otherwise `{"decision":"ask"}` |
| Stop | `refinement-gate.sh`, only for `terminationReason` `NO_TOOL_CALL` | `block` → `{"decision":"continue","reason":…}`; otherwise `{"decision":"allow"}` |
| SessionStart | `session-start.sh` (`{"source":"startup"}`) | `additionalContext` → `injectSteps[0].systemMessage.systemMessage` |

`ask` hands the call to agy's own permission settings; agy treats an empty
`{}` as a block, so the adapter never emits one. The adapter never runs the
command itself and always exits 0 with valid JSON; that is the response format,
and the Claude hooks keep their fail-open policy. Antigravity shares the Claude
markers and refine state in `.claude/`. One worktree runs one refine loop: while
a Claude loop is active, an agy stop in the same repository takes part in the
gate's alternation (block, allow, block, …) like a second Claude session.
The adapter intercepts `run_command`, not file-editing tools. A hook `deny`
still blocks under `--dangerously-skip-permissions`.

All gates are advisory policy tripwires (see §Privilege boundary), not a
security sandbox. A gate blocks (exit 2) only on a positive match — a
`--no-verify`/`-n` commit bypass, a credential pattern in raw command text,
credential-bearing stored git config on a push, a force
push, or a missing/stale verification marker. On any parse failure, internal
error, or unrecognized command shape the gate exits 0 (fail-open). The
verification marker is per-branch and considered fresh for 24 hours from its
mtime; `scripts/meta/completion-checker.sh` writes it (see §Verification).
These gates do not scan staged file contents.

Codex loads `.codex/config.toml` directly after the project is trusted. Project
command hooks also require review in `/hooks`, and changed definitions are
skipped until reviewed again. Use `--dangerously-bypass-hook-trust` only in
automation that independently vets the hook source.

### Skills (5)

| Skill | Description |
|-------|-------------|
| /refine | Autonomous iterative refinement loop |
| /status | Workspace status |
| /verify | Pre-commit verification |
| karpathy-guidelines | Reference handle for the Karpathy 4 rules (`SKILL.md`) |
| typesafe-ai | TypeSafe workflow skill from [typesafe-ai/skills](https://github.com/typesafe-ai/skills), commit `65a39f393687675ce170e6094757de20370365b9`; MIT; vendored with one local delta: an offline snapshot of the HTTP API reference at `reference/api.md` and the SKILL.md sentence that names it; generated mirror for Codex |

### TypeSafe (optional)

Store `TYPESAFE_API_KEY` only in `.devcontainer/.env` (gitignored).
Load it in the command before a request, for example `set -a; . .devcontainer/.env; set +a`.
The `typesafe-ai` skill reads the live TypeSafe documentation
for API and SDK usage, so this file carries no request shapes or SDK commands.

## Verification

Two tiers, split by cost:

| Tier | Command | When |
|------|---------|------|
| Fast checks | `bash scripts/meta/completion-checker.sh` | Before each commit — writes the per-branch marker the pre-commit gate reads |
| Acceptance suite | `bash .devcontainer/verify-template.sh` | On demand and in CI, not per commit — full template integrity, including docker-backed checks |

`completion-checker.sh` is environment-independent: it works in fresh clones,
CI, and temp checkouts, and does not require docker or a canonical checkout
path. The acceptance suite is the deep oracle; run it after structural changes
to the template (hooks, mirror, devcontainer) and before releases.

## Polyagent parity

```bash
bash scripts/sync-agents-mirror.sh         # .claude/ → .agents/ generated mirror
bash scripts/sync-agents-mirror.sh --dry   # diff only
```

`.claude/` is ground truth; `.agents/rules/` and `.agents/skills/` are
generated. The sync copies content and file modes, and **prunes** entries in
those two trees whose `.claude/` source was deleted, so the mirror tracks
metadata and deletions, not just additions. Other `.agents/` entries
(`hooks.json`, `hooks/`, `rules.json`) are Antigravity's hand-maintained native
files; the sync neither compares nor removes them.

### Codex sandbox bypass (DevContainer only)

Codex CLI sandboxes commands with [bubblewrap](https://github.com/containers/bubblewrap), which requires unprivileged user namespaces. Docker kernel policy blocks namespace creation, so every shell call from the sandbox fails (`bwrap: No permissions to create a new namespace`).

| Environment | Sandbox works | Recommended |
|-------------|:-------------:|-------------|
| Host Linux directly | ✓ | (default) `--sandbox workspace-write` |
| **DevContainer** | ✗ (kernel) | `--dangerously-bypass-approvals-and-sandbox` |

The bypass makes the DevContainer the command-execution compatibility boundary,
not a security or trust boundary. The mounted Docker socket grants host-level
power; outside containers, keep the default sandbox.

### Codex commands

See the [official Codex CLI reference](https://developers.openai.com/codex/cli/reference).

## Antigravity CLI (agy)

See the [official CLI reference](https://antigravity.google/docs/cli/reference/)
and [troubleshooting](https://antigravity.google/docs/cli/troubleshooting/).

### Authentication

Without D-Bus, account tokens are stored under `~/.gemini/antigravity-cli/`,
inside the `gemini-config` volume.

### Container prerequisites

| Feature | Requirement | Template configuration |
|---------|-------------|------------------------|
| Terminal sandbox (`--sandbox`) | Host permission for kernel namespaces | Off by default in this template |
| Browser | Google Chrome | Not installed |
| Voice | Microphone | No microphone device configured |
| Remote control | Eligible account and paired external device | Supplied separately by the user |

### Registering deeper rule folders

Antigravity reads only direct children of `.agents/rules/` and drops a rule file
without `trigger` frontmatter. `.agents/rules.json` registers
`.agents/rules/project`. To add a nested folder such as
`.claude/rules/project/backend/`:

1. Start each rule file with `---`, `trigger: always_on`, `---`.
2. Run `bash scripts/sync-agents-mirror.sh`.
3. Add `{ "path": ".agents/rules/project/backend" }` to the `entries` array in
   `.agents/rules.json`.
4. Run `bash scripts/meta/completion-checker.sh` (it validates the JSON).

`agy plugin validate` accepts a missing or wrong `trigger`, so it is not
evidence that a rule loads.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Build fails | `docker compose build --no-cache` |
| Claude re-auth needed | check named volume: `docker volume ls \| grep claude-config` |
| Codex re-auth needed | check named volume: `docker volume ls \| grep codex-config` |
| Antigravity re-auth needed | check named volumes: `docker volume ls \| grep -E 'gemini-config\|antigravity-secrets'` |
| Antigravity files are root-owned after using an older image | `sudo chown -R vscode:vscode ~/.gemini ~/.config/antigravity` |
| Antigravity ignores a rule | See [Registering deeper rule folders](#registering-deeper-rule-folders) |
| `/status` or `/refine` stops with exit 2 under agy | `ANTIGRAVITY_AGENT=1` is missing from the command environment; set `AGENT_VENDOR=antigravity` |
| Codex says `Run npm install -g @openai/codex to update` | restart the current Codex process; new sessions enter through the launcher and re-exec the latest real binary |
| Strict config rejects `ask_for_approval` | replace it with `approval_policy` in `~/.codex/config.toml`; project config is not copied there |
| Wrong Node version | `nvm use` or create `.nvmrc` |
| Hook test fails | `export CLAUDE_PROJECT_DIR=/workspaces` (Codex: `CODEX_PROJECT_DIR`) |
| Git permission errors | `git config core.filemode false` |
| `.agents/` drift | `bash scripts/sync-agents-mirror.sh` |

---

*Last updated: 2026-10-17*
