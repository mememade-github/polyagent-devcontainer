# Sentence-Level Karpathy Essence Audit — Full Agent System (2026-06-25)

> Mandate (user, verbatim Turn 1): "전체 Agent 시스템 - 당신/코덱스 구성 비교
> !실제 본문 내용 기반! andrej-karpathy-skills 기준에 따라 전체 구성요소의
> 본질을 감사." + (2026-06-25) "전체 요소 … 기존 의미없는 스크립팅등은 제거."
> Method: 4 parallel sentence-level audit agents (each quoting body text +
> re-executing claims), consolidated here, then evaluator §4 cross-check.
> Standard: Karpathy R1 Think / R2 Simplicity / R3 Surgical / R4 Goal(+INTEGRITY).

## Scope — full element universe (nothing subset)

| Group | Elements | Method |
|-------|----------|--------|
| Governance | CLAUDE.md, AGENTS.md, PROJECT.md, REFERENCE.md | sentence + cross-doc consistency + re-exec counts |
| Rules ×6 | behavioral-core, audit, commit, destructive-ops, anchor, devcontainer (+`.agents/` mirror) | self-compliance + Codex activation + diff |
| Skills ×5 + Agents ×2 | refine, status, verify, wiki, karpathy-guidelines + evaluator, wip-manager (+mirror) | execution-model parity + path-binding + diff |
| Hooks ×4+4, settings/config ×3, scripts ×4, devcontainer ×3 | all Claude+Codex hooks, settings.json, config.toml, hooks.json, sync/checker/karpathy/git-status, verify-template/entrypoint/setup-env | **re-execution** + path-binding + parity |
| security ×10 | (removed this session — see 2026-06-25-security-framework-removal.md) | audited → deleted (INTEGRITY self-violation) |

## Thesis (the essence)

**Byte-perfect mirror (Layer 1) masks systematic semantic breakage (Layer 2)
on Codex.** The mirror faithfully copies *words that are false or dead in
their Codex home*, while the *executable* layer (hooks/scripts) is sound.
Breakage concentrates exactly where text asserts a semantic property that
execution would falsify — but nothing executes it.

- 3 of the 4 mirror skill/agent diffs are **byte-IDENTICAL** to ground truth,
  yet carry guarantees Codex structurally cannot honor.
- The hook/script layer was **re-executed**: 59 PASS / 0 FAIL, every gate
  blocks, cross-vendor leak grep clean both ways. The code works.
- Therefore the failure mode is **not** broken code — it is **unverified
  prose mirrored into a context where it is untrue** (an R4/INTEGRITY class).

## 3-layer verdict (confirmed sentence-level)

- **Layer 1 — text/byte parity: PERFECT** (all 6 rules + 4 skills + 2 agent
  conversions diff IDENTICAL).
- **Layer 2 — semantic/essence parity: SYSTEMATICALLY DEGRADED** (evaluator
  isolation false; 4/6 rules dark; refine paths/markers/agent-spawn dead on
  Codex).
- **Layer 3 — Karpathy self-compliance: MIXED** (behavioral-core exemplary
  with a real oracle; anchor-discipline self-violates R2; security/ INTEGRITY
  self-violation — now removed).

## Consolidated findings (severity-ranked)

### FAIL (INTEGRITY / hard)

| id | file:line | quoted text | rule | evidence |
|----|-----------|-------------|------|----------|
| H1 | `.agents/skills/evaluator/SKILL.md:14,56-59` | "You never see the generator's reasoning or task intent" | R4/INTEGRITY | byte-identical to Claude agent, but `AGENTS.md:125` "No sub-agent isolation" + `.agents/agents/` absent → in-context skill = self-evaluation, which `AGENTS.md:59` forbids ("Never self-evaluate") |
| H2 | `AGENTS.md:3` | "all behavioral rules must live inline here" | R4 | false: grep P1-P6/"counter-test"/"filter-repo" in AGENTS.md = 0; only behavioral-core+devcontainer referenced (`:144-145`); 4/6 rule bodies neither inlined nor referenced |
| H2b | `AGENTS.md:7` | "Load explicitly with the Read tool at session start" | R4 | `.codex/hooks/session-start.sh` injects branch/WIP/env only — loads no rule; depends on model voluntarily acting on prose |
| H3 | `.agents/skills/refine/SKILL.md:63` | `PROJECT="${PROJECT:-$CLAUDE_PROJECT_DIR}"` | R3/R4 | Codex sets `$CODEX_PROJECT_DIR` (hooks prove it); `$CLAUDE_PROJECT_DIR` unset → empty path |
| H3b | `.agents/skills/refine/SKILL.md:56,111,394` | `.claude/.refinement-active` create/check/rm | R3/R4 | `refinement-gate.sh:23` gates on `.codex/state/refinement-active` → marker mismatch → **Codex refine gate never fires (dead gate)** |
| H3c | `.agents/skills/refine/SKILL.md:234,618` | "Spawn the `evaluator` agent"; "Portable with `.claude/`" | R3/R4 | `.agents/agents/` does not exist — no spawnable Codex agent; mirror still says `.claude/` |
| R2-self | `anchor-discipline.md` (whole, 779w) | "Minimum code… Nothing speculative" (the R2 it cites) | R2 | heaviest rule (779w vs 221 median): P1-P6 + counter-test + primary/process split, for a workflow with **zero in-repo invocation** — most violates the Simplicity it espouses |

