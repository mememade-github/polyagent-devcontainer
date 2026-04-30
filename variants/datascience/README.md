# Polyagent DevContainer — DataScience Variant

Polyagent DevContainer base에 Miniconda + PyTorch CPU + Jupyter를 추가한 데이터사이언스 변형.

## 사용

```bash
# 1. 저장소 루트에서 변형 디렉터리 진입
cd variants/datascience

# 2. VS Code로 열기
code .

# 3. Ctrl+Shift+P → Dev Containers: Reopen in Container
```

VS Code가 `variants/datascience/.devcontainer/devcontainer.json`을 사용하여 컨테이너를 빌드합니다. 공통 자산(`.claude/`, `.codex/`, `.agents/`, scripts/)은 저장소 루트에서 9p mount로 접근.

## 차이점 (base 대비)

| 측면 | base | datascience |
|------|------|------|
| Port band | 31000 | 32000 |
| Container 이름 | `polyagent-dev` | `polyagent-ds-dev` |
| Image 이름 | `polyagent-devcontainer` | `polyagent-devcontainer-ds` |
| 추가 런타임 | — | Miniconda, PyTorch CPU, Jupyter (port 32888) |
| 프로젝트 스켈레톤 | — | `data/`, `models/`, `notebooks/`, `outputs/`, `src/`, `tests/` |

## 포트 (DataScience variant)

| 변수 | 기본값 | 컨테이너 내부 | 용도 |
|------|--------|:--------:|------|
| PORT_APP | 32000 | 3000 | 앱 |
| PORT_API | 32080 | 8080 | API |
| PORT_DB | 32432 | 5432 | DB |
| PORT_EXTRA | 32888 | 8888 | **JupyterLab** |

## Conda 환경

```bash
# 기본 conda env: ds (Python 3.12, PyTorch CPU, Jupyter, scientific stack)
conda activate ds
jupyter lab --no-browser --ip=0.0.0.0 --port=8888
```

## 공통 — base와 동일

- AI 에이전트: Claude Code + Codex CLI 동등 병행
- Sub-agents: 2 (evaluator, wip-manager)
- Skills: 5 (refine, status, verify, wiki, karpathy-guidelines)
- MCP: Context7, Serena
- 거버넌스: 저장소 루트의 `CLAUDE.md`, `AGENTS.md`, `.claude/rules/behavioral-core.md` 그대로 적용

상세는 저장소 루트 [README.md](../../README.md), [PROJECT.md](../../PROJECT.md), [REFERENCE.md](../../REFERENCE.md) 참조.
