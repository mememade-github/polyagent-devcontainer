# Claude DevContainer

Claude Code + 13 Agent System이 포함된 격리 개발 환경 템플릿.

---

## 필요 조건

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [VS Code](https://code.visualstudio.com/) + [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

---

## 시작하기

### 1. 클론

```bash
git clone https://github.com/mememade-github/claude-devcontainer.git my-project
```

### 2. VS Code에서 열기

1. VS Code → File → Open Folder → `my-project` 선택
2. `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**
3. 첫 빌드 ~3-5분

### 3. Claude Code 실행

```bash
# 새 세션 시작 (권한 프롬프트 없이 자동 승인)
claude --dangerously-skip-permissions

# 이전 세션 이어서 작업
claude --dangerously-skip-permissions --continue
```

> `--dangerously-skip-permissions`: 파일 수정, 명령 실행 등 모든 도구를 승인 없이 허용합니다.
> `--continue`: 마지막 대화 컨텍스트를 이어받아 계속합니다.

### 4. 프로젝트 초기 설정

Claude 프롬프트에 아래 전체를 붙여넣기:

```
프로젝트 초기 설정을 수행해 주세요.

## 수집할 정보 (대화형으로 질문)
- 프로젝트명, 설명, GitHub URL
- 언어/프레임워크 (예: Python+FastAPI, TypeScript+Next.js, Go+Gin)
- 필요한 서비스 (PostgreSQL, Redis, OpenSearch 등)
- 포트 매핑 (기본: APP=3000, API=8080, DB=5432, EXTRA=6379)
- 서버 정보 (있으면)
- 테스트 프레임워크, CI/CD, 커밋 메시지 언어

## 수행할 작업
1. 프로젝트에 필요한 언어/도구 설치 (apt, nvm, pip, cargo 등)
2. .serena/project.yml — languages 배열에 프로젝트 언어 추가
3. CLAUDE.md — Identity 섹션 업데이트
4. PROJECT.md — 프로젝트에 맞게 재작성
5. REFERENCE.md — 프로젝트별 명령어 업데이트
6. .devcontainer/.env — 포트, 타임존, Node 버전 설정
7. .devcontainer/devcontainer.json — forwardPorts 동기화
8. .claude/rules/project/ — 프로젝트 코딩 규칙 생성

## 검증
- bash .devcontainer/verify-template.sh
- bash .claude/hooks/test-hooks.sh

## 주의
- .claude/settings.json, Dockerfile, 에이전트 frontmatter는 수정 금지

질문부터 시작해 주세요.
```

### 5. 저장

```bash
git add -A && git commit -m "chore: initialize project"
```

---

## VS Code 연결 방식

| 방식 | 설정 적용 | 워크스페이스 | 확장 |
|------|----------|-------------|------|
| **Reopen in Container** (권장) | devcontainer.json 전체 적용 | `/workspaces/` 자동 | 자동 설치 |
| **Attach to Running Container** | 미적용 | 수동 Open Folder 필요 | 수동 설치 필요 |

**Reopen in Container 접근:**
1. VS Code에서 프로젝트 폴더를 **로컬로** 열기 (File → Open Folder)
2. `Ctrl+Shift+P` → "Dev Containers: Reopen in Container"

> Attach는 이미 실행 중인 컨테이너에 단순 연결합니다. devcontainer.json 설정(워크스페이스 경로, 확장, 포트 포워딩)이 적용되지 않습니다.

---

## 포함 사항

| 구성 | 수량 |
|------|------|
| Agents | 13 (code-reviewer, debugger, planner, architect 등) |
| Hooks | 12 (세션 시작, 파괴적 명령 차단, 코드리뷰, 커밋 전 검증 등) |
| Skills | 8 (/commit, /pr, /verify, /status, /deploy, /build-fix, /eval, /audit) |
| MCP | 2 (Context7, Serena) |
| Tools | 20+ (ripgrep, fd, fzf, jq, tmux, docker CLI, gh 등) |

## 포트

| 변수 | 기본값 | 용도 |
|------|--------|------|
| PORT_APP | 3000 | 앱 |
| PORT_API | 8080 | API |
| PORT_DB | 5432 | DB |
| PORT_EXTRA | 6379 | 추가 (Redis 등) |

변경: `.devcontainer/.env`의 `PORT_*` 수정 + `devcontainer.json`의 `forwardPorts` 동기화 → 컨테이너 재빌드.

## CLI 환경 구성

### Docker 컨테이너

```bash
# 빌드
cd .devcontainer && docker compose build

# 캐시 없이 재빌드 (~3-5분)
cd .devcontainer && docker compose build --no-cache

# 시작 / 정지 / 상태
cd .devcontainer && docker compose up -d
cd .devcontainer && docker compose down
cd .devcontainer && docker compose ps

# 로그
cd .devcontainer && docker compose logs -f
```

### 프로젝트 환경

```bash
# Node.js 버전 확인
node --version

# 프로젝트 Node.js 설정 (.nvmrc 생성 후)
nvm install && nvm use

# 환경 검증
bash .devcontainer/verify-template.sh    # 전체 검증
bash .claude/hooks/test-hooks.sh         # Hook 검증
```

## Troubleshooting

| 문제 | 해결 |
|------|------|
| 빌드 실패 | `docker compose build --no-cache` |
| 파일이 안 보임 | "Reopen in Container" 사용 (Attach 아님) |
| Reopen 메뉴 없음 | Dev Containers 확장 설치 확인 |
| Claude 재인증 | `docker volume ls \| grep claude-config` |
| MCP 연결 실패 | `rm ~/.claude.json && /usr/local/bin/setup-env.sh` |
| 포트 충돌 | `.env` + `devcontainer.json` 포트 변경 후 재빌드 |
