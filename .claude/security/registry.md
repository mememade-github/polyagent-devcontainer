# Skill / Agent Registry

> Phase 4. Anchored in Karpathy R1.4 Goal-Driven Execution.
> Anthropic enterprise §"내부 레지스트리": purpose / owner / version / dependencies / evaluation status.

## Lifecycle states (Anthropic 6-stage)

`draft` → `reviewed` → `tested` → `active` → (`deprecated` | `retired`)

Transitions:

- **draft → reviewed**: code review passed (Anthropic checklist 8 items run).
- **reviewed → tested**: eval suite (`eval-suites/<name>.md`) executed and passed.
- **tested → active**: deployed via sync to all `.claude/` Full-copy receivers.
- **active → deprecated**: replacement chosen or workflow retired; entry kept for one cycle.
- **deprecated → retired**: removed from system.

Skip protocol: an iteration on an already-`active` component (frontmatter or body change) drops it back to `reviewed` until eval suite re-runs.

## Registry table

| Component | Purpose | Owner | Version | Dependencies | Last reviewed | Eval status | State |
|-----------|---------|-------|---------|--------------|---------------|-------------|-------|
| skills/refine | Autonomous exploratory improvement loop | Template maintainer | 1.0.0 | evaluator agent; `Agent` tool; per-project `score.sh` | 2026-04-28 | suite written, manual run pending | `reviewed` |
| skills/wiki | Cross-document knowledge base build / query / lint | Template maintainer | 1.0.0 | `Agent` tool | 2026-04-28 | suite written, manual run pending | `reviewed` |
| skills/status | Workspace-wide health snapshot | Template maintainer | 1.0.0 | `scripts/git/git-status.sh`, Docker daemon | 2026-04-28 | suite written, manual run pending | `reviewed` |
| skills/verify | Pre-commit verification dispatcher | Template maintainer | 1.0.0 | `scripts/meta/completion-checker.sh`, `pre-commit-gate.sh` | 2026-04-28 | suite written, manual run pending | `reviewed` |
| skills/karpathy-guidelines | Karpathy 4-rule reference handle (read-only prompt text) | forrestchang (upstream); Template maintainer (mirror) | 1.0.0 | none — no tools, no callees | 2026-04-30 | upstream-aligned (verbatim); no eval suite required | `active` |
| agents/evaluator | 1-pass review / `/refine` iteration scorer | Template maintainer | 1.0.0 | invoked by ROOT or `/refine`; no callees | 2026-04-28 | suite written, manual run pending | `reviewed` |
| agents/wip-manager | Multi-session task state author/resumer | Template maintainer | 1.0.0 | `wip/` directory; invoked by ROOT | 2026-04-28 | suite written, manual run pending | `reviewed` |

Hooks are *enforcement* code, not skills/agents. They are governed by
`trust-boundary.md` (rows 3–8) and tested via `tests/run.sh` patterns
in sub-projects that inherit them. They are not listed here per
Anthropic's split between skills (LLM-triggered) and runtime hooks.

## Versioning

- **Patch (1.0.x)**: SKILL.md / agent.md body wording change, no frontmatter or behavior change.
- **Minor (1.x.0)**: frontmatter field added or eval suite expanded; backwards-compatible behavior change.
- **Major (x.0.0)**: tools list change, scope change, or breaking behavior change.

A version bump on an `active` component triggers the skip protocol — state
returns to `reviewed` until the eval suite is re-run on the new version.

## Update protocol

Edit this registry whenever:

1. A new skill/agent is added (insert row, state `draft`).
2. A component is modified (bump version, update `Last reviewed`, drop state to `reviewed`).
3. An eval-suite run completes (set `Eval status` to result, advance state).
4. A component is deprecated or retired (update state).

The `Last reviewed` field is the date of the most recent state-changing edit
to the component itself OR to its eval-suite OR to its `risk-registry.md`
row — whichever is latest.

## Re-eval cadence (documentation only — no automation)

Component-code changes are already handled by the skip protocol (`active → reviewed`
on frontmatter/body edit). The following triggers cover the remaining cases where
an `active` component should be re-evaluated despite no local change:

- the upstream Anthropic enterprise checklist is updated → re-run all eval suites;
- a component's eval suite is modified → re-run that suite;
- `Last reviewed` is older than 12 months → re-run (fallback; the 12-month figure
  is heuristic, chosen to prevent indefinite staleness without prescribing tight
  cadence on rarely-changing components).

Automation (cron, CI scheduler) is intentionally out of scope for this registry;
the cadence is a manual operations guideline. Carries AUD-2026-025.

## Verification — end-state for Phase 4

```bash
# Auto-detects the current project root; override with PROJECT_ROOT=<path>
# when running from outside the receiver's tree. Row count baseline = 7
# (5 skills + 2 agents); receivers with own architecture (e.g. CAESAR
# learning agents) may declare higher counts in their own registry.
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
rows=$(awk '/^\| skills\/|^\| agents\//{c++} END{print c}' "$PROJECT_ROOT/.claude/security/registry.md")
[ "$rows" -ge 7 ] && echo "PASS (rows=$rows)" || echo "FAIL (expected >=7, got $rows)"
```

---

*Created: 2026-04-28. Phase 4 of Alt B (karpathy-skills aligned).*
