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

All user-tunable values live in `.devcontainer/.env`. The tracked file is
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
> The image creates every mount point as `vscode`, so new volumes are
> `vscode`-owned. A volume created by an older image without that directory
> may be `root`-owned; fix it once with
> `sudo chown -R vscode:vscode ~/.gemini ~/.config/antigravity`.

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
- **`agy update`**: runs on every container start (`setup-env.sh` step 6),
  unless `SKIP_AGY_UPDATE=1` is set. agy also self-updates in the background
  during sessions; see [§Antigravity CLI](#antigravity-cli-agy).

Same git commit may produce different installed versions on different days.
For reproducible images, pin the rolling sources: replace the Claude installer
URL with a tagged release, set `npm install -g @openai/codex@<version>`, and
`npm install -g @devcontainers/cli@<version>` (the Antigravity installer has
no version option), and pin the apt packages, the pip
tools (`ruff`/`pytest`/`mypy`), and Node to an
exact version (`setup_22.x` already fixes only the major), and pin the base
image to a digest or fully-qualified version tag — `ubuntu-22.04` is a rolling
alias that gets rebuilt. The `docker compose` plugin and `uv`
are already version-pinned. To disable the per-start refresh, set
`SKIP_CLAUDE_UPDATE=1`, `SKIP_CODEX_UPDATE=1`, and `SKIP_AGY_UPDATE=1` in the
compose `environment:` block (values may come from `.env`) — `docker compose up`
does not read `devcontainer.json`, which covers only the VS Code "Reopen in
Container" path. The tracked compose file passes only `TZ`; see
[§Antigravity CLI](#antigravity-cli-agy) for when each route takes effect.

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
Antigravity discovers the same `.agents/skills/` (seven skills, including the
two mirrored roles). `/refine` runs Audit, Modify, and Evaluate each in a fresh
built-in `self` subagent (`invoke_subagent`, `TypeName: self`): Audit and Modify
get the skill's Step 3 and Step 4 text, Evaluate gets the evaluator role body,
and each child receives only that instruction and the permitted evidence. The
child keeps the repository rules and hooks and never sees the parent
conversation. No `.agents/agents/*.md` definition file is used.

### Hooks

Claude (4): `session-start.sh`, `pre-commit-gate.sh`, `pre-push-gate.sh`, `refinement-gate.sh`.

Codex (4): `session-start.sh`, `pre-commit-gate.sh`, `pre-push-gate.sh`,
`refinement-gate.sh`. Codex matchers support `Bash`, `apply_patch`, `Edit`, and
`Write`; these commit/push gates intentionally inspect `Bash` commands.

Antigravity (adapter): `.agents/hooks.json` registers SessionStart, PreToolUse
(`run_command`), and Stop, each calling `.agents/hooks/claude-hooks-adapter.sh`
from `.agents/` (agy's hook working directory). The adapter feeds the
unmodified Claude hooks with `CLAUDE_PROJECT_DIR` set to the git root of the
command's `Cwd`:

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

```bash
codex login --device-auth                                                # auth (volume-persistent)
codex login status                                                       # auth status
codex                                                                    # interactive (loads AGENTS.md)
codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "<prompt>"
codex exec --dangerously-bypass-hook-trust "<vetted-automation-prompt>"    # vetted hooks only
codex --version
```

## Antigravity CLI (agy)

Antigravity CLI is Google's terminal agent (the successor of Gemini CLI). The
image installs it with the official installer. Official documentation:
<https://antigravity.google/docs/cli/reference/>.

### Authentication

| Method | Setup | Notes |
|--------|-------|-------|
| Google account OAuth (default) | run `agy` (or `/login`) | In a container the CLI prints a URL; sign in from any browser and paste the code the browser shows. Without a D-Bus session the token is stored in a file under `~/.gemini/antigravity-cli/`, which the `gemini-config` volume keeps. `/logout` signs out. Free, Pro, and Ultra plans |
| Business (Gemini Enterprise) | Sign in → Business → Google Cloud or Advanced WIF | Needs a license, project, and location; `--project` selects the project |
| Gemini API key | `"modelProvider": "gemini"` in `~/.gemini/antigravity-cli/settings.json` **and** `GEMINI_API_KEY` in the process environment | agy does not read `.env` files; export the key in the shell that runs agy. `/logout` has no effect; remove `modelProvider` to return to account login (removing only the key breaks runs). Billed through AI Studio, not the subscription |
| Application Default Credentials | `gcloud auth application-default login` + `AGY_ADC_AUTH=true` | `gcloud` is not in the image, and its credentials in `~/.config/gcloud/` are not on a template volume. Remote control is unavailable with ADC |

Gemini 4 Argon is available on Google AI Pro (not the trial) and AI Ultra; Free
and Plus plans get Gemini 3.8 Flash. `agy models` lists what the signed-in
account can use. Consumer plans do not support wrapping `agy` inside another
agent or automating account switching.

### Updates and update variables

- Start: `setup-env.sh` step 6 runs `agy update` on every container start. A
  failure prints `WARN: agy update failed; continuing with <version>` and the
  last 20 lines of output; the installed binary keeps working.
  `SKIP_AGY_UPDATE=1` skips the step.
- Background: during sessions agy updates itself (lock and 15-minute check
  marker in `~/.gemini/antigravity-cli/updater/`).
  `AGY_CLI_DISABLE_AUTO_UPDATE=true` turns this off; an explicit `agy update`
  still runs. `agy --version`, which the healthcheck uses, does not start the
  updater.

The tracked compose file passes only `TZ`, so both variables use the same
routes as `SKIP_CLAUDE_UPDATE` and `SKIP_CODEX_UPDATE`. When a route takes
effect matters:

| Route | Takes effect | Use for |
|-------|--------------|---------|
| Compose `environment:` (a local, untracked override such as `docker-compose.override.yml`) | every start of that container, `docker compose up` and VS Code | `SKIP_AGY_UPDATE`, container-wide `AGY_CLI_DISABLE_AUTO_UPDATE` |
| `devcontainer.json` `containerEnv` | every start, VS Code "Reopen in Container" path only | same |
| `docker run -e` / `docker compose run -e` | the new container it creates | same |
| `docker compose exec -e VAR=… polyagent-devcontainer agy` | that one exec process only; the start step has already run | per-session `AGY_CLI_DISABLE_AUTO_UPDATE=true` |

A variable passed with `exec -e` cannot skip the start step. Setting it in a
shell (`export AGY_CLI_DISABLE_AUTO_UPDATE=true`) affects only agy processes
started from that shell.

### Paths

| Path | Content |
|------|---------|
| `~/.local/bin/agy` | binary (the installer also adds a PATH block to `.bashrc` and `.profile`) |
| `~/.gemini/antigravity-cli/` | `settings.json`, `keybindings.json`, `conversations/`, `plugins/`, `updater/`, `worktrees/`, logs |
| `~/.gemini/config/` | global configuration shared by Antigravity products: `hooks.json`, `mcp_config.json`, `rules/`, `skills/`, `agents/`, `AGENTS.md` |
| `~/.config/antigravity/plugin-secrets.json` | plugin and MCP secrets |
| `AGENTS.md`, `.agents/` | workspace configuration, read from the current directory up to the repository root |

### Headless

`agy -p "<prompt>"` runs one turn. `--output-format text|json|stream-json`,
`--input-format stream-json`, `--json-schema <schema>`, and `--print-timeout`
control I/O. Without credentials it exits 1 with `authentication required` on
stderr (JSON `status: ERROR`); a pipe left open can wait for a login code. A
tool that needs approval is soft-denied in headless runs: exit 0, a hint on
stderr, and `denied_actions` in JSON output. Exit 0 or `status: SUCCESS` does
therefore not prove that a command ran.

### Permissions and sandbox

Modes: `default`, `accept-edits`, `plan`, `auto` (`--mode`, `Shift+Tab`
interactively). Rules: `permissions.allow` / `deny` / `ask` in `settings.json`,
`/permissions`. `--dangerously-skip-permissions` (or `toolPermission:
always-proceed`) auto-approves tools but still asks for plan approval. A hook
`deny` blocks even under auto-approval. The terminal sandbox (`--sandbox`,
`enableTerminalSandbox`, nsjail) is off by default and needs kernel namespaces,
which Docker blocks for the same reason as Codex's bubblewrap.

### Optional features

Test result values: **Confirmed** · **Condition not met (unverified)** ·
**Out of scope (App only / not CLI)** · **Failed: environment limit**.
"Pending test" cells are filled after the release test run.

| Feature | CLI support | Needs in this container | Test result |
|---------|-------------|-------------------------|-------------|
| Interactive TUI, color scheme, workspace trust | Yes | — | Pending test |
| Headless (`-p`, output/input formats, `--json-schema`, `--print-timeout`) | Yes | login or API key | Pending test |
| Modes (`--mode`, `Shift+Tab`) | Yes (`auto` on Linux/macOS) | — | Pending test |
| Permission rules, `--dangerously-skip-permissions` | Yes | — | Pending test |
| Terminal sandbox (`--sandbox`) | Yes, off by default | kernel namespaces | Pending test |
| Rules (`AGENTS.md`, `.agents/rules`, `rules.json`, global rules) | Yes | — | Pending test |
| Skills (`.agents/skills`, `/skills`, `skills.json`) | Yes | — | Pending test |
| Hooks (six events, `/hooks`) | Yes | workspace trust | Pending test |
| Subagents (`.agents/agents`, `--agent`, `invoke_subagent`, workspace inherit/branch/share) | Yes | — | Pending test |
| Teamwork (`/teamwork-preview`) | Paid plans | eligible account | Pending test |
| MCP (`mcp_config.json`, `/mcp`, `agy mcp`) | Yes | the MCP server itself | Pending test |
| Plugins (`/plugin`, `agy plugin …`, `agy plugin import gemini`) | Yes | marketplace access | Pending test |
| Artifact review (`/artifact`, `Ctrl+R`) | Yes | — | Pending test |
| Browser (`/browser`, Chrome DevTools MCP) | Yes | Google Chrome (not in the image) | Pending test |
| Goal (`/goal`) | Yes | — | Pending test |
| Schedule (`/schedule`, one-time and cron) | Yes | — | Pending test |
| Sidecars | App only (not CLI) | — | Out of scope (App only / not CLI) |
| `/plan` `/boost` `/learn` `/codesearch` `/context` `/btw` `/diff` | Yes (`/boost`: Pro/Ultra) | — | Pending test |
| Conversations (`/resume`, `-c`, `--conversation`, `/fork`, `/rewind`, `/rename`, `/compact`, `/clear`, `/export`, `/tasks`, `/open`) | Yes | — | Pending test |
| Models, effort, `/usage`, `/credits` | Yes | login | Pending test |
| Status line, title, key bindings, Vim mode, `/config` | Yes | — | Pending test |
| Voice (`/voice`, `agy mic-serve`) | Yes (not enterprise accounts) | a microphone (none in the container) | Pending test |
| Remote control (`--remote-control`, `agy remote-control`) | Yes (not with ADC) | account feature, a paired external device | Pending test |
| Extra directories, projects (`--add-dir`, `--project`, `--new-project`) | Yes | — | Pending test |
| Login and logout | Yes | a browser on any machine | Pending test |
| API key, Business/WIF, ADC sign-in | Yes | see §Authentication | Pending test |
| Updates (`agy update`, background updater) | Yes | network | Pending test |
| `agy install` options, `agy changelog`, `agy --version` | Yes | — | Pending test |
| IDE extensions, tab completion, side panel, app-only browser settings, Python SDK | Not CLI | — | Out of scope (App only / not CLI) |

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

### Antigravity commands

```bash
agy                                     # interactive (loads AGENTS.md and .agents/)
agy -p "<prompt>"                        # headless, one turn
agy -p --output-format json "<prompt>"  # machine-readable result
agy --mode plan                         # start in plan mode
agy --dangerously-skip-permissions      # auto-approve tools; hook deny still blocks
agy models                              # models for the signed-in account
agy update                              # explicit update
agy --version
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Build fails | `docker compose build --no-cache` |
| Claude re-auth needed | check named volume: `docker volume ls \| grep claude-config` |
| Codex re-auth needed | check named volume: `docker volume ls \| grep codex-config` |
| Antigravity re-auth needed | check named volumes: `docker volume ls \| grep -E 'gemini-config\|antigravity-secrets'` |
| agy prints D-Bus or keyring warnings | without a D-Bus session agy stores the token in a file, so no action is needed; `secret keyring is locked` means a keyring service is reachable but locked: unlock it (see the official CLI troubleshooting page) |
| `another background updater process is already active (update.lock)` | wait for the running updater, or set `AGY_CLI_DISABLE_AUTO_UPDATE=true` for the session |
| Antigravity ignores a rule | add `trigger: always_on` frontmatter; register a nested folder (§Registering deeper rule folders) |
| `/status` or `/refine` stops with exit 2 under agy | `ANTIGRAVITY_AGENT=1` is missing from the command environment; set `AGENT_VENDOR=antigravity` |
| Codex says `Run npm install -g @openai/codex to update` | restart the current Codex process; new sessions enter through the launcher and re-exec the latest real binary |
| Strict config rejects `ask_for_approval` | replace it with `approval_policy` in `~/.codex/config.toml`; project config is not copied there |
| Wrong Node version | `nvm use` or create `.nvmrc` |
| Hook test fails | `export CLAUDE_PROJECT_DIR=/workspaces` (Codex: `CODEX_PROJECT_DIR`) |
| Git permission errors | `git config core.filemode false` |
| `.agents/` drift | `bash scripts/sync-agents-mirror.sh` |

---

*Last updated: 2026-10-17*
