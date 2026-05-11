# Trust Boundary

> Phase 0 of the Anthropic-enterprise + karpathy-skills aligned security framework.
> Anchored in Karpathy R1.1 Think Before Coding — every assumption made about
> trust scope is surfaced explicitly here, not left implicit.

## Reference baseline — karpathy-skills

The reference repo (`forrestchang/andrej-karpathy-skills`) ships:

```
.claude-plugin/plugin.json   # name, description, version, author, license, keywords, skills[]
skills/karpathy-guidelines/SKILL.md   # name, description in frontmatter; pure prompt text
```

Risk dimensions (Anthropic enterprise §위험 등급):
- code execution: **0**  (no `*.py`, `*.sh`, `*.js`)
- command manipulation: **0**
- MCP references: **0**
- network access: **0**  (no `http`, `curl`, `fetch`, `requests`)
- hardcoded credentials: **0**
- file system scope: bounded to skill directory
- tool invocations: **0**  (no Bash / Edit / Agent calls)

Our system has higher capability than baseline by design. This document
records each component's deviation and its justification, per Karpathy R1.1.

---

## Components — 11 entities

### Agents (2)

#### 1. `agents/evaluator.md`
- **Role**: Context-isolated evaluation specialist. 1-pass review after code changes; scores against frozen Contract within `/refine`.
- **Trust scope (read)**: workspace files referenced by the caller's request.
- **Trust scope (write)**: evaluation report (path supplied by caller).
- **Tool scope**: `Read, Write, Edit, Bash, Grep, Glob, WebSearch, WebFetch`
- **Invocation**: invoked by `/refine` skill loop and by ROOT after code edits (CLAUDE.md §5.6). Does not invoke other agents.
- **Karpathy-baseline delta**: code execution + network present. Justification: must run tests/builds to score; may consult external docs to validate cross-references.

#### 2. `agents/wip-manager.md`
- **Role**: Manage WIP for multi-session tasks. Auto-invoked when tasks span sessions.
- **Trust scope (read)**: `wip/`, project files referenced by user request.
- **Trust scope (write)**: `wip/task-*/README.md`, `wip/task-*/`.
- **Tool scope**: `Read, Write, Edit, Bash, Grep, Glob, WebSearch, WebFetch`
- **Invocation**: ROOT invokes per CLAUDE.md §5.5. Does not invoke other agents.
- **Karpathy-baseline delta**: identical scope to evaluator. Justification: WIP auto-resume needs branch/file inventory; documentation tasks may consult external references.

### Hooks (4)

#### 3. `hooks/session-start.sh`
- **Role**: SessionStart hook. Injects project context + WIP auto-resume + env check.
- **Trust scope (read)**: `.git/`, `wip/`, `MEMORY.md`, branch state.
- **Trust scope (write)**: stdout JSON + stale `.claude/.last-verification.<branch>` cleanup (`rm -f`).
- **Tool scope**: shell built-ins + `git`, `jq`. No network.
- **Invocation**: triggered automatically by Claude Code at session start.
- **Karpathy-baseline delta**: code execution present. Justification: read-only context aggregation; no decision authority.

#### 4. `hooks/pre-commit-gate.sh`
- **Role**: PreToolUse hook (Bash matcher, `git commit*`). Blocks commits unless completion-checker recently ran on the branch.
- **Trust scope (read)**: `.claude/.last-verification.<branch>`, hook input JSON.
- **Trust scope (write)**: stderr only.
- **Tool scope**: shell built-ins. No network.
- **Invocation**: triggered for `git commit` Bash calls.
- **Karpathy-baseline delta**: code execution present. Justification: enforcement-only, no productive side effects.

#### 5. `hooks/pre-push-gate.sh`
- **Role**: PreToolUse hook (Bash matcher, `git push*`). 3-layer progressive hardening — Layer 1 blocks PAT residue in remote URL; Layer 2 warns on remote URL drift; Layer 3 (opt-in) blocks `.push-remote` declaration mismatch.
- **Trust scope (read)**: `git remote -v` output, hook input JSON, optional `.push-remote` file.
- **Trust scope (write)**: stderr + `.claude/.last-push-url.<remote>` baseline file (Layer 2 drift detection).
- **Tool scope**: shell built-ins + `git`, `grep`. No network.
- **Invocation**: triggered for `git push` Bash calls.
- **Karpathy-baseline delta**: same as pre-commit-gate. Same justification. Note: Layer 1 already covers credential-residue at push time — additional runtime credential-mask hook would duplicate this control (Karpathy R1.3 surgical avoidance).

