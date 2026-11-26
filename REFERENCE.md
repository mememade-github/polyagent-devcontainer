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

Template build and startup configuration lives in `.devcontainer/.env`, a
copy of `.devcontainer/.env.example`; [Quick start](README.md#quick-start)
covers initial setup. The Compose commands in README and this file pass
`--env-file .devcontainer/.env` and fail with `Couldn't find env file` when it
is absent. `COMPOSE_PROJECT_NAME` is set only in that file: a Compose command
run without it names the project, and the volume prefix, after the
`.devcontainer` directory (`devcontainer`). For every variable below
except `TYPESAFE_API_KEY`, a variable of the same name in the shell that runs
`docker compose` takes precedence over the file's value.

The second column is the value in effect with an unedited copy of
`.env.example`; where that file leaves a variable empty, the fallback in
`docker-compose.yml` applies (`DNS_PRIMARY`).

| Variable | With `.env.example` | Used by | Purpose |
|----------|---------|---------|---------|
| `COMPOSE_PROJECT_NAME` | `polyagent-devcontainer` | docker-compose.yml | Docker namespace |
| `CONTAINER_NAME` | `polyagent-dev` | docker-compose.yml | Container name |
| `IMAGE_NAME` | `polyagent-devcontainer` | docker-compose.yml | Image name |
| `IMAGE_TAG` | `latest` | docker-compose.yml | Image tag |
| `TZ` | `UTC` | docker-compose.yml | Timezone |
| `TYPESAFE_API_KEY` | *(empty)* | `.devcontainer/.env` | Optional TypeSafe key; store only in `.devcontainer/.env`; load it in the command before a request |
| `DNS_PRIMARY` | `8.8.8.8` | docker-compose.yml dns | First DNS resolver; set to your network's DNS server if internal hostnames must resolve |
| `PROJECT_NODE_VERSION` | *(empty)* | Dockerfile ARG | Project Node.js version (empty = not installed) |
| `HOST_WORKSPACE_PATH` | *(empty)* | docker-compose.yml volumes | Empty binds the parent of `.devcontainer` to `/workspaces`. If that path does not identify the same project for the Docker daemon, set a project path accessible to the daemon. This can occur inside another container, with a remote daemon, or on a host that needs path translation (see [Docker from inside the container](#docker-from-inside-the-container)). On Windows, if the daemon expects `/c/...` paths, `C:\Users\you\my-project` becomes `/c/Users/you/my-project`. |

## Docker from inside the container

The container uses the host's Docker daemon through the mounted
`/var/run/docker.sock`; this is not Docker-in-Docker (see
[Privilege boundary](#privilege-boundary)). It needs the mounted socket, the
in-container user in the `docker` group, and, for `devcontainer` commands, the
`devcontainer` CLI.

| Works through the socket | Not possible in the container |
|--------------------------|-------------------------------|
| `docker compose build`, `docker images`, `docker inspect` | VS Code extension testing |
| `devcontainer up`, `devcontainer exec` | GUI-dependent features |
| Compose bind mounts whose source path the daemon can see (below) | |

Compose resolves the two kinds of path in different places:

| Command | Who reads the path | Path inside this container |
|---------|--------------------|----------------------------|
| `docker compose build` | The Docker CLI reads the build context and sends it to the daemon | Works |
| `docker compose up` with a bind mount | The daemon mounts the source from its own filesystem | Works only if the daemon sees the same path |

The daemon may not see this container's `/workspaces/...` paths. For example,
with Docker Desktop on WSL2 the container's 9p-mounted `/workspaces` and the
daemon's host paths are different filesystem namespaces. In that case set
`HOST_WORKSPACE_PATH` to the project's path as the daemon sees it, and keep the
usual command form from the repository root:

```bash
HOST_WORKSPACE_PATH=<daemon-visible project path> \
  docker compose --env-file .devcontainer/.env -f .devcontainer/docker-compose.yml up -d
```

`HOST_WORKSPACE_PATH` changes only the `/workspaces` bind source; the build
context stays `.devcontainer/` and the CLI reads it from this container. Do not
add `--project-directory <host path>`: Compose then resolves the build context
against that host path as well, which the CLI inside the container cannot read.
Running the same command with `config` instead of `up -d` prints both resolved
paths without starting anything.

The daemon-visible source of a running container's workspace is:

```bash
docker inspect <container_name> \
  --format '{{range .Mounts}}{{if eq .Destination "/workspaces"}}{{.Source}}{{end}}{{end}}'
```

## Runtime layout

```
AI agent infrastructure:
  Claude Code → native binary (~/.local/bin/claude, auto-updated)
  Codex CLI   → npm global (~/.npm-global/bin/codex), a `#!/usr/bin/env node`
                script run by the first `node` on PATH
  Antigravity → native binary (~/.local/bin/agy, self-updating)
  Node.js     → Node 22 LTS at /usr/bin/node
  Python      → system python3 + uv (general development)

Project code (when PROJECT_NODE_VERSION is set):
  Node.js → project-node (nvm alias; interactive bash runs `nvm use`,
            which applies .nvmrc when present)
  Python  → install via deadsnakes / pyenv / etc.
  Other   → Go, Rust, etc. installed freely.

Aliases:
  project-node → Node ${PROJECT_NODE_VERSION}
  default      → project-node
```

With `PROJECT_NODE_VERSION` set, interactive bash (`vscode`'s shell and the
VS Code terminal's default profile) puts the project Node first on PATH, so
`node`, `npm`, and Codex with its launcher's npm update run on the project
Node there, and so does any shell or script started from it, because it
inherits that PATH. Processes started without that PATH keep Node 22: the
startup setup, and a non-interactive bash or a zsh started directly by
`docker exec`. Without `PROJECT_NODE_VERSION`, nvm is not installed and
`node` is Node 22.

## DevContainer lifecycle

```
Dockerfile ENTRYPOINT → entrypoint.sh (every container start)
  └── setup-env.sh (path A's postCreateCommand runs it once more when the
        container is created; the two runs can overlap in time, and only the
        Codex update in step 4 is serialized, by the launcher's flock)
        [1/6] Permissions   — Docker socket ownership, git core.filemode,
                              git safe.directory '*' (for mounts whose owner
                              differs from the container user; it turns off
                              Git's ownership check in every directory, on
                              any filesystem), command-history setup
        [2/6] SSH            — chmod 700/600/644 on ~/.ssh keys (optional)
        [3/6] Claude CLI     — `claude update` (skip with SKIP_CLAUDE_UPDATE=1)
        [4/6] Codex CLI      — reconcile PATH-first launcher, then refresh the
                              real ~/.npm-global/bin/codex with npm --prefix
                              (skip with SKIP_CODEX_UPDATE=1)
        [5/6] Codex config   — warn when the project .codex/config.toml is missing
                              or it or ~/.codex/config.toml sets the obsolete
                              `ask_for_approval`; remove a ~/.codex/config.toml
                              symlink to the project config and warn on any
                              other symlink there; never copy project config
                              into ~/.codex
        [6/6] Antigravity    — `agy update` (skip with SKIP_AGY_UPDATE=1)

postStartCommand (every start, devcontainer.json)
  git config core.filemode false
```

Both `docker compose up` and VS Code "Reopen in Container" route through
`entrypoint.sh`, so the 6 steps run regardless of how the container was started.
The container healthcheck runs `--version` of the three agent CLIs (no login,
no network call; Codex with `SKIP_CODEX_UPDATE=1`) and checks that
`/workspaces` has at least one of `.git`, `AGENTS.md`, `CLAUDE.md`,
`README.md`, or `.devcontainer/`. It shows only that the CLIs run and that one
of those entries exists, not that the intended project is mounted.

A is VS Code "Reopen in Container". B uses Docker Compose and does not read
`devcontainer.json`. Both paths use the Dockerfile and Compose declarations below.

| Common value | Source |
|--------------|--------|
| `LANG=en_US.UTF-8`, `LC_ALL=en_US.UTF-8`, `DEVCONTAINER=true` | Dockerfile `ENV`; also declared in `devcontainer.json` `containerEnv` |
| `LANGUAGE=en_US:en` | Dockerfile `ENV` |
| `TZ=UTC` by default | Dockerfile `ENV`; Compose `environment` uses `${TZ:-UTC}` |
| `init: true` | Compose; also declared in `devcontainer.json` |
| `tty: true`, `stdin_open: true` | Compose |
| Working directory `/workspaces` | Dockerfile `WORKDIR`; also `devcontainer.json` `workspaceFolder` |
| Default user `vscode` | Dockerfile `ARG USERNAME=vscode` and `USER ${USERNAME}` |

A also has these declarations in `devcontainer.json`:

| Declaration | Source |
|-------------|--------|
| `waitFor: postCreateCommand` | `devcontainer.json` `waitFor` |
| `remoteUser: vscode`; the same default user as Dockerfile `USER` for B | `devcontainer.json` `remoteUser` |
| `updateRemoteUserUID: true` | `devcontainer.json` `updateRemoteUserUID` |
| `shutdownAction: stopCompose` | `devcontainer.json` `shutdownAction` |
| Host `~/.ssh` bind to `/home/vscode/.ssh` | `devcontainer.json` `mounts` |
| `NODE_OPTIONS=--max-old-space-size=4096` | `devcontainer.json` `containerEnv` |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY=0` | `devcontainer.json` `remoteEnv` |
| VS Code editor settings and four extensions | `devcontainer.json` `customizations.vscode` |

For configuration values and workspace path conditions, see
[Configuration](#configuration-devcontainerenv).

After configuration changes, A uses **Dev Containers: Rebuild Container**.
For B, run these commands from the repository root:

```bash
# Reapply configuration
docker compose --env-file .devcontainer/.env -f .devcontainer/docker-compose.yml up -d --build --force-recreate
# Check status and logs
docker compose --env-file .devcontainer/.env -f .devcontainer/docker-compose.yml ps
docker compose --env-file .devcontainer/.env -f .devcontainer/docker-compose.yml logs
# Stop
docker compose --env-file .devcontainer/.env -f .devcontainer/docker-compose.yml down
```

The connection step is in [Quick start, path B](README.md#quick-start).

Another B instance uses a separate env file, such as `.devcontainer/.env.project-b`,
with distinct values for the two identifiers described in [Quick start](README.md#quick-start).
Every Compose command selects that file with `--env-file`.

See [Persistent volumes](#persistent-volumes) for volume deletion behavior.

### Project setup file

After step 6, `setup-env.sh` sources `/usr/local/bin/setup-env.project.sh` if
that file exists. The template image does not contain it. A project that needs
its own startup steps keeps the script as `.devcontainer/setup-env.project.sh`,
adds `COPY setup-env.project.sh /usr/local/bin/` to the Dockerfile next to the
`setup-env.sh` copy, and rebuilds; edits to the file take effect only after a
rebuild.

The file then runs on every container start, at the end of `setup-env.sh` and
in the same Bash process, and on path A once more through `postCreateCommand`.
It runs under `setup-env.sh`'s `set -e`, an `exit` in it ends the setup, and
variables it exports do not reach the container's main process or later
shells.

When a command in the file exits non-zero, or the file has a syntax error,
`setup-env.sh` stops at that point. On a start through the entrypoint, the
container's command starts anyway after
`[entrypoint] WARN: setup-env.sh exited with error (non-fatal)`. The
entrypoint does not name the failed command; Bash names it only when it
reports the error itself, as for a command that is not found, so a command
that exits non-zero without a message, such as `false`, leaves no name. The healthcheck does not reflect
the failure.

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
> For multiple instances, see [DevContainer lifecycle](#devcontainer-lifecycle).
> The image creates the mount points as `vscode`, so new volumes are `vscode`-owned.

`down` preserves named volumes; `down -v` removes the three vendors' auth, secrets, and history volumes.

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
- **Antigravity CLI**: the official installer is downloaded to a file and run
  with Bash (latest at build; the installer checks the manifest sha512).
  Successful output loses only the pre-initialization glog prefix on `I`-level
  lines from the installer's final `agy install` step. A nonzero installer exit
  or any `E`/`W`/`F`-level prefix keeps the full raw log.
- **`claude update`**: runs on every container start (`setup-env.sh` step 3),
  unless `SKIP_CLAUDE_UPDATE=1` is set. Startup reports "already latest" only
  when `claude update` exits 0 and the version is unchanged; a failed update
  prints a WARN, the version still in use, and the tail of its output, and
  startup continues.
- **Codex update**: every container start reconciles the launcher symlinks and
  delegates refresh to `/usr/local/bin/codex-launcher --update-only`, which
  updates the real binary with `npm install -g --prefix ~/.npm-global
  @openai/codex@latest`, unless `SKIP_CODEX_UPDATE=1` is set. Its exit status
  tells startup what happened: 0 when Codex was reinstalled or already matched
  the latest version, 3 when the latest version could not be checked (npm
  missing, or the registry unreachable while `~/.npm-global/bin/codex` is
  executable) and the install was left as it was, 4 when
  the reinstall failed and a working previous install was restored, and 5 when
  the reinstall failed and no working `codex` is installed. Startup prints "already
  latest" only for 0 with an unchanged version; 3, 4, 5, and any other status
  print a WARN, and 4, 5, and other statuses add the tail of the npm output.
  Startup continues in every case. A failed reinstall moves the previous
  package aside first and restores it, and with the registry unreachable an
  existing executable is never removed; with the registry unreachable and no
  executable, the reinstall is still tried. The same launcher
  performs the preflight before every new `codex` process; there a failed
  reinstall prints one line on stderr, nothing is added to stdout, and a
  skipped or unchecked update is silent. Codex's built-in
  `codex update` is **not** used: it targets the root-owned default npm prefix
  (`/usr/lib/node_modules`) and fails as the unprivileged `vscode` user.
- **Antigravity updates**: `agy update` runs on every container start
  (`setup-env.sh` step 6), unless `SKIP_AGY_UPDATE=1` is set. A failed update
  prints a WARN and the tail of its output, keeps the installed binary, and
  startup continues. The CLI also
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

### Governance roles

| Agent | Purpose | Invocation |
|-------|---------|------------|
| evaluator | Context-isolated evaluation against authorized requirements using observed evidence | For meaningful changes |
| wip-manager | Multi-session task tracker | When task spans sessions |

Current Codex supports in-process subagents and project
`.codex/agents/*.toml`. The template mirrors these Claude role bodies as Codex
skills for portable discovery. Independent evaluation uses
`scripts/meta/run-isolated-role.sh evaluate` in a fresh `codex exec --ephemeral`
process supplied with the evaluator role body, authorized request, acceptance
conditions, actual diff, relevant repository facts, execution evidence, and
repository location in the prompt file, without the modifier's reasoning; the
helper appends the report destination (its `<output-file>` argument) to the prompt.
The report destination must be outside the repository or gitignored. The helper
clears any previous report before execution and fails on process failure or a
missing or empty report, without validating report content or format.
`.agents/skills/` is Codex's native repo skills root: Codex skill discovery
consumes the mirror directly, so do not delete it as a mere convention. Mirrored
`SKILL.md` frontmatter (`tools`, `model`, `maxTurns`, `color`) is Claude-host
metadata that Codex ignores.
Antigravity discovers the mirrored skills, including the evaluator and wip-manager roles.
Independent evaluation uses a fresh built-in `self` subagent supplied with the
evaluator role body and the same permitted inputs, excluding the parent
conversation and modifier's reasoning. Children retain repository rules and
hooks and need no `.agents/agents/*.md` definition file.

### Hooks

Claude: `session-start.sh`, `pre-push-gate.sh`.

Codex: `session-start.sh`, `pre-push-gate.sh`.
Codex matchers support `Bash`, `apply_patch`, `Edit`, and
`Write`; the push gate intentionally inspects `Bash` commands.

In `agy -p` sessions (agy 1.5.18) Antigravity ran the adapter whether or not
the project path was in `trustedWorkspaces`, with or without
`--dangerously-skip-permissions`. `.agents/hooks.json` registers
SessionStart and PreToolUse (`run_command`), calling
`.agents/hooks/claude-hooks-adapter.sh` from `.agents/`. The unmodified Claude
hooks receive `CLAUDE_PROJECT_DIR` set to the git root of the command's `Cwd`,
or to `Cwd` itself when it is not inside a repository:

| agy event | Claude hook | agy answer |
|-----------|-------------|------------|
| PreToolUse `run_command` | `pre-push-gate.sh` | exit 2 → `{"decision":"deny","reason":<stderr>}`; exit 0 → `{"decision":"ask"}`; any other exit (including a 124 timeout), or the adapter cannot run the gate (no `jq`, unreadable input, no hook file) → `{"decision":"ask"}` plus `pre-push gate: not checked: <cause>` on the adapter's stderr |
| SessionStart | `session-start.sh` (`{"source":"startup"}`) | `additionalContext`, followed by the contents of the repository root `PROJECT.md` when that file is non-empty and readable, → `injectSteps[0].systemMessage.systemMessage`; with neither, `{"injectSteps":[]}`. agy 1.5.18 kept about the first 48 KB of that message and replaced the rest with `<truncated N bytes>` |

`ask` hands the call to agy's own permission settings and is not an approval;
agy treats an empty
`{}` as a block, so the adapter never emits one for a registered event. The adapter never runs the
command itself and always exits 0 with valid JSON; that is the response format,
and the Claude hooks keep their fail-open policy. An unchecked `ask` carries no
`reason` field; the not-checked line is on the adapter's stderr only.
The adapter intercepts `run_command`, not file-editing tools. A hook `deny`
still blocks under `--dangerously-skip-permissions`.

The pre-push gate is an advisory policy tripwire (see §Privilege boundary),
not a security sandbox. It reads the command text and does not work out what
the shell will run. It blocks (exit 2) only on a match: a credential pattern
in the raw text of any command (including `git commit`, and a command that
only prints the text), or, when the text contains `git … push` outside quoted
spans, a literal credential in the `remote.*`, `url.*`, or `credential.*` git
config visible from the target repository. A push or credential hidden in a
variable, `eval`, an alias, or a script file is not seen. Each push, the text
between `;`, `|`, `&`, `(`, `)` and newlines that contains `git … push`, is
checked against a repository the gate infers from the text: that push's
`git -C <path>` (a path without spaces, quotes removed), else
`CLAUDE_PROJECT_DIR` (Codex: `CODEX_PROJECT_DIR`), else the current directory;
a preceding `cd` or a variable is not followed. When no repository is found
for a push, the gate reports `no git repository found at <path>` as not
checked. The gate does not block force pushes; approval for them is
the agent's duty in `AGENTS.md` and each vendor's permission settings.

Exit 0 means the gate did not block: it checked and found no match, or the
command has no `git … push` text. It is not an approval and not evidence that
the command is safe. When a step the result depends on fails (unreadable or
non-JSON input, no command in it, `jq` or `git` missing, a `sed`, `grep`, or
`git config` error, or no repository found for a push-shaped command), the gate
writes `pre-push gate: not checked: <cause>` to stderr and does not block. The Claude gate then exits 1, which Claude Code's hooks documentation
defines as a non-blocking error for PreToolUse. The Codex gate exits 0,
because the Codex hooks documentation defines only exit 0 and exit 2 for
PreToolUse, so on Codex an unchecked command has the same exit code as a
checked one. In the sessions observed (Claude Code 2.1.332, codex-cli 0.172.0,
agy 1.5.18) the line never reached the agent: Claude Code recorded it as a hook
error in its debug log and `stream-json` hook events, `codex exec` showed it
nowhere in its output, and Antigravity wrote it only to its own log file
(`--log-file`). To learn whether the gate checked a command, read the Claude Code or
Antigravity record; the observed `codex exec` output does not tell an
unchecked command from a checked one. No hook requires a verification step before a commit, and none
scans file contents.

Codex project trust and hook review are covered in
[Codex sandbox bypass](#codex-sandbox-bypass-devcontainer-only).

### Skills

| Skill | Description |
|-------|-------------|
| /status | Workspace status |
| /verify | Run the checks relevant to a change and report what ran, failed, or was skipped |
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
| Fast checks | `bash scripts/meta/completion-checker.sh` | For a change that touches what it checks; report which checks ran, failed, or were skipped |
| Template checks | `bash .devcontainer/verify-template.sh` | On demand, not per commit: tools present on the runner, the fast checks once, hook scripts and the Antigravity adapter on synthetic input |

`completion-checker.sh` needs no Docker, network, or canonical checkout path,
and it checks the checkout that contains the script (a worktree's copy checks
that worktree). It exits 1 when any check failed or could not read its input.
The Codex TOML parse needs python3 with `tomllib` (Python 3.11 or later). This
template's image uses Ubuntu 22.04's python3 3.10, so in the container that
check is `NOT CHECKED` and the run can still exit 0.

`verify-template.sh` exits 0 when every required check ran and passed, 1 when
a check failed, and 2 when nothing failed but a required check (the fast
checks or the hook cases) could not run. An optional tool missing from the
runner (Docker, the agent CLIs, node, python3, uv) does not change the exit
code; the fast checks and the hook cases need git and jq and fail or do not
run without them. Its hook cases show only the hook scripts' and the
adapter's output for synthetic input, not a real agent session's rule
loading, hook invocation, or blocking. It starts no container and creates no
Docker objects, so observe a normal container start and the healthcheck by
starting the container as README describes. Run it after changes to the
hooks, the adapter, or the fast checker.

## Polyagent parity

```bash
bash scripts/sync-agents-mirror.sh         # .claude/ → .agents/ generated mirror
bash scripts/sync-agents-mirror.sh --dry   # diff only
```

`.claude/` is the source of `.agents/rules/` and `.agents/skills/`, which are
generated. The sync copies content and file modes, and **prunes** entries in
those two trees whose `.claude/` source was deleted, so the mirror tracks
metadata and deletions, not just additions. Other `.agents/` entries
(`hooks.json`, `hooks/`, `rules.json`) are Antigravity's hand-maintained native
files; the sync neither compares, checks for symlinks, nor removes them.
Symlinks are rejected only in the two generated trees and their `.claude/`
sources. `--dry` exits 0 and prints the number of differences; a failed
`find`, `diff` or `stat` exits 1 before any result is printed or any file is
changed. The sync copies file content verbatim and does not judge what it
says; text that only one vendor can use must be made vendor-neutral in the
`.claude/` source.

### Codex sandbox bypass (DevContainer only)

Codex CLI sandboxes commands with [bubblewrap](https://github.com/containers/bubblewrap), which needs to create unprivileged user namespaces. Docker's [default seccomp profile](https://docs.docker.com/engine/security/seccomp/) denies `unshare` and namespace-creating `clone` calls to a container without `CAP_SYS_ADMIN`, and the template's Compose file sets no other profile and adds no capability. In a container started that way, `bwrap` fails with `bwrap: No permissions to create new namespace`, `unshare -U true` fails with `Operation not permitted`, and so every sandboxed Codex shell call fails. A daemon or container with another seccomp profile or added capabilities, or a host that restricts unprivileged user namespaces, can behave differently; the template does not detect which case applies.

| Environment | Sandbox works | Recommended |
|-------------|:-------------:|-------------|
| Linux host that allows unprivileged user namespaces | ✓ | (default) `--sandbox workspace-write` |
| **DevContainer** under Docker's default seccomp profile | ✗ (seccomp) | `--dangerously-bypass-approvals-and-sandbox` |

The bypass is a compatibility measure, not a security or trust boundary: Codex
commands then run unsandboxed with the container's access. The mounted Docker socket grants host-level
power; outside containers, keep the default sandbox.

In a project that is not trusted, Codex runs neither the project
`.codex/config.toml` nor the project hooks, and `--dangerously-bypass-hook-trust`
does not change that, even with `-c features.hooks=true`. The Codex hooks
documentation says project hooks load only from a trusted project, each hook
definition must also be reviewed and trusted in `/hooks`, new or changed
definitions are skipped until trusted, and `--dangerously-bypass-hook-trust`
skips only the stored hook trust for one invocation. That the hooks run once
the project and its hooks are trusted rests on that documentation; this
template's checks do not observe a Codex session.

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
| Terminal sandbox (`--sandbox`; also agent mode `auto`, the default, for commands agy runs without review) | Kernel namespaces, which Docker's default seccomp profile denies | Unavailable in this container: a sandboxed command fails with `Command failed to run: fork/exec /home/vscode/.local/bin/agy: operation not permitted` |
| Browser | Google Chrome | Not installed |
| Voice | Microphone | No microphone device configured |
| Remote control | Eligible account and paired external device | Supplied separately by the user |

Observed with agy 1.5.18 in `agy -p` sessions in this container: without
`--dangerously-skip-permissions`, `echo hi` went to the terminal sandbox and
failed with that error, in a trusted workspace and also with
`enableTerminalSandbox: false`; agy's documentation says the sandbox has no
effect where it is unavailable, but here the command failed instead. With
`--mode accept-edits` and no other setting, print mode denied the command
because it cannot prompt for the `command` permission. The command ran with
`--dangerously-skip-permissions`; with `"toolPermission": "always-proceed"`,
both in the default mode and with `--mode accept-edits`; and with
`--mode accept-edits` plus a matching `permissions.allow` rule such as
`command(echo hi)` (a rule without `--mode accept-edits` was not tried). The
settings were passed with `--settings`. Running agy commands outside the sandbox is a
compatibility measure for a container under Docker's default seccomp profile,
as for Codex (§Codex sandbox bypass): the commands then run with the
container's access, including the host Docker socket, so it is not a security
boundary.

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
| Build fails | From the repository root: `docker compose --env-file .devcontainer/.env -f .devcontainer/docker-compose.yml build --no-cache` |
| Claude re-auth needed | check named volume: `docker volume ls \| grep claude-config` |
| Codex re-auth needed | check named volume: `docker volume ls \| grep codex-config` |
| Antigravity re-auth needed | check named volumes: `docker volume ls \| grep -E 'gemini-config\|antigravity-secrets'` |
| Antigravity files are root-owned after using an older image | `sudo chown -R vscode:vscode ~/.gemini ~/.config/antigravity` |
| Antigravity ignores a rule | See [Registering deeper rule folders](#registering-deeper-rule-folders) |
| Codex says `Run npm install -g @openai/codex to update` | restart the current Codex process; new sessions enter through the launcher and re-exec the latest real binary |
| Strict config rejects `ask_for_approval` | replace it with `approval_policy` in `~/.codex/config.toml`; project config is not copied there |
| Wrong Node version | `nvm use` or create `.nvmrc` |
| Hook test fails | `export CLAUDE_PROJECT_DIR=/workspaces` (Codex: `CODEX_PROJECT_DIR`) |
| Git permission errors | `git config core.filemode false` |
| `.agents/` drift | `bash scripts/sync-agents-mirror.sh` |

## Shared status and verification

`scripts/git/git-status.sh` and `scripts/meta/completion-checker.sh` are maintained
here. Each receiving project decides when to adopt a new version and may keep its
own changes; contract changes are listed in [UPGRADING.md](UPGRADING.md). Status finds
nested Git repositories and worktrees, excluding `node_modules` and `.venv`.
Full and brief output show each repository’s branch, changes and upstream state.

The default tracked-content policy checks public-template identifiers. A private
project can replace it with its own extended regexes in
`scripts/meta/leak-patterns.txt`; optional untracked identifiers come from
`.env/leak-patterns`. Matches report filenames without copying secret values.
A pattern file that exists as a directory entry must be readable, and
`scripts/meta/leak-patterns.txt` must hold at least one pattern; otherwise the
scan fails. A `git grep` error, such as a pattern it rejects or a tracked file
it cannot read, also fails the scan; its messages are not printed because they
can quote the patterns. In the checker's `Leak patterns:` line, a local file it
cannot see is reported as `none`. Repositories that already own
`scripts/meta/verify-env-sync.sh` run it when their `.env` exists. Others have no
additional synchronization check.
