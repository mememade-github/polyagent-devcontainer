---
name: verify
description: Run pre-commit verification checks on a product
argument-hint: "[product-name|all]"
user-invocable: true
allowed-tools: Bash, Read
---

Run verification checks for the specified product. Default is "all".

Target: $ARGUMENTS (default: all)

## Auto-Detection

1. Read the Pre-Commit Gate / verification section of CLAUDE.md for project-specific verification commands
2. If present, read the local-CI / verification-commands section of REFERENCE.md for detailed checks
3. Detect project type from files:
   - `pyproject.toml` → Python: `ruff check src/ && mypy src/ --ignore-missing-imports`
   - `package.json` → TypeScript: `pnpm build`
   - `Cargo.toml` → Rust: `cargo build`

## For "all"

Run the project's completion-checker script if available (vendor-neutral root
resolution so the mirrored Codex skill works without `$CLAUDE_PROJECT_DIR`):
```bash
bash "${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git rev-parse --show-toplevel)}}/scripts/meta/completion-checker.sh"
```

Or run verification for each detected project directory.

Report results clearly with PASS/FAIL for each check.
