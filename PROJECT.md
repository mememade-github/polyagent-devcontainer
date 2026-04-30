# PROJECT.md — Polyagent DevContainer Domain Context

> Tier 1 베이스 DevContainer 템플릿 — 다중 AI 코딩 에이전트 동등 병행 운영.
> 거버넌스 규칙: [CLAUDE.md](CLAUDE.md) (Claude) · [AGENTS.md](AGENTS.md) (Codex)
> 명령어/절차: [REFERENCE.md](REFERENCE.md)

---

## Overview

복수 AI 에이전트(Claude Code · Codex CLI · 향후 확장)를 동일한 격리 개발 환경에서 동등 병행
운영하기 위한 DevContainer 템플릿. 단일 ground truth + vendor별 mirror 모델로, 새 vendor가
추가되어도 거버넌스/규칙/스킬을 재작성하지 않고 흡수 가능.

기본 구성: 2 sub-agents · 6 hooks (Claude) / 4 hooks (Codex) · 4 skills · MCP × 2 (Context7, Serena).

## Variants

| Variant | Path | Port band | 추가 구성 |
|---------|------|:---------:|---------|
| **base** (default) | `.devcontainer/` | 31000 | (Tier 1 only) |
| **datascience** | `variants/datascience/` | 32000 | Jupyter, data/, models/, notebooks/, src/, tests/ |

base는 루트의 `.devcontainer/`로 즉시 사용. DataScience variant는 `variants/datascience/`
디렉터리 자체를 VS Code로 열어 사용 (자체 `.devcontainer/` 보유).

## Tech Stack

| Category | Technology |
|----------|-----------|
| Container | Docker Compose, DevContainer spec |
| Runtime | Ubuntu 22.04, Node.js 22 LTS (MCP/Codex), Python 3 (Serena) |
| AI Agents | Claude Code CLI, OpenAI Codex CLI |
| MCP | Context7 (documentation), Serena (code intelligence) |
| Tools | ripgrep, fd, jq, tmux, gh CLI, docker CLI |

## Polyagent Parity Model

| Vendor | Source of truth | Mirror |
|--------|----------------|--------|
| Claude Code | `CLAUDE.md`, `.claude/{rules,skills,hooks,agents,security}/`, `.claude/settings.json` | — |
| Codex CLI | (mirror) | `AGENTS.md`, `.agents/{rules,skills,security}/`, `.codex/{config.toml,hooks.json,hooks/}` |
| 향후 vendor | (mirror) | 동일 패턴으로 추가 |

Sync: `bash scripts/sync-agents-mirror.sh` — `.claude/` → `.agents/` 단방향 overlay (preserve-extras).

## Port Bands (variant별 충돌 방지)

```
HOST 포트 = 대역기준 + 표준포트 하위 3자리
CONTAINER 내부 포트 = 항상 표준 고정 (3000, 8080, 5432, 6379/8888)
docker-compose.yml: "${HOST_PORT}:${STANDARD_PORT}" 패턴
```

| Variant | 대역 | PORT_APP | PORT_API | PORT_DB | PORT_EXTRA |
|---|:---:|:---:|:---:|:---:|:---:|
| base | 31000 | 31000 | 31080 | 31432 | 31379 |
| datascience | 32000 | 32000 | 32080 | 32432 | 32888 (Jupyter) |
| *(future)* | 33000 | 33000 | 33080 | 33432 | 33xxx |

## MCP Servers

| Server | Purpose |
|--------|---------|
| Context7 | Library documentation search |
| Serena | Code intelligence (Python) |

## Distribution

| Channel | URL | Role |
|---------|-----|------|
| GitHub (origin) | `mememade-github/polyagent-devcontainer` | 개발 ground truth — 모든 commit/push의 원본 |
| 사내 GitLab (mirror, public) | `<group>/polyagent-devcontainer` (<gitlab-host>:<port>) | DAX 사내망 사용자용 read-only mirror — Pull Mirroring 자동 동기화 |

## Environment

- **Configuration**: `.devcontainer/.env` (variant별 단일 소스)
- **Persistent Volumes**: `~/.claude` (Claude auth), `~/.codex` (Codex auth), `/commandhistory` (history)

---

*Last updated: 2026-04-30 — renamed claude-devcontainer → polyagent-devcontainer + DataScience variant 흡수 + GitLab public mirror 추가*