#### 6. `hooks/refinement-gate.sh`
- **Role**: Stop hook. Prevents session stop during active `/refine` iteration when score < threshold.
- **Trust scope (read)**: `.refinement-active` marker, score files.
- **Trust scope (write)**: stdout JSON decision only.
- **Tool scope**: shell built-ins + `jq`. No network.
- **Invocation**: triggered at every Stop event.
- **Karpathy-baseline delta**: same as pre-commit-gate. Same justification.

### Skills (5)

#### 7. `skills/refine/SKILL.md`
- **Role**: Autonomous exploratory improvement loop — thin orchestrator with fresh-context agents.
- **Trust scope (read)**: project source per task scope.
- **Trust scope (write)**: project source per task scope; `.refinement-active`, `.refine-output`, `attempts/*.jsonl`.
- **Tool scope**: `Bash, Read, Write, Edit, Grep, Glob, Agent`
- **Invocation**: user-invocable via `/refine`.
- **Karpathy-baseline delta**: code execution + Agent recursion (highest autonomy). Justification: by-design exploratory loop; recursion is the loop mechanism, not a side channel.

#### 8. `skills/wiki/SKILL.md`
- **Role**: LLM Wiki — build and maintain structured knowledge bases with cross-referencing, consolidation, contradiction detection.
- **Trust scope (read)**: wiki source dirs.
- **Trust scope (write)**: wiki output dirs.
- **Tool scope**: `Bash, Read, Write, Edit, Grep, Glob, Agent`
- **Invocation**: user-invocable via `/wiki`.
- **Karpathy-baseline delta**: same as `/refine`. Justification: ingestion + contradiction detection requires multi-file traversal + sub-agent dispatch.

#### 9. `skills/status/SKILL.md`
- **Role**: Show workspace status — all git repos, services, WIP tasks, environment health.
- **Trust scope (read)**: workspace, `.git/` dirs, service ports.
- **Trust scope (write)**: stdout only.
- **Tool scope**: `Bash, Read, Glob, Grep`
- **Invocation**: user-invocable via `/status`.
- **Karpathy-baseline delta**: code execution present, **no Write/Edit/Agent**. Closest to baseline.

#### 10. `skills/verify/SKILL.md`
- **Role**: Run pre-commit verification checks on a product.
- **Trust scope (read)**: target product source.
- **Trust scope (write)**: marker file `.last-verification.<branch>`.
- **Tool scope**: `Bash, Read`
- **Invocation**: user-invocable via `/verify`.
- **Karpathy-baseline delta**: narrowest of all skills. Code execution present (must run tests). Closest to baseline along with `/status`.

#### 11. `skills/karpathy-guidelines/SKILL.md`
- **Role**: Reference handle for the Karpathy 4 rules. Loaded on demand by evaluator agent or explicit invocation; not user-invocable as a `/command`.
- **Trust scope (read)**: own `SKILL.md` + `EXAMPLES.md` body only.
- **Trust scope (write)**: none.
- **Tool scope**: none (prompt-text only; no `allowed-tools` declared in frontmatter).
- **Invocation**: passive — Read-tool fetched by other agents/skills as a behavioral reference.
- **Karpathy-baseline delta**: zero — this skill is Karpathy upstream verbatim (MIT). Closest to baseline of all components.

### Wiring — `settings.json`

`settings.json` declares the hook bindings. It is the trust-boundary integration point — every PreToolUse / Stop / SessionStart hook listed above is registered there. Hooks not listed in `settings.json` do not fire even if present in `hooks/`.

| Trigger | Matcher | Hook |
|---------|---------|------|
| SessionStart | — | session-start.sh |
| PreToolUse | Bash + `git commit*` | pre-commit-gate.sh |
| PreToolUse | Bash + `git push*` | pre-push-gate.sh |
| Stop | — | refinement-gate.sh |

---

## Verification — end-state for Phase 0

This document is correct iff:

1. Every file under `.claude/agents/`, `.claude/hooks/`, `.claude/skills/` has a section here.
2. Every section has all five fields: Role / Trust scope (read) / Trust scope (write) / Tool scope / Invocation / Karpathy-baseline delta.
3. Every hook listed in `settings.json` is present here.

Check command:

```bash
# Component count match (expect: 2 + 4 + 5 = 11)
expected=$(( $(ls /workspaces/.claude/agents/*.md 2>/dev/null | wc -l) \
          + $(ls /workspaces/.claude/hooks/*.sh 2>/dev/null | wc -l) \
          + $(ls -d /workspaces/.claude/skills/*/ 2>/dev/null | wc -l) ))
documented=$(grep -cE '^#### [0-9]+\.' /workspaces/.claude/security/trust-boundary.md)
[ "$expected" -eq "$documented" ] && echo "OK ($documented)" || echo "MISMATCH (expected=$expected, documented=$documented)"
```

---

*Created: 2026-04-28. Phase 0 of Alt B (karpathy-skills aligned).*
