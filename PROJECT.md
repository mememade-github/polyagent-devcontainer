# PROJECT.md — Polyagent DevContainer

> Tier 1 base DevContainer template — multi-AI-agent parity environment.
> Governance: [CLAUDE.md](CLAUDE.md) (Claude) · [AGENTS.md](AGENTS.md) (Codex, Antigravity)
> Commands: [REFERENCE.md](REFERENCE.md)

## Overview

Workspace-scoped environment for running Claude Code, Codex CLI, and Antigravity CLI in parity on the same project. One ground truth (`.claude/`) feeds per-vendor mirrors (`.agents/rules`, `.agents/skills`, `.codex/`). New vendors are added by mirroring, not by rewriting governance.

Default loadout: 2 sub-agents · 4 hooks · 5 skills (refine, status, verify, karpathy-guidelines, typesafe-ai).

## Tech Stack

| Category | Technology |
|----------|-----------|
| Container | Docker Compose, DevContainer spec |
| Runtime | Ubuntu 22.04, Node.js 22 LTS, Python 3 |
| AI Agents | Claude Code CLI, OpenAI Codex CLI, Google Antigravity CLI (`agy`) |
| Tools | ripgrep, fd, fzf, jq, tmux, gh CLI, docker CLI, uv |

## Polyagent Parity Model

| Vendor | Source of truth | Mirror |
|--------|----------------|--------|
| Claude Code | `CLAUDE.md`, `.claude/{rules,skills,hooks,agents}/`, `.claude/settings.json` | — |
| Codex CLI | (mirror) | `AGENTS.md`, `.agents/{rules,skills}/`, `.codex/{config.toml,hooks.json,hooks/}` |
| Antigravity CLI | (mirror + native adapter) | `AGENTS.md`, `.agents/{rules,skills}/`; native `.agents/rules.json`, `.agents/hooks.json`, `.agents/hooks/claude-hooks-adapter.sh` (runs `.claude/hooks/`) |

Sync: `bash scripts/sync-agents-mirror.sh` — `.claude/` → `.agents/rules`, `.agents/skills` one-way generated mirror (copies edits; prunes orphans whose `.claude/` source was deleted; leaves the native `.agents/` files untouched).

## Environment

- **Template configuration**: `.devcontainer/.env` (build and startup values)
- **Persistent volumes**: `~/.claude` (Claude auth), `~/.codex` (Codex auth), `~/.gemini` (Antigravity auth, settings, conversations), `~/.config/antigravity` (Antigravity plugin/MCP secrets), `/commandhistory` (shell history)
- **Editor workspace settings**: `.vscode/` is tracked for VS Code convenience settings; it is not an agent vendor.

## Distribution

- **GitHub** (origin): `mememade-github/polyagent-devcontainer` — development ground truth

---

*Last updated: 2026-10-17*
