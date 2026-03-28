---
name: build-fix
description: Fix build errors quickly. Delegates to build-error-resolver agent for minimal-diff fixes.
user-invocable: true
allowed-tools: Bash, Read, Agent
paths:
  - "**/package.json"
  - "**/tsconfig.json"
  - "**/pyproject.toml"
  - "**/Cargo.toml"
---

# /build-fix — Build Error Resolution

Delegates to the **build-error-resolver** agent to fix build/type errors with minimal diffs.

## Usage

```
/build-fix                    # Auto-detect project from current directory
/build-fix <project>          # Fix specific project build errors
```

## What It Does

1. Reads CLAUDE.md/REFERENCE.md for project-specific build commands
2. Runs the build command for the target project
3. If errors found, delegates to `build-error-resolver` agent
4. Agent fixes errors with minimal diffs
5. Re-runs build to verify
6. Reports result

## Build Command Discovery

Check these sources for project-specific build commands:
1. `REFERENCE.md` — "Local CI" section
2. `CLAUDE.md` — "Pre-Commit Gate" section
3. `package.json` → `pnpm build` (TypeScript/Node.js)
4. `pyproject.toml` or `setup.cfg` → `ruff check` + `mypy` (Python)
