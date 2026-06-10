# PROJECT.md — Polyagent DevContainer

> Tier 1 base DevContainer template — multi-AI-agent parity environment.
> Governance: [CLAUDE.md](CLAUDE.md) (Claude) · [AGENTS.md](AGENTS.md) (Codex)
> Commands: [REFERENCE.md](REFERENCE.md)

## Overview

Isolated environment for running Claude Code and Codex CLI in parity on the same project. One ground truth (`.claude/`) feeds per-vendor mirrors (`.agents/`, `.codex/`). New vendors are added by mirroring, not by rewriting governance.

Default loadout: 2 sub-agents · 4 hooks · 5 skills (refine, status, verify, wiki, karpathy-guidelines).

## Tech Stack

| Category | Technology |
|----------|-----------|
| Container | Docker Compose, DevContainer spec |
| Runtime | Ubuntu 22.04, Node.js 22 LTS, Python 3 |
| AI Agents | Claude Code CLI, OpenAI Codex CLI |
| Tools | ripgrep, fd, fzf, jq, tmux, gh CLI, docker CLI, uv |

## Polyagent Parity Model

| Vendor | Source of truth | Mirror |
|--------|----------------|--------|
| Claude Code | `CLAUDE.md`, `.claude/{rules,skills,hooks,agents,security}/`, `.claude/settings.json` | — |
| Codex CLI | (mirror) | `AGENTS.md`, `.agents/{rules,skills,security}/`, `.codex/{config.toml,hooks.json,hooks/}` |

Sync: `bash scripts/sync-agents-mirror.sh` — `.claude/` → `.agents/` one-way overlay (preserve-extras).

## Environment

- **Configuration**: `.devcontainer/.env` (single source for all user-tunable values)
- **Persistent volumes**: `~/.claude` (Claude auth), `~/.codex` (Codex auth), `/commandhistory` (shell history)

## Distribution

- **GitHub** (origin): `mememade-github/polyagent-devcontainer` — development ground truth
- **Internal GitLab mirror**: shipped as an in-tree template at `.gitlab-ci.yml`. The consumer wires it to their GitLab project (register a Runner, set `GITLAB_PUSH_TOKEN`, add a schedule).

---

*Last updated: 2026-04-30*
