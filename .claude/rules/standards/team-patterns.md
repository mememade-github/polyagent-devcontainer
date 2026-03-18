# Team Patterns Standard

## Source
- Official: Claude Code Agent Teams documentation (https://code.claude.com/docs/en/agent-teams)
- Derived: Team delegation patterns
- Last verified: 2026-03-19

## Standard

### Status

> Agent Teams is an **experimental** feature (as of 2026-02).
> APIs and behavior may change. Monitor official docs for updates.

### Team Sizing

- **Optimal**: 3-5 members per team
- **Task density**: 5-6 tasks per teammate for efficiency
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

### Team-Related Hook Events

| Hook Event | Trigger | Use Case |
|------------|---------|----------|
| SubagentStart | Before teammate spawns | Resource tracking |
| SubagentStop | After teammate finishes | Cleanup |
| TeammateIdle | Teammate goes idle between turns | Work assignment |
| TaskCompleted | Task marked complete | Progress tracking |

> These events can be handled by hooks in settings.json for automated team coordination.

### Model Selection for Teammates

| Model | Use For | Note |
|-------|---------|------|
| opus | ALL agents | 프로젝트 특수 지침: 모든 Agent는 최상위 모델 사용 (2026-03-19) |

> 이 워크스페이스는 모든 Agent에 opus 모델을 사용합니다. 공식 문서의 복잡도별 모델 선택 가이드를 override합니다.

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

### Display Modes

Teammates display their work in the CLI:

| Mode | Description |
|------|-------------|
| Inline | Shows agent output in main terminal (default for few agents) |
| Background | Shows notification on completion (for parallel work) |

## Compliance Checks

- [ ] Teams are created with `TeamCreate` before spawning teammates
- [ ] Teams are deleted with `TeamDelete` after work completes
- [ ] No team persists across sessions without WIP tracking
- [ ] Teammate model matches task complexity
- [ ] Each teammate has exactly one active task
- [ ] TeammateIdle/TaskCompleted hooks considered for coordination

## References

- https://code.claude.com/docs/en/agent-teams (official teams reference)
- `.claude/settings.json` (team configuration)
- CLAUDE.md Agent Teams Delegation section
