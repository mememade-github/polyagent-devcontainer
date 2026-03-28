# Hook & Lifecycle Reference

> Reference -- not auto-loaded into context. Read explicitly when needed.

---

## Hook JSON Protocol

**Input** (all events receive via stdin):
```json
{
  "session_id": "abc-123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/workspaces",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "Edit",
  "tool_input": {"file_path": "...", "old_string": "...", "new_string": "..."}
}
```

**Exit codes** (command hooks):

| Exit Code | Meaning | Effect |
|-----------|---------|--------|
| 0 | Success/allow | Tool proceeds normally |
| 2 | Block with feedback | Tool blocked, **stderr** shown to agent |
| Any other | Non-blocking error | Logged as warning, tool proceeds |

> Exit code 1 is non-blocking (logged), NOT a blocking signal.
> Only exit code 2 blocks. Stderr (not stdout) is fed back on block.

**hookSpecificOutput** (exit 0 only, on stdout):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask",
    "permissionDecisionReason": "reason shown to Claude",
    "additionalContext": "injected into context",
    "updatedInput": { "field": "new value" }
  }
}
```

> **CRITICAL**: Choose ONE approach per hook. Exit 2 ignores all JSON -- only stderr is read.
> JSON `permissionDecision` requires exit 0. Exit 2 + stderr is more reliable for blocking.

**Universal JSON fields** (exit 0 only, ALL events):
- `async: true` -- run hook in background without blocking
- `statusMessage` -- custom spinner text

---

## 23 Hook Scripts

### settings.json Event Mapping (18 직접 등록)

| Event | Matcher | Hook | Timeout | Category |
|-------|---------|------|---------|----------|
| SessionStart | (all) | session-start.sh | 15s | Context injection |
| PreToolUse | Bash | block-destructive.sh | 5s | Gate |
| PreToolUse | Bash | pre-commit-gate.sh | 5s | Gate |
| PreToolUse | Bash | pre-push-gate.sh | 5s | Gate |
| PreToolUse/PostToolUse | (all) | heartbeat.sh | 1s | Utility |
| PostToolUse | Edit\|Write | code-review-reminder.sh | 5s | Suggestion |
| PostToolUse | Edit\|Write | suggest-compact.sh | 2s | Suggestion |
| PostToolUse | Edit\|Write | standards-reminder.sh | 5s | Suggestion |
| PostToolUseFailure | (all) | error-tracker.sh | 5s | Observation |
| Stop | (all) | stop-gate.sh | 5s | Gate |
| Stop | (all) | refinement-gate.sh | 10s | Gate |
| SubagentStart | (all) | subagent-start-report.sh | 5s | Observation |
| SubagentStop | (all) | subagent-stop-report.sh | 5s | Observation |
| PreCompact | (all) | pre-compact.sh | 5s | Context |
| PostCompact | (all) | post-compact.sh | 5s | Context |
| TaskCompleted | (all) | task-quality-gate.sh | 5s | Gate |
| UserPromptSubmit | (all) | user-prompt-submit.sh | 5s | Context |
| SessionEnd | (all) | session-end.sh | 5s | Context |

### Indirect Call Hooks (5 helper scripts)

| Hook | Called By | Purpose |
|------|----------|---------|
| claude-update-check.sh | session-start.sh | Daily auto-update check (cached 24h) |
| worker-guard.sh | session-start.sh | Detect other active sessions via worktree heartbeat |
| mark-verified.sh | pre-commit-gate.sh | Create verification timestamp marker |
| review-complete.sh | code-review-reminder.sh | Clear pending-review marker |
| test-hooks.sh | (test suite) | Automated hook testing (not a runtime hook) |

---

## Hook Categories

### Gate Hooks (5)

Block operations when conditions are not met. Use exit 2 + stderr (PreToolUse) or JSON decision (Stop).

| Hook | Event | Blocks When |
|------|-------|-------------|
| block-destructive.sh | PreToolUse (Bash) | `rm -rf`, `git push --force`, `DROP TABLE`, etc. |
| pre-commit-gate.sh | PreToolUse (Bash) | Verification marker stale before `git commit` |
| pre-push-gate.sh | PreToolUse (Bash) | PAT token in remote URL before `git push` |
| stop-gate.sh | Stop | Code review pending (unreported file changes) |
| refinement-gate.sh | Stop | Active refinement loop in progress |

### Observation Hooks (3)

Collect data silently. Always exit 0.

| Hook | Event | Collects |
|------|-------|----------|
| error-tracker.sh | PostToolUseFailure | Tool failures → .error-log |
| subagent-start-report.sh | SubagentStart | Agent start → subagent.log |
| subagent-stop-report.sh | SubagentStop | Agent completion → subagent.log |

### Suggestion Hooks (3)

Inject reminders into context. Always exit 0.

| Hook | Event | Suggests |
|------|-------|----------|
| code-review-reminder.sh | PostToolUse (Edit\|Write) | Code review after products/ file changes |
| standards-reminder.sh | PostToolUse (Edit\|Write) | Run tests after .claude/ file changes |
| suggest-compact.sh | PostToolUse (Edit\|Write) | Compaction when tool call count exceeds threshold |

### Context Hooks (3)

Save/restore state around lifecycle events.

| Hook | Event | Action |
|------|-------|--------|
| session-start.sh | SessionStart | Inject git branch, WIP tasks, env status |
| pre-compact.sh | PreCompact | Save critical state before compaction |
| post-compact.sh | PostCompact | Restore context awareness after compaction |

### Quality Gate Hook (1)

| Hook | Event | Action |
|------|-------|--------|
| task-quality-gate.sh | TaskCompleted | Quality check on completed agent team tasks |

### Utility Scripts (4)

Called by other hooks, not registered in settings.json.

| Hook | Purpose |
|------|---------|
| claude-update-check.sh | Check for Claude Code updates (daily, cached) |
| worker-guard.sh | Detect concurrent sessions via worktree heartbeat |
| mark-verified.sh | Write `.last-verification.$branch` marker |
| review-complete.sh | Clear `.pending-review` marker |

### Test Script (1)

| Hook | Purpose |
|------|---------|
| test-hooks.sh | Automated hook testing suite (20 tests) |

---

## 22 Official Hook Events

| Event | Timing | Status | Use Case |
|-------|--------|--------|----------|
| SessionStart | Session init | Verified | Env check, WIP resume |
| UserPromptSubmit | After user sends prompt | Official | Input validation, context injection |
| PreToolUse | Before tool execution | Verified | Observation, tool blocking |
| PermissionRequest | On permission prompt | Official | Auto-approve/deny patterns |
| PostToolUse | After tool execution | Verified | Observation, result analysis |
| PostToolUseFailure | After tool failure | Verified | Error tracking |
| Notification | On notification | Official | Alert routing |
| SubagentStart | Before subagent spawn | Verified | Team coordination |
| SubagentStop | After subagent finish | Verified | Team cleanup |
| Stop | Before session end | Verified | Evolution gate, cleanup |
| StopFailure | On API/runtime error during stop | Official | Error handling |
| TeammateIdle | Teammate goes idle | Official | Team coordination |
| TaskCompleted | Task marked complete | Verified | Progress tracking |
| ConfigChange | Config file modified | Unverified | Config validation |
| WorktreeCreate | Worktree created | Unverified | Worktree setup |
| WorktreeRemove | Worktree removed | Unverified | Worktree cleanup |
| PreCompact | Before context compaction | Verified | Save state |
| PostCompact | After context compaction | Verified | State recovery |
| InstructionsLoaded | When CLAUDE.md/rules loaded | Unverified | Instruction validation |
| Elicitation | MCP requests user input | Unverified | MCP input handling |
| ElicitationResult | User responds to MCP elicitation | Unverified | MCP response processing |
| SessionEnd | Session fully ended | Unverified | Final cleanup, metrics |

Status: **Verified** = registered + tested, **Official** = documented but not registered, **Unverified** = may not exist in current runtime.

---

## Stop Event Protocol

Stop hooks use a **different JSON schema** from PreToolUse hooks:

```json
{ "decision": "block", "reason": "Human-readable explanation" }
```

| Hook Event | Blocking Schema | Example |
|------------|----------------|---------|
| PreToolUse | `{ "permissionDecision": "deny" }` + exit 2 | block-destructive.sh |
| Stop | `{ "decision": "block", "reason": "..." }` + exit 0 | stop-gate.sh |

---

## hookSpecificOutput Supported Events

| Supported | Not Supported |
|-----------|---------------|
| PreToolUse, PostToolUse, PostToolUseFailure | PreCompact, PostCompact |
| PermissionRequest, SessionStart | Stop, StopFailure |
| SubagentStart, UserPromptSubmit | SessionEnd, ConfigChange |
| Notification, Elicitation, ElicitationResult | WorktreeCreate, WorktreeRemove |
| TaskCompleted, TeammateIdle | InstructionsLoaded |

Hooks for unsupported events MUST NOT output `hookSpecificOutput` JSON.
The runtime validates `hookEventName` and rejects unrecognized values.

> **Incident**: 2026-03-21 -- PreCompact/PostCompact hooks outputting hookSpecificOutput
> caused runtime validation errors. Fixed by removing JSON output.

---

## Permitted `2>/dev/null` Patterns (P-1 through P-5)

Each usage MUST have an adjacent comment stating intent.

**P-1. Capability detection**
```bash
if command -v git &>/dev/null; then  # Intentional: graceful fallback
```

**P-2. ACTUAL_ROOT resolution**
```bash
GIT_COMMON=$(git -C "$PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null)  # Worktree resolution
```

**P-3. Honest uncertainty fallback**
```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")  # Never use 0/main/success
```

**P-4. Cross-platform compatibility**
```bash
MTIME=$(stat -c '%Y' "$F" 2>/dev/null || stat -f '%m' "$F" 2>/dev/null)  # Chain MUST NOT end with || echo 0
```

**P-5. Optional resource probing**
```bash
WIP_DIRS=$(ls -d "$ROOT"/wip/*/ 2>/dev/null)  # Resource may not exist
```

---

## Per-Category Error Handling

| Category | Exit | On Error | Example |
|----------|------|----------|---------|
| Observation | 0 always | stderr warning, continue | `echo "WARN: write failed" >&2` |
| Gate (PreToolUse) | 2 | stderr feedback, block tool | `echo "FAIL: ..." >&2; exit 2` |
| Gate (Stop) | 0 | JSON `decision: block` | `jq -n '{decision:"block",reason:"..."}'; exit 0` |
| Context-injection | 0 always | stderr warning, inject additionalContext | `echo "WARN: log failed" >&2` |
| Suggestion | 0 always | stderr warning, explicit reset | `echo "WARN: read failed" >&2; COUNT=0` |
| Utility script | set -euo pipefail | auto exit 1 on failure | `set -euo pipefail` |
| Helper script | caller's policy | errors propagate to caller | MUST NOT swallow errors |

### Prohibited Patterns

| Pattern | Violation | Replacement |
|---------|-----------|-------------|
| `cmd 2>/dev/null` (data write) | Swallows diagnostic stderr | Remove; let stderr propagate |
| `cmd \|\| true` (log write) | Disguises write failure | Use explicit error check |
| `cmd \|\| echo 0` (arithmetic) | Injects fake data | Explicit error path per category |
| `exit 0` on error state | Reports error as success | Appropriate exit code per category |

---

## Collaboration Details

### Why One Worker Per Worktree?

Git tracks changes at the working tree level. Two sessions editing the same worktree cause:
- **Unstaged change collision**: session A edits file X, session B overwrites it
- **Staging area conflict**: both sessions `git add` different versions
- **Tool call race**: Edit tool's `old_string` matching breaks on concurrent modification

If you need a second worker: create a second worktree, not a second session in the same one.

### High-Risk Files (serialize, don't parallelize)

| File | Risk | Strategy |
|------|------|----------|
| `CLAUDE.md` | HIGH | One worker at a time |
| `PROJECT.md` | HIGH | One worker at a time |
| `.claude/settings.json` | HIGH | One worker at a time |
| `.claude/agents/*.md` | MEDIUM | Declare specific agent file |
| `.claude/rules/*.md` | MEDIUM | Declare specific rule file |

### Low-Risk Files (safe to parallelize)

| File Pattern | Why Safe |
|--------------|----------|
| Independent sub-repositories | Separate git history |
| `.claude/agent-memory/` | Per-agent, no cross-reference |
| `.claude/agent-memory/` subfiles | Per-agent, append-only |
| Test files not shared across modules | Isolated by design |

### Session-Start Integration

At session start, `worker-guard` hook automatically:
1. Enumerates all worktrees via `git worktree list`
2. Checks each worktree's `.heartbeat` mtime for activity
3. Reports active sessions (within 10-minute heartbeat window)
4. Warns if current session's worktree branch diverges from main

### Merge Conflict Resolution

If `git rebase main` produces conflicts:
1. **Identify**: `git diff --name-only --diff-filter=U`
2. **Check who modified**: `git log --oneline main..HEAD -- <file>`
3. **Resolve**: prefer the more recent logical change
4. **Continue**: `git rebase --continue`
5. **Never**: `git rebase --abort` and silently drop changes

---

## DevContainer Details

### 4-Phase Testing Protocol

**Phase 1: Docker Build** (inside container)
```bash
cd /path/to/.devcontainer
docker compose build --no-cache 2>&1
docker images | grep <image-name>
docker inspect <image-name>:latest --format '{{.Config.User}}'
```

**Phase 2: Config Validation** (inside container)

| Item | Method |
|------|--------|
| settings.json | `jq . < .claude/settings.json` |
| devcontainer.json | JSONC parsing |
| docker-compose.yml | `docker compose config` |
| hooks/*.sh | `bash -n <file>` + shebang check |
| agents/*.md | YAML frontmatter parsing |
| skills/*/SKILL.md | Required fields exist |

**Phase 3: Functional Tests** (inside container)
```bash
bash .claude/hooks/test-hooks.sh
for f in .claude/hooks/*.sh; do bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"; done
```

**Phase 4: HOST Integration**

Option A -- CLI Automated (preferred):
```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . claude --version
devcontainer exec --workspace-folder . claude mcp list
devcontainer exec --workspace-folder . node --version
docker compose -p <compose-project-name> down
```

Option B -- Manual (VS Code GUI, for extension/UI testing):
1. "Reopen in Container" from HOST VS Code
2. Verify `/workspaces/` mount, postCreateCommand, extensions
3. Verify `claude --version` and MCP servers

### DinD Detection

| Symptom | Likely Cause |
|---------|-------------|
| Empty `/workspaces/` | Mount path missing in nested container |
| "Cannot find workspace" | Path resolution failure |
| Missing VS Code extensions | VS Code not connected (Option B only) |

### Agent Guidance

1. Run Phase 1-3 first, report PASS/FAIL per item
2. Run Phase 4 Option A (CLI) for automated verification
3. Fall back to Option B (manual handoff) only for VS Code extension testing:
   > "Phase 1-4A complete. VS Code extensions require manual verification: Reopen in Container from HOST."

---

*Last updated: 2026-03-28*
