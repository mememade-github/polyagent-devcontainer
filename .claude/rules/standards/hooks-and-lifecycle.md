# Hooks and Lifecycle Standard

## Source
- Official: Claude Code hooks documentation (2026)
- Derived: MEMEMADE observe.sh, evolution-gate.sh patterns
- Last verified: 2026-02-26

## Standard

### Hook Events

| Event | Timing | Use Case |
|-------|--------|----------|
| SessionStart | On session init | Environment check, WIP resume, version check |
| PreToolUse | Before tool execution | Observation recording, tool blocking |
| PostToolUse | After tool execution | Observation recording, result analysis |
| Stop | Before session end | Evolution gate, cleanup, compact suggestion |
| SubagentStart | Before subagent spawn | Team coordination |
| SubagentStop | After subagent finish | Team cleanup |

### Hook JSON Protocol

**Input** (stdin): JSON object from Claude Code
```json
{
  "tool_name": "Edit",
  "tool_input": {"file_path": "...", "old_string": "...", "new_string": "..."}
}
```

**Output** (exit codes):
| Exit Code | Meaning | Effect |
|-----------|---------|--------|
| 0 | Success/allow | Tool proceeds normally |
| 1 | Error | Logged, tool proceeds |
| 2 | Block with feedback | Tool blocked, stdout shown to agent |

### Performance Requirements

- **Timeout**: All hooks MUST complete within 2 seconds
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

### Blocking vs Non-Blocking

- **Observation hooks**: Non-blocking (exit 0 always), append-only
- **Gate hooks** (evolution-gate, pre-commit): May block (exit 2)
- **Suggestion hooks** (suggest-compact): Non-blocking, advisory only

### Log Rotation

- Observations file: Rotate at 10MB
- Archive to `.claude/instincts/archive/observations.YYYYMMDDHHMMSS.jsonl`

## Compliance Checks

- [ ] All hooks have `#!/bin/bash` shebang
- [ ] All hooks pass `bash -n` syntax check
- [ ] Observation hooks complete in < 2 seconds
- [ ] Observation hooks record at minimum `{ts, phase, tool}`
- [ ] Gate hooks use exit code 2 (not 1) for blocking
- [ ] No hook modifies files outside `.claude/` (except observation logs)
- [ ] Hook paths in settings.json match actual file locations

## References

- `.claude/hooks/*.sh` (current hook implementations)
- `.claude/settings.json` (hook registration)
