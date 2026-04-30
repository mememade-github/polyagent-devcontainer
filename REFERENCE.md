# REFERENCE.md — Commands & Procedures

> Actionable commands, configuration, and troubleshooting.
> For domain context (services, ports, infrastructure), see [PROJECT.md](PROJECT.md).

## Configuration (.env)

모든 사용자 설정은 `.devcontainer/.env` 단일 파일에서 관리합니다.

| 변수 | 기본값 | 참조 위치 | 용도 |
|------|--------|----------|------|
| `COMPOSE_PROJECT_NAME` | `polyagent-devcontainer` | docker-compose.yml | Docker 네임스페이스 |
| `CONTAINER_NAME` | `polyagent-dev` | docker-compose.yml | 컨테이너 이름 |
| `IMAGE_NAME` | `polyagent-devcontainer` | docker-compose.yml | 이미지 이름 |
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
  [1/2] 권한 설정 (Docker 소켓, git filemode, 명령 히스토리)
  [2/2] SSH 설정 (호스트 키 바인드 시)
  MCP: 플러그인 자동 관리 (Context7, Serena, Playwright)

postStartCommand (매 시작 시)
  git config core.filemode false
```

## Persistent Volumes

| Volume | Target | Purpose |
|--------|--------|---------|
| `claude-config-${devcontainerId}` | `~/.claude` | Claude Code 인증 (rebuild 유지) |
| `codex-config-${devcontainerId}` | `~/.codex` | Codex CLI 인증 (rebuild 유지) |
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
| **Codex** | Codex CLI (npm global), AGENTS.md, .codex/ hooks |
| **Node.js** | node 22 LTS, npm, npx (Context7 MCP 인프라용) |
| **Python** | python3, uv, jedi (Serena 인프라용), ruff, pytest, mypy (정제 루프 검증용) |

## Agent System

### Agents (2)

| Agent | Purpose | Invocation |
|-------|---------|------------|
| evaluator | Context-isolated quality evaluation | After changes; within /refine loop |
| wip-manager | Multi-session task tracker | When task spans sessions |

### Hooks (6)

| Hook | Event | Purpose |
|------|-------|---------|
| session-start.sh | SessionStart | Git status, WIP resume, Known Issues |
| pre-commit-gate.sh | PreToolUse(Bash) | Require verification before commit |
| pre-push-gate.sh | PreToolUse(Bash) | Git push safety gate |
| refinement-gate.sh | Stop | Block stop if refinement pending |
| meta-evolution-guard.sh | PreToolUse(Bash) | Meta-Evolution delegation wrapper enforcement (§6 projects) |
| sub-project-edit-guard.sh | PreToolUse(Edit\|Write) | Block Edit/Write on §6 sub-project trees (§6 projects) |

### Skills (/commands — 4)

| Skill | Description |
|-------|-------------|
| /refine | Autonomous iterative refinement loop |
| /status | Workspace status |
| /verify | Pre-commit verification |
| /wiki | Structured knowledge wiki (init, ingest, query, lint) |
## Polyagent Parity

본 템플릿은 다중 AI 에이전트(현재 Claude Code · Codex CLI) 병행 운영을 지원합니다.
새 vendor 추가 시 동일 ground-truth + mirror 패턴으로 흡수.

### Ground Truth & Mirror

| 측면 | Claude (ground truth) | Codex (mirror) |
|------|----------------------|----------------|
| 거버넌스 문서 | `CLAUDE.md` (@import 자동 로드) | `AGENTS.md` (별도 파일, Read 도구로 로드) |
| 규칙/스킬/보안 | `.claude/{rules,skills,security}/` | `.agents/{rules,skills,security}/` |
| Hook 설정 | `.claude/settings.json` | `.codex/hooks.json` |
| Hook 스크립트 | `.claude/hooks/*.sh` | `.codex/hooks/*.sh` |
| Sub-agent | `.claude/agents/*.md` (격리 컨텍스트) | `.agents/skills/<name>/SKILL.md` (skill로 흡수) |

### Mirror 동기화

```bash
# Claude 측(.claude/)을 변경한 후 Codex 측(.agents/)에 반영
bash scripts/sync-agents-mirror.sh         # 미러 갱신
bash scripts/sync-agents-mirror.sh --dry   # 변경 확인만
```

`.agents/`는 자동 생성된 미러이므로 직접 수정 금지. ground truth는 `.claude/`.

### Codex 명령

```bash
# 인증 — device flow (volume 영속)
codex login --device-auth
# → 출력된 URL + 코드를 브라우저에서 입력

# 인증 상태 확인
codex login status

# 대화형 시작 (AGENTS.md 자동 로드)
codex

# 비대화형 실행 (DevContainer 환경 권장 옵션 포함)
codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "<prompt>"

# 버전 확인
codex --version
```

#### `--dangerously-bypass-approvals-and-sandbox` 사용 사유 (DevContainer 한정)

Codex CLI는 기본적으로 [bubblewrap](https://github.com/containers/bubblewrap)으로 명령 실행을 sandbox화합니다. 그러나 bubblewrap은 unprivileged user namespace를 요구하는데, Docker 컨테이너 내부에서는 kernel 정책상 이 namespace 생성이 차단되어 있어 sandbox 내 모든 쉘 호출이 실패합니다 (오류: `bwrap: No permissions to create a new namespace`).

| 환경 | sandbox 작동 | 권장 옵션 |
|------|:-----------:|----------|
| 호스트 Linux 직접 실행 | ✓ | (default) `--sandbox workspace-write` |
| **DevContainer 내부** | ✗ (kernel 제약) | `--dangerously-bypass-approvals-and-sandbox` |

DevContainer 자체가 이미 격리 환경이므로 Codex의 redundant sandbox는 우회 합리적. 컨테이너 외부에서 Codex를 사용할 때는 default sandbox 유지.

### Codex Vendor 제약

| 항목 | 제약 | 우회 |
|------|------|------|
| Edit\|Write matcher | PreToolUse hook 미지원 | `Bash(...)` 패턴만 사용 |
| Sub-agent 격리 | 미지원 | agents → skills로 흡수 (`.agents/skills/`) |
| frontmatter `tools`/`model`/`color` | 무시됨 | 본문은 그대로 유지, vendor가 무시 |
| `@import` 구문 | 미지원 | AGENTS.md 본문 self-contained 또는 Read 도구로 명시 로드 |

## Troubleshooting

| 문제 | 해결 |
|------|------|
| 컨테이너 빌드 실패 | `docker compose build --no-cache` |
| Claude 재인증 | named volume 확인: `docker volume ls \| grep claude-config` |
| Codex 재인증 | named volume 확인: `docker volume ls \| grep codex-config` |
| 잘못된 Node 버전 | `nvm use` 또는 `.nvmrc` 생성 |
| 포트 충돌 | `.env` PORT_* 변경 + devcontainer.json forwardPorts 수정 |
| MCP 연결 실패 | `rm ~/.claude.json && /usr/local/bin/setup-env.sh` |
| Hook test 실패 | `export CLAUDE_PROJECT_DIR=/workspaces` (Codex: `CODEX_PROJECT_DIR`) |
| git permission 오류 | `git config core.filemode false` |
| `.agents/` drift | `bash scripts/sync-agents-mirror.sh` 재실행 |

---

*Last updated: 2026-03-21*
