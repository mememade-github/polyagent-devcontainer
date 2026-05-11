# Risk Registry

> Phase 1. Anchored in Karpathy R1.1 Think Before Coding (surface assumptions
> as data) and R1.4 Goal-Driven Execution (verifiable cell coverage).
> Companion to `trust-boundary.md`. Cell values are direct measurements,
> not inferences.

## Cell value vocabulary

| Value | Meaning |
|-------|---------|
| `clean` | Dimension does not apply or no occurrence in source. |
| `declared` | Declared in frontmatter / config; no actual exercise observed in body. |
| `doc-ref` | Mentioned in documentation/comments only (e.g. URL in a "see also" link). Not invoked at runtime. |
| `active` | Exercised at runtime as part of normal operation. |
| `enforced` | Active by design as the component's primary security purpose. |

## Axis definitions (Anthropic enterprise §위험 등급)

| # | Axis | Detection method |
|---|------|------------------|
| A1 | code execution (script in skill/agent dir) | `find ... -name "*.py" -o -name "*.sh" -o -name "*.js"` |
| A2 | command manipulation (safety-rule override / action-hiding / exfil-via-response / input-conditional behavior) | manual read; grep for "ignore previous", "do not tell", base64 |
| A3 | MCP references | `grep -E "mcp__\|ServerName:"` |
| A4 | network access | `grep -E "https?://\|curl\|wget\|fetch\(\|requests\.\|urllib\|WebSearch\|WebFetch"` |
| A5 | hardcoded credentials | `grep -E "PAT[= ][a-zA-Z0-9]\|TOKEN[= ][a-zA-Z0-9]\|api[_-]key[= ][a-zA-Z0-9]"` (manual disambiguation of false positives) |
| A6 | file-system scope | declared write paths + observed write paths in body |
| A7 | tool invocations (Bash / Edit / Agent) | frontmatter tools field + body grep |

---

## Registry — 11 components × 7 axes

| # | Component | A1 code | A2 manip | A3 MCP | A4 net | A5 cred | A6 fs scope | A7 tools |
|---|-----------|---------|----------|--------|--------|---------|-------------|----------|
| 1 | agents/evaluator.md | clean | clean | clean | declared | clean | task-scoped | active (Bash, Edit, Write, Read, Grep, Glob) |
| 2 | agents/wip-manager.md | clean | clean | clean | declared | clean | `wip/` + task-scoped | active (Bash, Edit, Write, Read, Grep, Glob) |
| 3 | hooks/session-start.sh | enforced | clean | clean | clean | clean | read-only (`.git/`, `wip/`, MEMORY.md) | active (shell, jq, git) |
| 4 | hooks/pre-commit-gate.sh | enforced | clean | clean | clean | clean | `.last-verification.<branch>` read | active (shell) |
| 5 | hooks/pre-push-gate.sh | enforced | clean | clean | clean | enforced (Layer 1: PAT residue block) | git-remote read | active (shell, git, grep) |
| 6 | hooks/refinement-gate.sh | enforced | clean | clean | clean | clean | `.refinement-active`, score files | active (shell, jq) |
| 7 | skills/refine/SKILL.md | clean | clean | clean | clean | clean | task-scoped + `.refinement-active`, attempts/ | active (Bash, Edit, Write, Read, Grep, Glob, **Agent**) |
| 8 | skills/wiki/SKILL.md | clean | clean | clean | doc-ref (Karpathy gist link) | clean | wiki source/output | active (Bash, Edit, Write, Read, Grep, Glob, **Agent**) |
| 9 | skills/status/SKILL.md | clean | clean | clean | clean | clean | read-only (`.git/`, ports) | active (Bash, Read, Grep, Glob) |
| 10 | skills/verify/SKILL.md | clean | clean | clean | clean | clean | read + `.last-verification` write | active (Bash, Read) |
| 11 | skills/karpathy-guidelines/SKILL.md | clean | clean | clean | clean | clean | own dir (`SKILL.md` + `EXAMPLES.md`) read-only | clean (no `tools` field — reference handle) |

## Cell-by-cell justifications (non-`clean` only)

### A1 (code execution)
- Hooks 3-6 carry `enforced` because they ARE `.sh` scripts — that is the component's purpose, not a violation. Karpathy R1.3 Surgical: leave functioning safety code untouched.

