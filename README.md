# Polyagent DevContainer

복수 AI 코딩 에이전트를 동등 환경에서 병행 운영하는 격리 개발 환경 템플릿.

현재 지원: **Claude Code** · **OpenAI Codex CLI**
설계 원칙: 추가 에이전트(Cursor, Aider 등)를 동일 ground-truth + mirror 모델로 수용 가능.

기본 구성: 2 agents · 6 hooks · 4 skills · MCP × 2 (Context7, Serena)

---

## 변형 (Variants)

| Variant | 위치 | 용도 | Port Band |
|---------|------|------|:---------:|
| **base** | `.devcontainer/` (루트) | 범용 베이스 — Reopen in Container 즉시 동작 | 31000 |
| **datascience** | `variants/datascience/` | Jupyter + Data Science 패키지 | 32000 |

base는 루트의 `.devcontainer/`로 즉시 사용 가능. DataScience variant는 `variants/datascience/` 디렉터리 자체를 VS Code로 열어 사용.

---

## 필요 조건

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [VS Code](https://code.visualstudio.com/) + [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

---

## 시작하기 (base variant)

### 1. 클론

```bash
git clone <your-repo-url> my-project
```

### 2. VS Code에서 열기

1. VS Code → File → Open Folder → `my-project` 선택
2. `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**
3. 첫 빌드 ~3-5분

### 3. AI 에이전트 실행

```bash
# Claude Code (권한 프롬프트 없이 자동 승인)
claude --dangerously-skip-permissions

# Codex CLI (DevContainer 한정 sandbox 우회 — 사유: REFERENCE.md 참조)
codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "<prompt>"

# 이전 Claude 세션 이어서 작업
claude --dangerously-skip-permissions --continue
```

### 4. 프로젝트 초기 설정

원하는 에이전트 프롬프트에 아래 전체를 붙여넣기:

```
프로젝트 초기 설정을 수행해 주세요.

## 수집할 정보 (대화형으로 질문)
- 프로젝트명, 설명, GitHub URL
- 언어/프레임워크 (예: Python+FastAPI, TypeScript+Next.js, Go+Gin)
- 필요한 서비스 (PostgreSQL, Redis, OpenSearch 등)
- 포트 매핑 (기본: APP=31000, API=31080, DB=31432, EXTRA=31379)
- 서버 정보 (있으면)
- 테스트 프레임워크, CI/CD, 커밋 메시지 언어

## 수행할 작업
1. 프로젝트에 필요한 언어/도구 설치 (apt, nvm, pip, cargo 등)
2. .serena/project.yml — languages 배열에 프로젝트 언어 추가
3. CLAUDE.md / AGENTS.md — Identity 섹션 업데이트
4. PROJECT.md — 프로젝트에 맞게 재작성
5. REFERENCE.md — 프로젝트별 명령어 업데이트
6. .devcontainer/.env — 포트, 타임존, Node 버전 설정
7. .devcontainer/devcontainer.json — forwardPorts 동기화
8. .claude/rules/project/ — 프로젝트 코딩 규칙 생성

## 검증
- bash .devcontainer/verify-template.sh
- bash .claude/hooks/test-hooks.sh

## 주의
- .claude/settings.json, .codex/hooks.json, Dockerfile, 에이전트 frontmatter는 수정 금지

질문부터 시작해 주세요.
```

### 5. 저장

```bash
git add -A && git commit -m "chore: initialize project"
```

---

## 시작하기 (datascience variant)

```bash
git clone <your-repo-url> my-ds-project
cd my-ds-project/variants/datascience
code .
# Ctrl+Shift+P → Dev Containers: Reopen in Container
```

DataScience variant는 자체 `.devcontainer/`, `data/`, `models/`, `notebooks/`, `src/`, `tests/` 구조 보유. 상세는 [variants/datascience/README.md](variants/datascience/README.md) 참조.

---

## VS Code 연결 방식

| 방식 | 설정 적용 | 워크스페이스 | 확장 |
|------|----------|-------------|------|
| **Reopen in Container** (권장) | devcontainer.json 전체 적용 | `/workspaces/` 자동 | 자동 설치 |
| **Attach to Running Container** | 미적용 | 수동 Open Folder 필요 | 수동 설치 필요 |

**Reopen in Container 접근:**
1. VS Code에서 프로젝트 폴더(또는 variant 폴더)를 **로컬로** 열기 (File → Open Folder)
2. `Ctrl+Shift+P` → "Dev Containers: Reopen in Container"

> Attach는 이미 실행 중인 컨테이너에 단순 연결합니다. devcontainer.json 설정(워크스페이스 경로, 확장, 포트 포워딩)이 적용되지 않습니다.

---

## 포함 사항

| 구성 | 수량 |
|------|------|
| AI Agents | Claude Code + Codex CLI (동등 병행) |
| Sub-Agents | 2 (evaluator, wip-manager) |
| Hooks (Claude) | 6 (session-start, pre-commit-gate, pre-push-gate, refinement-gate, meta-evolution-guard, sub-project-edit-guard) |
| Hooks (Codex) | 4 (session-start, pre-commit-gate, pre-push-gate, refinement-gate) |
| Skills | 4 (/refine, /status, /verify, /wiki) |
| MCP | 2 (Context7, Serena) |
| Tools | 20+ (ripgrep, fd, fzf, jq, tmux, docker CLI, gh 등) |

## 포트 (base variant 기준, 컨테이너 내부)

> 호스트 매핑 포트는 `.devcontainer/.env`의 `PORT_*`로 설정. 상세: [REFERENCE.md](REFERENCE.md)

| 변수 | 기본값 | 용도 |
|------|--------|------|
| PORT_APP | 31000 | 앱 |
| PORT_API | 31080 | API |
| PORT_DB | 31432 | DB |
| PORT_EXTRA | 31379 | 추가 (Redis 등) |

변경: `.devcontainer/.env`의 `PORT_*` 수정 + `devcontainer.json`의 `forwardPorts` 동기화 → 컨테이너 재빌드.

DataScience variant는 32000 대역(32000/32080/32432/32888 — Jupyter 포함)을 사용. 상세는 해당 variant 디렉터리 참조.

## CLI 환경 구성

### Docker 컨테이너 (base)

```bash
# 빌드 / 재빌드
cd .devcontainer && docker compose build
cd .devcontainer && docker compose build --no-cache   # 캐시 없이 (~3-5분)

# 시작 / 정지 / 상태 / 로그
cd .devcontainer && docker compose up -d
cd .devcontainer && docker compose down
cd .devcontainer && docker compose ps
cd .devcontainer && docker compose logs -f

# 컨테이너 접속
docker exec -it polyagent-dev bash
cd .devcontainer && docker compose exec polyagent-devcontainer bash

# 이미지 / 볼륨 확인
docker images | grep polyagent-dev
docker volume ls | grep -E 'claude-config|codex-config'
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
| Codex 재인증 | `docker volume ls \| grep codex-config` |
| MCP 연결 실패 | `rm ~/.claude.json && /usr/local/bin/setup-env.sh` |
| 포트 충돌 | `.env` + `devcontainer.json` 포트 변경 후 재빌드 |
| `.agents/` drift | `bash scripts/sync-agents-mirror.sh` 재실행 |

---

## 라이선스 / 출처

이전 명칭: `claude-devcontainer`. 2026-04-30 Codex parity 추가 + DataScience variant 흡수와 함께 `polyagent-devcontainer`로 재정체성. Git history 그대로 보존.

배포 채널:
- GitHub: https://github.com/mememade-github/polyagent-devcontainer (개발 ground truth)
- 사내 GitLab (public mirror, pull): `<group>/polyagent-devcontainer` (DAX 사내망 한정)
