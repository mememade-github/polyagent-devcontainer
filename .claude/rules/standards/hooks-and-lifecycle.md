# Hooks and Lifecycle Standard

## Source
- Official: Claude Code hooks reference (https://code.claude.com/docs/en/hooks)
- Official: Claude Code Best Practices — "Address root causes, not symptoms" (https://code.claude.com/docs/en/best-practices)
- Derived: Project observe.sh, evolution-gate.sh, error-tracker.sh patterns
- Last verified: 2026-03-21

## Standard

### Hook Types

Claude Code supports four hook types:

| Type | Execution | Use Case | Default Timeout |
|------|-----------|----------|-----------------|
| **command** | Shell command (bash) | File I/O, observations, gates | 600s |
| **prompt** | Injected into model context | Context enrichment, guidelines | 30s |
| **agent** | Spawns an agent with tools | Complex pre/post processing | 60s |
| **http** | HTTP POST to endpoint | Webhook integrations | varies |

### Hook Events (Official — 22 events)

Status: **Verified** = registered in settings.json and tested, **Official** = documented in Claude Code but not registered here, **Unverified** = may not exist in current runtime

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
| StopFailure | On API/runtime error during stop | Official | Error handling (rate_limit, auth, billing, server_error, max_output_tokens, unknown) |
| TeammateIdle | Teammate goes idle | Official | Team coordination |
| TaskCompleted | Task marked complete | Verified | Progress tracking |
| ConfigChange | Config file modified | Unverified | Config validation |
| WorktreeCreate | Worktree created | Unverified | Worktree setup |
| WorktreeRemove | Worktree removed | Unverified | Worktree cleanup |
| PreCompact | Before context compaction | Verified | Save state before compaction |
| PostCompact | After context compaction | Verified | State recovery after compaction |
| InstructionsLoaded | When CLAUDE.md/rules loaded | Unverified | Instruction validation |
| Elicitation | MCP requests user input | Unverified | MCP input handling |
| ElicitationResult | User responds to MCP elicitation | Unverified | MCP response processing |
| SessionEnd | Session fully ended | Unverified | Final cleanup, metrics |

### Hook JSON Protocol

**Common input fields** (all events receive these via stdin):
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

**Output** (exit codes — command hooks):

| Exit Code | Meaning | Effect |
|-----------|---------|--------|
| 0 | Success/allow | Tool proceeds normally |
| 2 | Block with feedback | Tool blocked, **stderr** shown to agent |
| Any other | Non-blocking error | Logged as warning, tool proceeds |

> **Note**: Exit code 1 is a non-blocking error (logged), NOT a blocking signal.
> Only exit code 2 blocks. Stderr (not stdout) is fed back to the agent on block.

**Output** (exit 0 hooks can return `hookSpecificOutput` JSON on stdout):
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

> **CRITICAL — hookSpecificOutput is NOT supported for all events.**
> Only these events accept `hookSpecificOutput` JSON:
>
> | Supported | Not Supported |
> |-----------|---------------|
> | PreToolUse, PostToolUse, PostToolUseFailure | PreCompact, PostCompact |
> | PermissionRequest, SessionStart | Stop, StopFailure |
> | SubagentStart, UserPromptSubmit | SessionEnd, ConfigChange |
> | Notification, Elicitation, ElicitationResult | WorktreeCreate, WorktreeRemove |
> | TaskCompleted, TeammateIdle | InstructionsLoaded |
>
> Hooks for unsupported events MUST NOT output `hookSpecificOutput` JSON.
> The runtime validates `hookEventName` and rejects unrecognized values,
> causing hook failure. Use only top-level fields (`async`, `statusMessage`)
> or output nothing for unsupported events.
>
> **Incident reference**: 2026-03-21 — PreCompact/PostCompact hooks outputting
> `hookSpecificOutput` with `hookEventName: "PreCompact"/"PostCompact"` caused
> runtime validation errors during context compaction. Fixed by removing JSON output.

> **CRITICAL**: Choose ONE approach per hook, not both.
> Exit 2 ignores all JSON — only stderr is read.
> JSON `permissionDecision` requires exit 0. Bug [#4669](https://github.com/anthropics/claude-code/issues/4669)
> reports `deny` being ignored in some versions. **Exit 2 + stderr is more reliable for blocking.**

**Additional JSON fields** (exit 0 only, supported for ALL events):

- **`async: true`**: Run hook in background without blocking tool execution.
- **`statusMessage`**: Custom spinner text while hook runs.

### Performance Requirements

- **Official timeouts**: 600s (command), 30s (prompt), 60s (agent)
- **Recommended**: Observation hooks should complete in < 2 seconds
  (self-imposed for latency, not an official limit)
- **No network calls** in PreToolUse/PostToolUse (latency risk)

### Worktree Compatibility

- **`bash` prefix required**: All hook commands in settings.json MUST use `bash` prefix
  (e.g., `bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/observe.sh`)
- **Reason**: `core.filemode=false` environments (9p/drvfs mounts) do not preserve
  execute permissions on git worktree checkout, causing Permission denied (exit 126)
- **`ACTUAL_ROOT` pattern**: Hooks that reference project-level resources (.env/, instincts/,
  agent-memory/) MUST resolve the actual project root via `git rev-parse --git-common-dir`
  to work correctly in worktree contexts
- **Atomic writes**: Use `printf >> file` not temp-file-rename for observations
- **Minimal dependencies**: Prefer sed/awk over jq/python for speed

### Observation Hook Requirements

Observation hooks (PreToolUse/PostToolUse) MUST record:

| Field | Required | Source | Example |
|-------|----------|--------|---------|
| `ts` | Yes | `date -u` | `2026-02-26T12:00:00Z` |
| `phase` | Yes | Hook event arg | `pre` or `post` |
| `tool` | Yes | `tool_name` from stdin | `Edit` |
| `input_summary` | Recommended | First 200 chars of `tool_input` | File path, pattern |
| `success` | Recommended | Post-phase only, error detection | `true` or `false` |

### Stop Event Protocol

Stop hooks use a **different JSON schema** from PreToolUse hooks:

```json
{
  "decision": "block",
  "reason": "Human-readable explanation of why stop is blocked"
}
```

| Field | Value | Effect |
|-------|-------|--------|
| `decision` | `"block"` | Prevents session from ending |
| `reason` | string | Shown to the agent as feedback |

> **Note**: This is distinct from the `permissionDecision` schema used by PreToolUse hooks.
> Stop hooks output `decision: "block"` (not `permissionDecision: "deny"`).
> Both schemas coexist — the hook event determines which protocol applies.

| Hook Event | Blocking Schema | Example |
|------------|----------------|---------|
| PreToolUse | `{ "permissionDecision": "deny" }` + exit code 2 | block-destructive.sh, pre-commit-gate.sh |
| Stop | `{ "decision": "block", "reason": "..." }` + exit code 0 | stop-gate.sh, evolution-gate.sh |

### Blocking vs Non-Blocking

- **Observation hooks**: Non-blocking (exit 0 always), append-only
- **Gate hooks** (evolution-gate, pre-commit): May block (exit 2, stderr feedback)
- **Suggestion hooks** (suggest-compact): Non-blocking, advisory only
- **Context-injection hooks** (code-review-reminder, error-tracker, standards-reminder): Non-blocking, inject `additionalContext` via JSON output

### Log Rotation

- Observations file: Rotate at 10MB
- Archive to `.claude/instincts/archive/observations.YYYYMMDDHHMMSS.jsonl`

## Compliance Checks

- [ ] All hooks have `#!/bin/bash` shebang
- [ ] All hooks pass `bash -n` syntax check
- [ ] Observation hooks complete in < 2 seconds (recommended)
- [ ] Observation hooks record at minimum `{ts, phase, tool}`
- [ ] Gate hooks use exit code 2 (not 1) for blocking
- [ ] Gate hooks write feedback to stderr (not stdout)
- [ ] No hook modifies files outside `.claude/` (except observation logs)
- [ ] Hook paths in settings.json match actual file locations
- [ ] Hook type (command/prompt/agent/http) appropriate for use case
- [ ] Used hook events are registered in settings.json (not all 22 required — only those with active implementations)
- [ ] Hooks outputting `hookSpecificOutput` JSON use only supported events (see table above)

## References

- https://code.claude.com/docs/en/hooks (official hooks reference)
- `.claude/hooks/*.sh` (current hook implementations)
- `.claude/settings.json` (hook registration)
