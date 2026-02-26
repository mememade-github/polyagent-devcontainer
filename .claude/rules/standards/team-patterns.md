# Team Patterns Standard

## Source
- Official: Claude Code Agent Teams documentation (2026)
- Derived: MEMEMADE team delegation patterns
- Last verified: 2026-02-26

## Standard

### Team Sizing

- **Optimal**: 3-5 members per team
- **Maximum**: 7 members (communication overhead grows quadratically)
- **Pattern**: 1 leader + N specialists

### Team Lifecycle

```
TeamCreate (at first delegation need)
    |
    v
TaskCreate → TaskUpdate (assign to teammates)
    |
    v
Work (teammates execute in parallel)
    |
    v
SendMessage type: "shutdown_request" (to each teammate)
    |
    v
TeamDelete (cleanup — MANDATORY)
```

- Teams MUST NOT persist between tasks
- Create team when first agent delegation is needed
- Delete team after all agents complete work
- Never leave orphaned teams running

### Model Selection for Teammates

| Complexity | Model | Use Case |
|------------|-------|----------|
| Complex reasoning | opus | Architecture review, evolution, deep code analysis |
| Standard tasks | sonnet | Documentation, WIP management, general review |
| Quick/simple | haiku | Build fixes, environment checks, diagnostics |

### Subagent Type Mapping

- `subagent_type` should match the agent name in `.claude/agents/`
- Custom agents defined in `.claude/agents/` are available as subagent types
- Built-in types: `general-purpose`, `Explore`, `Plan` (always available)

### Task Assignment

- One task per member at a time
- Use TaskUpdate with `owner` to assign
- Prefer task ID order (lowest first) for sequential context
- Blocked tasks: resolve blockers before assignment

### Communication Protocol

- Use `SendMessage` for all inter-agent communication
- Plain text messages, not structured JSON
- `broadcast` only for critical team-wide issues
- Teammates go idle between turns (normal, not an error)

## Compliance Checks

- [ ] Teams are created with `TeamCreate` before spawning teammates
- [ ] Teams are deleted with `TeamDelete` after work completes
- [ ] No team persists across sessions without WIP tracking
- [ ] Teammate model matches task complexity
- [ ] Each teammate has exactly one active task

## References

- `.claude/settings.json` (team configuration)
- CLAUDE.md Agent Teams Delegation section
