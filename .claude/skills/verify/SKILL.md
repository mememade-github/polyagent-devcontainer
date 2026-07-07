---
name: verify
description: Run pre-commit verification checks on a product
argument-hint: "[product-name|all]"
user-invocable: true
allowed-tools: Bash, Read
---

Run verification checks for the specified product. Default is "all".

Target: $ARGUMENTS (default: all)

## For "all" (default)

Run the fast, environment-independent completion checker (vendor-neutral root
resolution so the mirrored Codex skill works without `$CLAUDE_PROJECT_DIR`):
```bash
bash "${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git rev-parse --show-toplevel)}}/scripts/meta/completion-checker.sh"
```
On success it writes the per-branch marker the pre-commit gate reads
(existence + 24h freshness).

For the full acceptance suite (on-demand / CI — docker-backed, not per commit):
```bash
bash "${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git rev-parse --show-toplevel)}}/.devcontainer/verify-template.sh"
```

## For a specific product

1. Read the pre-commit verification section of CLAUDE.md / AGENTS.md and
   REFERENCE.md §Verification for project-specific commands.
2. Detect project type from files:
   - `pyproject.toml` → Python: `ruff check src/ && mypy src/ --ignore-missing-imports`
   - `package.json` → TypeScript: `pnpm build`
   - `Cargo.toml` → Rust: `cargo build`

Report results clearly with PASS/FAIL for each check.
