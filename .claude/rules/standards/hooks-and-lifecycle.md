# Hooks and Lifecycle Standard

## Source
- Official: Claude Code hooks reference (https://code.claude.com/docs/en/hooks)
- Official: Claude Code Best Practices — "Address root causes, not symptoms" (https://code.claude.com/docs/en/best-practices)
- Derived: Project observe.sh, evolution-gate.sh, error-tracker.sh patterns
- Last verified: 2026-02-26

## Standard

### Hook Types

Claude Code supports three hook types:

| Type | Execution | Use Case | Default Timeout |
|------|-----------|----------|-----------------|
| **command** | Shell command (bash) | File I/O, observations, gates | 600s |
| **prompt** | Injected into model context | Context enrichment, guidelines | 30s |
| **agent** | Spawns an agent with tools | Complex pre/post processing | 60s |

### Hook Events (Official — 17 events)

| Event | Timing | Input Fields (beyond common) | Use Case |
|-------|--------|------------------------------|----------|
| SessionStart | Session init | — | Env check, WIP resume |
| UserPromptSubmit | After user sends prompt | user_message | Input validation, context injection |
| PreToolUse | Before tool execution | tool_name, tool_input | Observation, tool blocking |
| PermissionRequest | On permission prompt | tool_name, tool_input, permission_type | Auto-approve/deny patterns |
| PostToolUse | After tool execution | tool_name, tool_input, tool_response | Observation, result analysis |
| PostToolUseFailure | After tool failure | tool_name, tool_input, error | Error tracking |
| Notification | On notification | title, message | Alert routing |
| SubagentStart | Before subagent spawn | agent_name, agent_type | Team coordination |
| SubagentStop | After subagent finish | agent_name, agent_type | Team cleanup |
| Stop | Before session end | stop_reason | Evolution gate, cleanup |
| TeammateIdle | Teammate goes idle | teammate_name | Team coordination |
| TaskCompleted | Task marked complete | task_id | Progress tracking |
| ConfigChange | Config file modified | config_path | Config validation |
| WorktreeCreate | Worktree created | worktree_path, branch | Worktree setup |
| WorktreeRemove | Worktree removed | worktree_path | Worktree cleanup |
| PreCompact | Before context compaction | — | Save state before compaction |
| SessionEnd | Session fully ended | — | Final cleanup, metrics |

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

**Output** (command hooks can also return JSON on stdout):
```json
{
  "hookSpecificOutput": "string shown in hook output",
  "permissionDecision": "allow|deny|ask"
}
```

### Performance Requirements

- **Official timeouts**: 600s (command), 30s (prompt), 60s (agent)
- **Recommended**: Observation hooks should complete in < 2 seconds
  (self-imposed for latency, not an official limit)
- **No network calls** in PreToolUse/PostToolUse (latency risk)
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
- [ ] Hook type (command/prompt/agent) appropriate for use case

## References

- https://code.claude.com/docs/en/hooks (official hooks reference)
- `.claude/hooks/*.sh` (current hook implementations)
- `.claude/settings.json` (hook registration)
