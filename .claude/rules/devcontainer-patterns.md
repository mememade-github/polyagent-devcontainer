# DevContainer Development Patterns

> Prevents Docker-in-Docker (DinD) anti-pattern and defines container validation protocol.

## Core Principle

DevContainers run on the **HOST** Docker daemon. From inside a container, the host daemon is
accessible via mounted `docker.sock` — this is NOT DinD.

**Prerequisites**: `docker.sock` mounted + user in `docker` group + `devcontainer` CLI installed

| Allowed (via docker.sock) | Not Possible |
|--------------------------|-------------|
| `docker compose build` | VS Code extension testing |
| `devcontainer up/exec` | GUI-dependent features |
| `docker images`, `docker inspect` | — |
| Volume mounts via `--project-directory` | — |

## Volume Mount Path Translation

When running `docker compose up` inside a DevContainer, bind mount volume source paths are
resolved by the **Docker daemon**, not the container. The DevContainer and Docker daemon access
the same physical files through different paths, so path translation is required.

### Filesystem Namespace Isolation

```
DevContainer (9p mount):
  /workspaces/<project>/... → files visible ✓

Docker daemon (WSL2 host mount):
  /run/desktop/mnt/host/c/.../<project>/... → files visible ✓

Cross-access impossible:
  DevContainer → /run/desktop/  = does not exist (not mounted)
  Docker daemon → /workspaces/  = empty WSL2 native directory (different filesystem)
```

This issue does not occur in server deployments where scripts and Docker daemon run on the
same OS. It is a structural constraint specific to DevContainers.

### Resolution: HOST_WORKSPACE_PATH + --project-directory

Set `HOST_WORKSPACE_PATH` to the HOST filesystem path that the Docker daemon uses, then use
`docker compose --project-directory <HOST_PATH>` to translate volume mount paths.

Verify the correct value:

```bash
docker inspect <container_name> \
  --format '{{range .Mounts}}{{if eq .Destination "/workspaces"}}{{.Source}}{{end}}{{end}}'
```

See each project's `REFERENCE.md` for specific configuration instructions.

### build vs volume mount Behavior

| Command | File Access Method | DevContainer Path Behavior |
|---------|-------------------|---------------------------|
| `docker compose build` | Docker CLI reads files and sends to daemon | DevContainer path OK |
| `docker compose up` (bind mount) | Docker daemon mounts directly from HOST | **HOST path required** |

## 4-Phase Testing Protocol

### Phase 1: Docker Build (inside container)

```bash
cd /path/to/.devcontainer
docker compose build --no-cache 2>&1
docker images | grep <image-name>
docker inspect <image-name>:latest --format '{{.Config.User}}'
```

### Phase 2: Config Validation (inside container)

| Item | Method |
|------|--------|
| settings.json | `jq . < .claude/settings.json` |
| devcontainer.json | JSONC parsing |
| docker-compose.yml | `docker compose config` |
| hooks/*.sh | `bash -n <file>` + shebang check |
| agents/*.md | YAML frontmatter parsing |
| skills/*/SKILL.md | Required fields exist |

### Phase 3: Functional Tests (inside container)

```bash
bash .claude/hooks/test-hooks.sh
for f in .claude/hooks/*.sh; do bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"; done
```

### Phase 4: HOST Integration

**Option A: CLI Automated** (preferred — `devcontainer` CLI + docker.sock)

```bash
cd /path/to/project
# 1. Build and start container on HOST Docker
devcontainer up --workspace-folder .

# 2. Verify Claude + MCP inside the container
devcontainer exec --workspace-folder . claude --version
devcontainer exec --workspace-folder . claude mcp list

# 3. Verify system tools
devcontainer exec --workspace-folder . node --version
devcontainer exec --workspace-folder . npx --version

# 4. Cleanup
docker compose -p <compose-project-name> down
```

**Option B: Manual** (VS Code GUI — for extension/UI testing)

1. "Reopen in Container" from HOST VS Code
2. Verify `/workspaces/` mount, postCreateCommand, extensions
3. Verify `claude --version` and MCP servers (`/mcp`)

## DinD Detection

| Symptom | Likely Cause |
|---------|-------------|
| Empty `/workspaces/` | Mount path missing in nested container |
| "Cannot find workspace" | Path resolution failure |
| Missing VS Code extensions | VS Code not connected (Option B only) |

## Agent Guidance

1. Run Phase 1-3 first, report PASS/FAIL per item
2. Run Phase 4 Option A (CLI) for automated verification
3. Fall back to Option B (manual handoff) only for VS Code extension testing:
   > "Phase 1-4A complete. VS Code extensions require manual verification: Reopen in Container from HOST."
