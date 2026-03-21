# PROJECT.md — Claude DevContainer Domain Context

> Tier 1 베이스 DevContainer 템플릿.
> 거버넌스 규칙: [CLAUDE.md](CLAUDE.md)
> 명령어/절차: [REFERENCE.md](REFERENCE.md)

---

## Overview

Claude Code 개발을 위한 베이스 DevContainer 템플릿. 14 agents, 12 hooks, 8 skills, MCP 서버(Context7, Serena)를 포함한 완전한 Claude Code 워크스페이스를 제공합니다.

## Tech Stack

| Category | Technology |
|----------|-----------|
| Container | Docker Compose, DevContainer spec |
| Runtime | Ubuntu 22.04, Node.js 22 LTS (MCP), Python 3 (Serena) |
| AI | Claude Code CLI, Context7 MCP, Serena MCP |
| Tools | ripgrep, fd, jq, tmux, gh CLI, docker CLI |

## Port Band (31000)

| Port | Variable | Purpose |
|------|----------|---------|
| 31000 | PORT_APP | Application / dev server |
| 31080 | PORT_API | API server |
| 31432 | PORT_DB | Database |
| 31379 | PORT_EXTRA | Redis / queue |

## MCP Servers

| Server | Purpose |
|--------|---------|
| Context7 | Library documentation search |
| Serena | Code intelligence (Python) |

## Environment

- **Configuration**: `.devcontainer/.env` (single source)
- **Persistent Volumes**: `~/.claude` (auth), `/commandhistory` (history)

---

*Last updated: 2026-03-22*
