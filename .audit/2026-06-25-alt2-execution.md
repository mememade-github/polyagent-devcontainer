# Alt-2 Execution — keep-essence reorganization of the whole agent system

> **Codex re-audit erratum (2026-06-25):** the original H3 round-trip wrote a
> `.codex/state` marker directly, but did not prove that the refine resolver
> selected that path in a real Codex environment where `CODEX_PROJECT_DIR` is
> unset. It selected `.claude` and left the Codex Stop gate dead. The original
> sync proof also covered deleted top-level skills but not nested/root/type
> conflicts. Both claims are superseded by
> `2026-06-25-codex-full-component-execution-audit.md` and commits
> `eb78d0e`, `19cbb56`, and `6c61814`.

> Mandate (user, 2026-06-25): "전체 수행" of **Alt 2** — keep current elements +
> Karpathy + best-practice meta-audit, then **keep only the core and reorganize**
> (evaluator stays LLM-judgment, not a script; other scripts/hooks core-only).
> Standing constraints: **local only, no push**; **execution audit mandatory**
> ("실행 감사 필수"); verify runtime in an **external container**.
> Feasibility verdict (prior turn): Alt 2 is completable as a *closed decision
> function* (KEEP-CORE / COMPRESS / REMOVE / FIX over every element), so the
> Alt-1 fallback did not trigger.

## 1. Meta-audit — external best-practice anchors (why each KEEP is a model)

Bounded research (one authoritative source per class). All ten KEEP classes have
an external anchor; the self-generated rules do not (→ COMPRESS / bespoke note).

| Element | External anchor |
|---|---|
| Karpathy 4 rules | forrestchang/andrej-karpathy-skills (MIT); Karpathy's LLM-coding-pitfalls commentary |
| CLAUDE.md memory | Anthropic Claude Code docs — Memory (auto-loaded per-project contract) |
| Hooks (session-start, pre-commit) | Anthropic Claude Code docs — Hooks (deterministic lifecycle policy) |
| Subagents / Skills | Anthropic — Agent Skills engineering post; Agent SDK subagents |
| Pre-commit / CI gating | pre-commit.com; Pro Git "Git Hooks" |
| LLM-as-judge (evaluator) | Zheng et al., MT-Bench/Chatbot-Arena, NeurIPS 2023 (arXiv 2306.05685) |
| Iterative refinement (refine) | Self-Refine (2303.17651) + Reflexion (2303.11366), NeurIPS 2023 |
| One concern per commit | atomic-commit practice (Pro Git) — clean revert, `git bisect` |
| Least blast radius (destructive-ops) | Google SRE — partition / staged rollout |
| DevContainer, avoid DinD | devcontainers/features docker-outside-of-docker |

Weakest primary sources (honest): atomic-commit and blast-radius are consensus,
not RFCs; the Karpathy X post is attested but paywalled (the MIT repo is the firm
anchor). `audit-discipline` and `anchor-discipline` have **no** dedicated external
source — kept as bespoke guards, deliberately short.

## 2. Decision function applied (every live element, one verdict)

- **KEEP-CORE (unchanged, externally anchored or executing):** behavioral-core,
  devcontainer-patterns, karpathy-guidelines, status, wip-manager, verify (logic),
  session-start / pre-commit-gate / pre-push-gate hooks ×2, config ×3,
  completion-checker, karpathy-consistency-check, verify-template.
- **COMPRESS (body → essence; names/counts unchanged):** audit-discipline
  (103→~30), commit-discipline (59→~25, **§2 Coupling retained** — the pre-commit
  gate cites it), destructive-ops-discipline (70→~40, alternatives table kept),
  anchor-discipline (124→~22, P1+essence+P4 only), **refine (624→~135** — dropped
  wiki-integration / skill-library / scorer-evolution / reflexion layers).
- **REMOVE:** `skills/wiki` (heavy KB, not core; no executing consumer once refine
  de-wired) — pruned from the mirror by the fixed sync. (`security/` ×20 already
  removed in the prior local change set.)
- **FIX (vendor-coupling / honesty):**
  - **H1 evaluator isolation** — added a vendor-aware "Isolation mechanism" section:
    Claude = subagent context; Codex = `codex exec` subprocess fed only
    `{contract, diff}`. Honest on both; the LLM-judgment model is retained (no
    scripted evaluator — per user).
  - **H2 AGENTS.md "rules must live inline"** (false) — reworded to "not
    auto-loaded; `Read` these"; the session-start load list now names **all 6**
    rules (the 4 previously-dark rules now actually load on Codex).
  - **H3/H3b refine paths** — vendor-neutral resolver: under Codex the marker /
    attempts resolve to `.codex/state/…` (matching the Codex stop-gate), under
    Claude to `.claude/…`. The mirrored refine now drives the Codex gate.
  - **/verify invocation** — `${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git
    rev-parse --show-toplevel)}}` so the Codex mirror runs without
    `$CLAUDE_PROJECT_DIR`.
  - **Apex sync** — `sync-agents-mirror.sh` gained **deletion propagation**
    (orphan prune via dual-source check: a `.agents/skills/<X>` is legitimate iff
    `.claude/skills/<X>` or `.claude/agents/<X>.md` exists) + a **coupling guard**
    (warns on a real bare `$CLAUDE_PROJECT_DIR` expansion reaching the mirror).
  - Governance counts reconciled across CLAUDE/AGENTS/PROJECT/REFERENCE/README +
    verify-template (skills 5→4) for cross-document consistency.

## 3. Execution-audit catches (why "실행 감사 필수" mattered)

- A consumer grep without `--hidden` skipped `.claude` / `.codex` / `.agents`
  entirely. The hidden-aware re-grep then showed **`completion-checker.sh` is
  consumed by both commit gates + both /verify skills + verify-template** — it is
  the live auto-verification engine, **not** removable. Plan corrected
  REMOVE → FIX. This is the regression the execution audit prevented.
- `verify-template.sh` is the integrity oracle the commit gate runs; its assertions
  were updated in lockstep (skills 4, verify-invocation contract) so the gate stays
  green after the element-set change.

## 4. Verification (re-executed, not asserted)

Local: `sync --dry` = 0 changes · `karpathy-consistency-check` = PASS ·
`verify-template` = **59 PASS / 0 FAIL** · `bash -n` on all 8 hooks = OK ·
sync run pruned `skills/wiki` and reported **0 coupling leaks**.

**External container** (fresh `polyagent-devcontainer:latest`, working tree
streamed in, entrypoint booted):
- A. `sync --dry` = 0 · B. consistency = PASS · C. `verify-template` = **59/0**.
- D. **Codex refine marker round-trip** — wrote `.codex/state/refinement-active`
  as refine's Codex branch does; the Codex `refinement-gate.sh` read it and
  returned `decision: block` (score 0.4<0.85). H3/H3b **proven** functional (the
  gate was dead before).
- E. **/verify** resolved to `…/scripts/meta/completion-checker.sh` with
  `$CLAUDE_PROJECT_DIR` unset. Codex break fixed.

## 5. Net effect & reversibility

Staged, **local, not pushed**: 51 files, **+1688 / −3679** (~2000 fewer lines) —
the keep-essence reduction. Fully reversible via git (nothing committed). Element
set after: 6 rules (4 compressed) · 4 skills · 2 agents · 4+4 hooks · 3 config ·
4 scripts. The executing substrate is unchanged in behavior and verified green.

Residual (low): the evaluator writes its full report to a `.claude/.refine-eval.json`
path under Codex (report-only; the return value drives scoring) — left as-is.
