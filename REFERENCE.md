# REFERENCE.md — Commands & Procedures

> Actionable commands, configuration, and troubleshooting.
> For domain context (services, ports, infrastructure), see [PROJECT.md](PROJECT.md).

## Configuration (.env)

모든 사용자 설정은 `.devcontainer/.env` 단일 파일에서 관리합니다.

| 변수 | 기본값 | 참조 위치 | 용도 |
|------|--------|----------|------|
| `COMPOSE_PROJECT_NAME` | `claude-devcontainer` | docker-compose.yml | Docker 네임스페이스 |
| `CONTAINER_NAME` | `claude-dev` | docker-compose.yml | 컨테이너 이름 |
| `IMAGE_NAME` | `claude-devcontainer` | docker-compose.yml | 이미지 이름 |
| `IMAGE_TAG` | `latest` | docker-compose.yml | 이미지 태그 |
| `TZ` | `UTC` | docker-compose.yml | 타임존 (.env에서 오버라이드) |
| `PROJECT_NODE_VERSION` | *(empty)* | Dockerfile ARG | 프로젝트 Node.js (비워두면 미설치) |
| `PORT_APP` | `31000` | docker-compose.yml ports | 앱 포트 |
| `PORT_API` | `31080` | docker-compose.yml ports | API 포트 |
| `PORT_DB` | `31432` | docker-compose.yml ports | DB 포트 |
| `PORT_EXTRA` | `31379` | docker-compose.yml ports | 추가 포트 |
| `HOST_WORKSPACE_PATH` | *(empty)* | docker-compose.yml volumes | 워크스페이스 경로 |

## Ports

| 변수 | 기본값 | devcontainer.json | 용도 |
|------|--------|------------------|------|
| `PORT_APP` | 31000 | forwardPorts[0] | 앱, dev server |
| `PORT_API` | 31080 | forwardPorts[1] | API 서버 |
| `PORT_DB` | 31432 | forwardPorts[2] | 데이터베이스 |
| `PORT_EXTRA` | 31379 | forwardPorts[3] | Redis, queue 등 |

**주의**: `.env` 포트 변경 시 `devcontainer.json`의 `forwardPorts`도 함께 수정해야 합니다.

## Runtime Isolation

```
Claude Code 인프라 (프로젝트 코드와 격리):
  Claude Code → 네이티브 바이너리 (~/.local/bin/claude, 자동 업데이트)
  Node.js     → Context7 MCP 전용 (nvm, Node 22 LTS)
  Python      → Serena MCP 전용 (시스템 python3, uv, ~/work/serena)

프로젝트 코드 (PROJECT_NODE_VERSION 설정 시):
  Node.js  → project-node (nvm alias, .nvmrc 자동 적용, MCP 노드 위에 추가)
  Python   → 사용자 설치 (deadsnakes, pyenv 등)
  기타     → Go, Rust 등 자유 설치

project-node (alias) → Node ${PROJECT_NODE_VERSION} → 프로젝트용
default (alias)      → project-node
```

## DevContainer Lifecycle

```
postCreateCommand (setup-env.sh — 최초 1회)
  [1/4] 권한 설정 (Docker 소켓, git filemode, 명령 히스토리)
  [2/4] SSH 설정 (호스트 키 바인드 시)
  [3/4] MCP: Context7
  [4/4] MCP: Serena

postStartCommand (매 시작 시)
  git config core.filemode false
```

## Persistent Volumes

| Volume | Target | Purpose |
|--------|--------|---------|
| `claude-config-${devcontainerId}` | `~/.claude` | Claude Code 인증 (rebuild 유지) |
| `command-history-${devcontainerId}` | `/commandhistory` | Shell 히스토리 |

## Pre-installed Tools

| Category | Tools |
|----------|-------|
| **Shell** | tmux, zsh, fzf, jq, tree, htop |
| **Search** | ripgrep (rg), fd-find (fd) |
| **Git** | git, git-lfs, gh (GitHub CLI) |
| **Container** | docker CLI, docker compose v2, devcontainer CLI |
| **Editor** | vim, nano |
| **Network** | curl, wget, openssh-client |
| **Claude** | Claude Code CLI, Context7 MCP, Serena MCP |
| **Node.js** | node 22 LTS, npm, npx (Context7 MCP 인프라용) |
| **Python** | python3, uv, jedi (Serena 인프라용) |

## Agent System

### Agents (13)

| Agent | Purpose | Auto-trigger |
|-------|---------|-------------|
| code-reviewer | Code review with severity framework | After code changes |
| security-reviewer | Security vulnerability detection (OWASP) | After security-sensitive changes |
| database-reviewer | PostgreSQL optimization, schema design | After DB changes |
| build-error-resolver | Fix build/type errors with minimal diffs | On build failure |
| tdd-guide | TDD: RED→GREEN→REFACTOR cycle | On new feature |
| e2e-runner | E2E testing | On feature completion |
| doc-updater | Documentation specialist | On system changes |
| refactor-cleaner | Dead code cleanup | On maintenance |
| architect | Architecture design review | On design decisions |
| planner | Implementation planning | On complex tasks |
| debugger | Root cause analysis | On errors |
| environment-checker | Workspace health | On env issues |
| wip-manager | Multi-session tracking | When task spans sessions |

### Hooks (12)

| Hook | Event | Purpose |
|------|-------|---------|
| session-start.sh | SessionStart | Git status, WIP resume, Known Issues |
| block-destructive.sh | PreToolUse(Bash) | Block rm -rf, git push --force |
| pre-commit-gate.sh | PreToolUse(Bash) | Require verification before commit |
| code-review-reminder.sh | PostToolUse(Edit/Write) | Track modified files |
| suggest-compact.sh | PostToolUse(Edit/Write) | Suggest context compaction |
| stop-gate.sh | Stop | Block stop if review pending |
| mark-verified.sh | Utility | Set verification marker |
| review-complete.sh | Utility | Clear review marker |
| claude-update-check.sh | Utility | Check for Claude updates |
| error-tracker.sh | PostToolUseFailure | Track errors, enforce root cause fix |
| standards-reminder.sh | PostToolUse(Edit/Write) | Enforce standards-first for .claude/ changes |
| test-hooks.sh | Testing | Validate hooks |

### Skills (/commands)

| Skill | Description |
|-------|-------------|
| /build-fix | Build error resolution |
| /verify | Pre-commit verification |
| /commit | Git commit with format |
| /pr | Create pull request |
| /deploy | Deploy to production |
| /status | Workspace status |
| /eval | Eval-Driven Development |
| /audit | Standards compliance audit |

## Troubleshooting

| 문제 | 해결 |
|------|------|
| 컨테이너 빌드 실패 | `docker compose build --no-cache` |
| Claude 재인증 | named volume 확인: `docker volume ls \| grep claude-config` |
| 잘못된 Node 버전 | `nvm use` 또는 `.nvmrc` 생성 |
| 포트 충돌 | `.env` PORT_* 변경 + devcontainer.json forwardPorts 수정 |
| MCP 연결 실패 | `rm ~/.claude.json && /usr/local/bin/setup-env.sh` |
| Hook test 실패 | `export CLAUDE_PROJECT_DIR=/workspaces` |
| git permission 오류 | `git config core.filemode false` |

---

*Last updated: 2026-03-21*
