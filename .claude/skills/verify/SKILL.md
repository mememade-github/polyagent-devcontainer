---
name: verify
description: Run pre-commit verification checks on a product
argument-hint: "[product-name|all]"
user-invocable: true
allowed-tools: Bash, Read
paths:
  - "products/**/*.py"
  - "products/**/*.ts"
  - "products/**/*.tsx"
  - "**/pyproject.toml"
  - "**/package.json"
  - "**/Cargo.toml"
---

Run verification checks for the specified product. Default is "all".

Target: $ARGUMENTS (default: all)

## Auto-Detection

1. Read CLAUDE.md §3 (Pre-Commit Gate) for project-specific verification commands
2. Read REFERENCE.md "Local CI" section for detailed check commands
3. Detect project type from files:
   - `pyproject.toml` → Python: `ruff check src/ && mypy src/ --ignore-missing-imports`
   - `package.json` → TypeScript: `pnpm build`
   - `Cargo.toml` → Rust: `cargo build`

## For "all"

Run the project's completion-checker script if available:
```bash
$CLAUDE_PROJECT_DIR/scripts/meta/completion-checker.sh
```

Or run verification for each detected project directory.

Report results clearly with PASS/FAIL for each check.
