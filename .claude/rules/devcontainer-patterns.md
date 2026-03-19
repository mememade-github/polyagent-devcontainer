# DevContainer Development Patterns

> Prevents Docker-in-Docker (DinD) anti-pattern and defines container validation protocol.

## Core Principle

DevContainers run on the **HOST** machine via VS Code. They cannot be started from inside another container.
- DinD fails because mount paths reference HOST filesystem, not nested container paths
- `docker.sock` sharing does not translate container-internal paths

## External Docker Testing (docker.sock)

From inside a DevContainer, the **host Docker daemon** is accessible via mounted socket.
This is NOT DinD — commands execute on the host daemon directly.

**Prerequisites**: `docker.sock` mounted + user in `docker` group

| Allowed | Not Possible |
|---------|-------------|
| `docker compose build` | Open another DevContainer |
| `docker images`, `docker inspect` | Test volume mounts (HOST paths) |
| `docker rmi` (caution: host images) | Run postCreateCommand |

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

### Phase 4: HOST Integration (user-only, cannot be automated)

1. "Reopen in Container" from HOST VS Code
2. Verify `/workspaces/` mount, postCreateCommand, extensions
3. Verify `claude --version` and MCP servers (`/mcp`)

## DinD Detection

| Symptom | Likely Cause |
|---------|-------------|
| Empty `/workspaces/` | Mount path missing in nested container |
| "Cannot find workspace" | Path resolution failure |
| Missing VS Code extensions | VS Code not connected |

## Agent Guidance

1. Run Phase 1-3 first, report PASS/FAIL per item
2. Delegate Phase 4 to user with handoff template:
   > "Phase 1-3 complete. From HOST VS Code: Reopen in Container, verify `claude --version` and `/mcp`."
