---
name: commit
description: Create a git commit with proper message format and verification
argument-hint: "[message]"
user-invocable: true
allowed-tools: Bash, Read
---

Create a git commit following project conventions.

## Pre-commit Checks

Before committing, run verification (see CLAUDE.md §3 for project-specific commands).

If a completion-checker script exists, run it:
```bash
$CLAUDE_PROJECT_DIR/scripts/meta/completion-checker.sh
```

If checks fail, fix issues before proceeding.

## Commit Process

1. **Stage changes**: Stage specific files (not `git add -A`)
2. **Review staged**: `git diff --cached --stat`
3. **Create commit**: Use conventional commit format

## Commit Message Format

```
<type>(<scope>): <description>

[optional body]

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting (no code change)
- `refactor`: Code restructure (no feature/fix)
- `test`: Adding tests
- `chore`: Build/config/tooling

### Scope
- Use the project/module name relevant to the change
- For workspace root: `workspace` or omit

## After Commit

Report the hash and summary. Do NOT push unless explicitly requested.