### WARN

| id | file:line | issue | rule |
|----|-----------|-------|------|
| W1 | `CLAUDE.md:17` | "AGENTS.md … delta only" — stale; AGENTS.md is fully self-contained (its own `:3`) | R4 |
| W2 | `.agents/skills/verify/SKILL.md:26` | `$CLAUDE_PROJECT_DIR/scripts/...` no fallback → broken path under Codex (status `:15` has `git rev-parse` fallback → degrades gracefully) | R3 |
| W3 | `refine/SKILL.md:298-385,402-451` | wiki-authoring + scorer-evolution (~120 of 623 ln) embedded in a "thin orchestrator" — independently revertable scope-creep | R2/R3 |
| W4 | `completion-checker.sh:13,29-30` | hardcodes `.claude/`, ignores `$CODEX_PROJECT_DIR`; **re-exec proven** to write `.claude/.last-verification.main` with no `CLAUDE_PROJECT_DIR` set → Codex run litters `.claude/` (gitignored; Codex gate writes own `.codex/state` marker, so gate not broken) | R3 |
| W5 | `anchor-discipline.md:101-105` | "termination conditions" framed executable but are human-judged prose (vs behavioral-core's scripted, re-run-proven oracle) | R4 |

### NOTE

| id | file:line | issue | rule |
|----|-----------|-------|------|
| N1 | `audit-discipline.md:88`, `anchor-discipline.md:107` | `AUD-2026-008/010` defined only in the citing file — circular self-minted authority (AUD-018 excepted: real script) | R4 |
| N2 | `anchor-discipline.md:16,71` | "default 80%", "default 5" magic-numbers with no consumer — configurability not requested | R2 |
| N3 | `devcontainer-patterns.md:8` | "this is NOT DinD" stated flat; REFERENCE.md frames same docker.sock as host-root — co-locate the privilege caveat | R1 |
| N4 | `CLAUDE.md:51` | /refine WARNING claim omits its precondition (`.refine/score.sh` must exist) | R4 |
| N5 | `refine/SKILL.md:11,618` | "thin orchestrator" / "self-contained" — true on Claude, false in mirror | R2/R4 |
| N6 | `session-start.sh:7` | dead `SOURCE` var (Codex variant uses its own) | R2 |
| N7 | `.codex/hooks/pre-push-gate.sh:48` | baseline write `printf > FILE` no failure guard (Claude twin warns) | R4 |
| N8 | `.codex/hooks/refinement-gate.sh:11` | `mkdir` side-effect before marker check (Claude returns early) | R2/R3 |

## What is NOT a problem (false-alarm clearances, by execution)

- `pre-commit-gate.sh:78` `[ -x ] || [ -f ]` — **load-bearing** on 9p mounts
  (scripts are mode 0644), not redundant. Correct defensive design.
- Secret regex `ghp_[A-Za-z0-9]{36}` — boundary-tested (35 no-match, 36/37/40
  match); real PATs ≥36 → no under-match. Sound.
- Hook parity — Codex gates parse 4 command-field shapes vs Claude's 1, and
  resolve root via `git rev-parse`; correct vendor adaptation, not breakage.
- Cross-vendor path leak — grep clean both ways for the *hooks* (only the
  *shared* `completion-checker.sh` leaks, W4).
- All scripts function: `verify-template` 59/0, `karpathy-check` PASS, `sync
  --dry` 0-change. **No meaningless/non-functioning script remains** after the
  security/ removal — confirming that removal's scope was complete.

## Negative space (declared exclusions)

Not audited: live `git commit`/`push` end-to-end; Codex CLI's *runtime*
honoring of `hooks.json` (only the scripts, not the dispatcher); Dockerfile /
docker-compose.yml / devcontainer.json; prose/style beyond R1-R4; `.audit/*`
contents; non-`main` branch + concurrent-session marker races; whether Claude
honors `@import` at runtime (assumed per harness).

## Remediation pointers (record-not-action; awaits explicit "수정")

- H1 → prompt-composed isolated evaluation ({contract,diff} only) — PoC-proven
  (`2026-06-25-h1b-evaluator-isolation-poc.md`); reduces self-eval drift.
- H2 → add the 4 dark rules to AGENTS.md (inline or Codex Read-list) so the
  "live inline" claim becomes true.
- H3 → vendor-neutral resolver: `${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(git rev-parse --show-toplevel)}}`
  + state-dir branch (`.claude` vs `.codex/state`) in refine mirror + completion-checker.
- R2-self → compress anchor-discipline preserving P1(anchor)+P4(attestation);
  drop magic-numbers/AUD-self-citations or back them with a real oracle.
- W1/N* → honest doc corrections (one-liners).
- Prior detailed alternatives: `2026-06-24-remediation-and-alternatives.md`.

## Root cause (apex — surfaced by §4 cross-check)

H1 / H2 / H3 / H3b / H3c / W2 / W4 are **not independent bugs**. They are
symptoms of **one generating mechanism: the one-way `.claude/`→`.agents/`
sync copies semantically Claude-coupled text verbatim, with no translation
and no "does this claim still hold for Codex?" gate.**

- `sync-agents-mirror.sh` is `cp -R` (byte copy). It guarantees **Layer-1
  parity by construction** — and that is precisely the disease: it reproduces,
  into the Codex home, sentences that are *true on Claude and false on Codex*
  (the evaluator's isolation guarantee; refine's `$CLAUDE_PROJECT_DIR` +
  `.claude/.refinement-active`; the rules' "loaded inline" premise).
- So **any** `.claude/`-hardcoded path or Claude-execution-model claim in a
  ground-truth file silently breaks when mirrored. The audit caught instances;
  the class is "mirror without semantic translation."
- The same script is also **orphan-blind** (additive `cp`, no deletion
  propagation) — which is why removing `security/` this session required a
  manual `git rm` of `.agents/security/` the sync could never have pruned.

Essence: **byte-perfect mirroring is the wrong success criterion** (R4 — wrong
goal). The correct criterion is *semantic* parity: a mirror step that (a)
rebinds vendor paths/env, (b) drops or re-words claims the target vendor can't
honor, (c) propagates deletions. Until then, Layer-1 "100% parity" actively
masks Layer-2 breakage.

## §4 external cross-check — SIGN-OFF

**Verdict: SOUND. Zero false positives.** All five problem claims (H1, H2, H3,
H3-checker, R2-self) independently CONFIRMED by the evaluator via re-executed
tool evidence (diff byte-identity; `grep` body-keyword = 0; env-stripped
`completion-checker.sh` re-creating `.claude/.last-verification.main`; `wc -w`
size ranking 779 largest; zero-invocation greps). Both NOT-A-BUG checks
(load-bearing `||-f` on 0644; `ghp_{36}` boundary) correctly cleared.

Corrections folded in:
- **R2-self** is reframed: the *facts* are tool-proven; the *label* "R2
  violation" is a defensible engineering judgment, marked as such.
- **H3 generalized** to the mirror-sync path-coupling class (see Root cause).
- **H2 precise framing**: the 4 rules ARE physically in `.agents/rules/` but
  **unreachable via the documented Codex load path (AGENTS.md)** — "mirrored
  to disk, dark to the consumer," stronger than "not inlined."
- Evaluator's scoping gap "consistency-checker unexercised" is **already
  closed**: groups 2 & 4 executed `karpathy-consistency-check.sh` (clean PASS +
  injected-drift FAIL + restore PASS). The evaluator lacked those group reports.
- Residual (declared): Claude-side `/refine` end-to-end not run (path-match
  inferred, not executed); flagged in negative space.

Audit-discipline §4 satisfied: external cross-check confirmed correctness AND
caught a scoping error (instance→class) the finder agents shared. This audit
is cleared for citation / Codex handoff.
