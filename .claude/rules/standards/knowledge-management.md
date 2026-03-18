# Knowledge Management Standard

## Source
- Official: Claude Code CLAUDE.md documentation (2026)
- Community: claude-code-tips, ECC patterns
- Last verified: 2026-02-26

## Standard

### CLAUDE.md (Project Instructions)

- **Location**: Repository root (`/CLAUDE.md`)
- **Size**: 150-200 lines maximum (loaded into every session context)
- **Required sections**:
  - Identity (workspace name, environment)
  - Project structure (tree overview)
  - Core principles (integrity, destructive ops)
  - Automated workflow (hooks, agents, gates)
  - Coding rules (concise)
  - Communication preferences
  - Environment specifics

### Per-Agent Memory

- **Location**: `.claude/agent-memory/<agent-name>/MEMORY.md`
- **Behavior**: First 200 lines injected into agent system prompt
- **Content**: Cross-session learnings, evolution history, known patterns
- **Updates**: Agent writes own memory at end of meaningful sessions
- **Size**: Keep under 200 lines for system prompt injection

### Rules (`.claude/rules/`)

| Type | Location | Scope | Loaded |
|------|----------|-------|--------|
| Portable | `.claude/rules/*.md` | All projects (Tier 1) | Auto, every session |
| Project-specific | `.claude/rules/project/*.md` | This project only | Auto, every session |
| Standards | `.claude/rules/standards/*.md` | Reference knowledge | Auto, every session |

- Rules are auto-loaded into system prompt — keep concise
- Budget guidelines:
  - Portable rules (`.claude/rules/*.md`): aim for < 300 lines
  - Project rules (`.claude/rules/project/*.md`): aim for < 200 lines
  - Standards (`.claude/rules/standards/*.md`): aim for < 700 lines (reference material)
  - **Total**: aim for < 1200 lines across all rule files
- Each rule file should have a clear, single topic

### Skills (`.claude/skills/`)

- **Location**: `.claude/skills/<skill-name>/SKILL.md`
- **Auto-load**: By context match (skill description matches user intent)
- **User-invocable**: Via `/<skill-name>` if `user-invocable: true` in frontmatter
- **Required frontmatter**:
  ```yaml
  ---
  name: skill-name
  description: What this skill does
  user-invocable: true|false
  ---
  ```

### Instincts (`.claude/instincts/`)

- **Observations**: `observations.jsonl` — hook-recorded tool usage
- **Personal**: `personal/*.md` — learned patterns with confidence scores
- **Inherited**: `inherited/*.md` — imported from external sources
- **Archive**: `archive/` — decayed instincts (confidence < 0.2)
- **Not in Tier 1**: Domain-specific, not copied to templates

### Knowledge Hierarchy

```
CLAUDE.md (immutable principles, loaded first)
    |
    v
.claude/rules/ (portable standards, auto-loaded)
    |
    v
.claude/rules/project/ (project-specific, auto-loaded)
    |
    v
.claude/skills/ (on-demand, context-matched)
    |
    v
.claude/instincts/ (learned, confidence-gated)
    |
    v
.claude/agent-memory/ (per-agent, session-injected)
```

### Cross-Project Synchronization

Portable `.claude/` artifacts (standards, skills, hooks, agents) are distributed as copies
to sub-projects. When modifying portable files in the ROOT workspace, **all copies MUST be
synchronized in the same commit/session**.

**Sync protocol**:
1. Modify portable files in ROOT (`.claude/rules/standards/`, `.claude/skills/`, `.claude/hooks/`, `.claude/agents/`)
2. Identify all sub-projects with `.claude/` copies (see distribution map below)
3. Copy changed files from ROOT → each sub-project
4. Verify zero divergence across all copies
5. Commit and push each affected repository

**Distribution map** (maintained in ROOT `PROJECT.md`):
- ROOT `PROJECT.md` documents which sub-projects have `.claude/` copies
- Each sub-project may have project-specific additions (`.claude/rules/project/`)
- Project-specific files are NOT synchronized — only portable files

**What syncs** (ROOT → sub-projects):
- `.claude/rules/standards/*.md` — all files
- `.claude/skills/*/SKILL.md` — all files
- `.claude/hooks/*.sh` — all files
- `.claude/agents/*.md` — all files (excluding `_archive/`)
- `.claude/settings.json` — when hook registrations change

**What does NOT sync**:
- `.claude/rules/project/*.md` — project-specific, may differ
- `.claude/agent-memory/` — per-project learning data
- `.claude/instincts/` — domain-specific observations

## Compliance Checks

- [ ] CLAUDE.md exists at repository root
- [ ] CLAUDE.md is under 200 lines
- [ ] Each agent with `memory: project` has a MEMORY.md
- [ ] Rule files are concise and single-topic
- [ ] Skills have SKILL.md with required frontmatter
- [ ] No project-specific content in portable rules
- [ ] Instincts directory structure: personal/, inherited/, archive/

## References

- `/workspaces/CLAUDE.md` (current project instructions)
- `.claude/rules/*.md` (current rules)
- `.claude/skills/*/SKILL.md` (current skills)