### A2 (command manipulation)
- All `clean`. Manual read of all 11 component bodies revealed no instruction to override safety, hide actions, exfiltrate via response, or conditionally change behavior on input. Re-verify whenever a component is modified.

### A3 (MCP references)
- All `clean`. Detection grep returns 0 across `.claude/agents/` and `.claude/skills/`.

### A4 (network access)
- evaluator / wip-manager: `declared` — `WebSearch` and `WebFetch` are listed in their `tools` field but no body invocation pattern (`http`, `fetch`, `curl`) appears. Capability is reserved, not exercised.
- wiki: `doc-ref` — single `https://gist.github.com/karpathy/...` link in the description, no network-call instruction.

### A5 (hardcoded credentials)
- All `clean` after disambiguation. Earlier broad grep produced false positives on substrings like `PATH`, `WT_PATH`, `--max-iter PATH` — none are credential references. The phrase "credential" appears in `pre-push-gate.sh` only as Layer-1 detection logic (the hook **searches for** PATs in remote URLs to block them).
- pre-push-gate Layer 1 is marked `enforced` along axis A5: it is the runtime check that PAT residue not appear in `git push` remote URLs.

### A6 (file-system scope)
- Agents: scope determined by caller's task. Evaluator may read/write any path the caller requests; wip-manager additionally owns `wip/`.
- Skills/refine: writes own marker (`.refinement-active`), output (`.refine-output`), and per-iteration log (`attempts/*.jsonl`). Otherwise scope is task-bound.
- Skills/wiki: writes inside the wiki source/output directories supplied as args.
- Skills/status: read-only (`.git/`, port checks). No write.
- Skills/verify: read + writes a single marker file `.last-verification.<branch>`.
- Skills/karpathy-guidelines: read-only of own directory (`SKILL.md` + `EXAMPLES.md`). No writes. Karpathy upstream verbatim.
- Hooks: each hook's scope is hook-input + the specific marker / git output it consults; none of them write to source.

### A7 (tool invocations)
- agents/evaluator, wip-manager: full standard toolkit including `Edit`/`Write`/`Bash`. No `Agent` (do not delegate further).
- skills/refine, wiki: full toolkit **including `Agent`** — by design recursive (refine spawns evaluator; wiki spawns ingestion sub-agents). Highest autonomy by intent.
- skills/status: read-only toolkit.
- skills/verify: narrowest (`Bash, Read`).
- skills/karpathy-guidelines: **clean** — no `tools` field declared in frontmatter. Reference handle invoked via `Read` by other agents/skills. Closest to Karpathy upstream baseline.

---

## Comparison — karpathy-skills baseline vs ours

| Axis | karpathy-skills | This system |
|------|-----------------|-------------|
| A1 code | `clean` | `enforced` (hooks) + script-free skills/agents |
| A2 manip | `clean` | `clean` |
| A3 MCP | `clean` | `clean` |
| A4 net | `clean` | `declared` (2 agents) + `doc-ref` (1 skill) |
| A5 cred | `clean` | `clean` for skills/agents; `enforced` (pre-push Layer 1) |
| A6 fs scope | bounded to skill dir | task-bounded (skills/agents) + tightly scoped (hooks) |
| A7 tools | `clean` | `active` everywhere — by design (this is an agentic system, not a single guideline skill) |

The system inherits the structural simplicity of karpathy-skills inside each
*content* file (no scripts in skills, no MCP, no hardcoded secrets, no manipulation
patterns) while extending capability along A1 (hooks), A4 (declared), A6 (task-bound),
and A7 (toolkit). Each extension is recorded in `trust-boundary.md` with a written
justification — Karpathy R1.1 satisfied.

## When to update

Update this registry whenever a component is added, removed, or modified —
specifically when frontmatter `tools` field changes or a new script is
introduced. Update protocol: re-run the detection commands of §"Axis definitions"
on the changed component, edit the affected row, and re-verify the integrity
check below.

## Verification — end-state for Phase 1

```bash
# Cell coverage: 11 components × 7 axes = 77 cells
rows=$(grep -cE '^\| [0-9]+ \|' /workspaces/.claude/security/risk-registry.md)
[ "$rows" -eq 11 ] && echo "OK (rows=$rows)" || echo "FAIL (expected 11, got $rows)"
```

Component-list parity with `trust-boundary.md` is implicit by manual review
(both documents reference the same 11 entities).

---

*Created: 2026-04-28. Phase 1 of Alt B (karpathy-skills aligned).*
