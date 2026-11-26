---
name: verify
description: Run the checks relevant to a change and report what ran, failed, or was skipped
argument-hint: "[product-name|all]"
user-invocable: true
allowed-tools: Bash, Read
---

Run the checks relevant to the request and the change for `$ARGUMENTS` (default: `all`).

For `all`, run the fast checker:

```bash
bash "${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git rev-parse --show-toplevel)}}/scripts/meta/completion-checker.sh"
```

It checks shell syntax, the hook and rule JSON files, the Codex TOML (skipped when python3 has no tomllib), the tracked-content leak scan, and mirror drift; a pass establishes only those properties. Run the docker-backed acceptance suite on demand, not per commit:

```bash
bash "${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git rev-parse --show-toplevel)}}/.devcontainer/verify-template.sh"
```

For a specific product, read its governance and `REFERENCE.md` verification section, then run repository-defined checks. Report which commands ran and passed, which failed, and which checks were skipped.
