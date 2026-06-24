# Agent-System Essence Audit — Claude ↔ Codex (full-surface, body-based)

*Date: 2026-06-24 · Auditor: Claude (Opus 4.8) · Yardstick: andrej-karpathy-skills (R1–R4)*
*Method: enumerate → byte-diff → read bodies → 3 parallel breadth sub-audits → re-execute top claims → evaluator §4 cross-check.*

## 0. Mandate & frozen anchor (user, verbatim 7 elements)

> "전체 Agent 시스템 - 당신/코덱스 구성 비교 !실제 본문 내용 기반! andrej-karpathy-skills 기준에 따라 전체 구성요소의 본질을 감사하는 것 (매우 어렵고 큰 작업)"

1. `전체 Agent 시스템` — full surface, not a subset.
2. `당신/코덱스 구성 비교` — Claude ↔ Codex pairwise.
3. `!실제 본문 내용 기반!` — **actual file bodies**, not CLAUDE.md/PROJECT.md descriptions.
4. `andrej-karpathy-skills 기준` — Karpathy R1 Think / R2 Simplicity / R3 Surgical / R4 Goal.
5. `전체 구성요소의 본질` — **essence**, not text.
6. `(매우 어렵고 큰 작업)` — depth mandated.

## 1. Negative-space declaration (audit-discipline §1)

**Covered:** every file under `.claude/`, `.agents/`, `.codex/` + the 4 governance docs (CLAUDE/AGENTS/PROJECT/REFERENCE) + sync engine + verification spine. Body-read, not description-read.

**NOT covered (declared exclusions):**
- The closed-source Codex CLI runtime's *actual interpretation* of `.codex/config.toml`/`hooks.json` — audited the config/hook **content**, not the binary's behavior, except where a hook was E2E-runnable.
- The host Docker trust boundary (documented in REFERENCE.md; not re-litigated — prior audits cover it).
- Supply-chain/rolling-version drift (prior-audit scope).
- Algorithmic optimality of the refine/wiki *domain logic* (audited essence + parity, not whether the algorithms are best-in-class).
- **Runtime path-binding under a live Codex process** was proven by deterministic shell-parameter simulation (`CLAUDE_PROJECT_DIR` unset reproduces the Codex condition exactly — pure `${VAR:-}` expansion, not container-dependent), NOT by booting the Codex CLI in an external container. If a live-Codex exercise is wanted, it is a separately-scoped follow-up.

## 2. Audit universe (enumerated, line counts)

| Layer | Claude (`.claude/` + CLAUDE.md) | Codex mirror (`.agents/`) | Codex CLI (`.codex/`) |
|---|---|---|---|
| Governance | CLAUDE.md (109) | — | AGENTS.md (156) |
| Sub-agents | agents/ 2 (evaluator 101, wip-manager 149) | **skills/ re-homed** (same 2, byte-identical) | — |
| Hooks | hooks/ 4 (126/87/94/96) | — | hooks/ 4 (88/64/58/84) |
| Rules | rules/ 6 +project/ | rules/ 6 (identical) | — |
| Skills | skills/ 5 | skills/ 5 + 2 re-homed = 7 | — |
| Security | security/ 10 | security/ 10 (identical) | — |
| Wiring | settings.json (49) | — | config.toml (29) + hooks.json (38) |
| Engine/spine | scripts/sync-agents-mirror.sh, scripts/meta/completion-checker.sh (33), verify-template.sh (59 checks) | | |

## 3. Three-layer verdict

### LAYER 1 — Text parity: **PERFECT** ✓
Byte-diff: rules 6/6, skills 5/5 (incl. rubrics yml), security 10/10, agents→skills 2/2 — all IDENTICAL. `sync --dry` = 0. Cross-document consistency clean: component counts (2·4·5) match ground truth; all 4 docs dated 2026-04-30; Tier1/Ubuntu22.04/Node22 uniform; no port/count/date/version drift. The mirror mechanism faithfully copies **bytes**.

### LAYER 2 — Essence/semantic parity: **SYSTEMATICALLY DEGRADED** ✗
Byte-identical mirroring creates an *illusion* of parity that masks four distinct essence gaps:

**Gap 1 — Execution-model (agents). [HIGH]**
`evaluator.md`'s essence is context-isolation: *"You never see the generator's reasoning or task intent"* (evaluator.md:14, 55–59). The byte-identical copy is deployed on Codex as a **skill** (`.agents/skills/evaluator/SKILL.md`; `.agents/agents/` does not exist — re-verified). A skill loads into the *same* context, so the isolation the body mandates is **structurally unsatisfiable**. Consequence: `refine`'s keep/discard loop is driven solely by the evaluator score (refine:240–262); on Codex that score is **self-graded** — the exact anti-pattern refine:587 marks "✗ (self-validated)". Only refine **objective mode** (pure `verify_cmd`, no evaluator) keeps integrity on Codex; tool-augmented/calibrated modes do not. *Contrast:* `wip-manager` is a procedural skill needing no isolation → re-homing is essence-preserving there (harmless).
*Partial mitigation:* AGENTS.md:127 honestly flags "No sub-agent isolation". *Residual gap:* the refine body still **mandates** isolation it can't deliver, and nothing documents "calibrated/tool-augmented refine is Claude-only."

**Gap 2 — Activation (rules). [HIGH]**
CLAUDE.md @imports **all 6** discipline rules every session (CLAUDE.md:98–103). AGENTS.md session-start Read-list names only **2** (behavioral-core + devcontainer-patterns; AGENTS.md:146–147). → `audit-discipline`, `commit-discipline`, `destructive-ops-discipline`, `anchor-discipline` are **DARK on a default Codex session** — byte-identical files that are never loaded ("inert parity"). No Codex hook/config injects them (re-verified). Most dangerous: **destructive-ops dark on the very vendor whose sandbox is bypassed** in this container (REFERENCE.md `--dangerously-bypass-approvals-and-sandbox`); anchor dark on the only vendor that could break the shared-prior blind spot it warns about (anchor-discipline.md:62–67).
*Undocumented & self-contradictory:* AGENTS.md:3 asserts "all behavioral rules must live inline here" then loads 2/6. The asymmetry is nowhere declared.
*Survives anyway (hook-enforced):* commit-discipline §2 Coupling reminder (pre-commit Layer 3, both vendors). The **judgment-guiding** disciplines (destructive alternatives, audit scoping, anchor thesis-preservation) do not.

**Gap 3 — Path-binding (skills). [HIGH]**
`refine` hard-codes `$CLAUDE_PROJECT_DIR` + **22** `.claude/` literals (re-verified); `verify:26` = `bash "$CLAUDE_PROJECT_DIR/scripts/meta/completion-checker.sh"`. REFERENCE.md:181 itself documents that Codex uses `CODEX_PROJECT_DIR`, but the mirrored bodies never branch on it. **Runtime proof** (CLAUDE_PROJECT_DIR unset = Codex condition): refine `PROJECT` → empty (state writes to wrong tree); verify:26 → `bash "/scripts/meta/completion-checker.sh"` (absolute, nonexistent) → **fails** on the `all` path. Same bytes, wrong runtime target. status/wiki degrade **gracefully** (vendor-agnostic primary path; `.claude/` fallback finds nothing but doesn't error).
> **§4 precision:** the failing layer is the *skill's invocation path* (verify:26 expands to an absolute `/scripts/...`), NOT `completion-checker.sh` itself — that script has its own `${CLAUDE_PROJECT_DIR:-$(cd …)}` fallback (completion-checker.sh:13) and is var-robust *if reached*. So the correct fix branches the **skill invocation**, not the script. "HARD FAIL" is the literal-interpretation worst case of the skill instruction (verify:24/29 "if available" / "Or run…" is NL prose a lenient reader may route around). The status/wiki "graceful degradation" sub-claim is body-read, not command-proven — the weakest-evidenced line in this gap; treat as provisional.

**Gap 4 — Liveness (security), vendor-orthogonal. [MED]**
The entire `.claude/security/` surface is **0/10 LIVE, 10/10 VESTIGIAL** (grep-proven: zero refs to trust-boundary|risk-registry|frontmatter-schema|eval-suite outside the security dirs; `registry` only in AGENTS.md inventory L31/120). No hook, skill, agent, settings, config, script, or @import consumes any of it. Deleting all 10 would change **zero** runtime behavior. Mirroring it preserves the *text* of something with no *function* — on both vendors.

### LAYER 3 — Does the system obey the rules it audits others by? **MIXED — incl. an INTEGRITY self-violation** ✗
- Clean R1–R4: behavioral-core, commit-discipline (59L, the model), devcontainer-patterns, karpathy-guidelines (+EXAMPLES), verify (31L), status (67L).
- **anchor-discipline = R2 FAIL / meta-violation [MED]:** 123 lines, 7 protocols (P1–P6+§7), nested termination taxonomies, default-N configurability, per-response self-check ceremony — precisely the "200 lines that could be 50" / "configurability that wasn't requested" the yardstick it cites forbids (behavioral-core:25–27). The rule that polices essence-preservation is itself over-engineered.
  - **Why FAIL here but only WARN for refine (623L) — the grade tracks *self-referential contradiction*, not raw size (§4 calibration):** anchor-discipline cites behavioral-core:27 and then violates it — a simplicity-policing rule that is itself over-engineered is a category worse than a merely-large file. refine's bulk is *partly irreducible* (the context-isolated GAN loop is genuinely needed) and refine never preaches the rule it bends; anchor's bulk is *ceremony* (per-response self-check, nested taxonomies, AUD tags) and it breaks a rule it explicitly invokes. Self-contradiction → FAIL; large-but-honest → WARN.
- **refine = R2/R3 WARN [MED]:** Steps 7D+9 (refine:298–452) embed a 145-line wiki-page authoring block + scorer-evolution meta-learning — a second/third subsystem bolted into a refinement loop, each independently revertable (commit-discipline's own reversibility test). Inert-by-default but "complexity before it's needed."
- **security/ = INTEGRITY self-violation [MED]:** CLAUDE.md's core principle is *"Every claim must be verified by execution before statement."* Yet `registry.md:8,13` asserts a lifecycle gate ("reviewed → tested: eval suite executed and passed") that **no code ever executes** (self-admitted "documentation only — no automation," registry.md:59,71); all 6 eval-suites say "Manual"/"No automated runner". The security docs **assert controls that don't run** — the system contradicts its own central essence in its own security artifact.

## 4. Per-component scorecard

| Component | Text parity | R1 | R2 | R3 | R4 | Codex essence |
|---|---|---|---|---|---|---|
| behavioral-core | ✓ | P | P | P | P | PRESERVED (loaded) |
| audit-discipline | ✓ | P | WARN | P | P | **DARK** |
| commit-discipline | ✓ | P | P | P | P | **DARK** (hook part survives) |
| destructive-ops | ✓ | P | WARN | P | P | **DARK** (high-stakes) |
| anchor-discipline | ✓ | P | **FAIL** | WARN | P | **DARK** |
| devcontainer-patterns | ✓ | P | P | P | P | PRESERVED (loaded) |
| karpathy-guidelines | ✓ | P | P | P | P | PRESERVED |
| refine | ✓ | P | WARN | WARN | P | **DEGRADED→BROKEN** (isolation+paths) |
| status | ✓ | P | P | P | WARN | DEGRADED (graceful) |
| verify | ✓ | P | P | P | P | DEGRADED (hard-fail on `all`) |
| wiki | ✓ | P | WARN | P | P | DEGRADED (refine-coupled path) |
| evaluator (agent) | ✓ | P | P | P | P | **BROKEN essence** (isolation lost) |
| wip-manager (agent) | ✓ | P | P | P | P | PRESERVED (procedural) |
| security/ ×10 | ✓ | — | — | — | n/a | VESTIGIAL (both vendors) |
| hooks ×4 | n/a (separate) | P | P | P | P | PRESERVED (functional equiv.) |

## 5. Severity-ranked findings

**HIGH**
- H1 — refine keep/discard loop loses epistemic integrity on Codex (evaluator isolation unsatisfiable → self-grading); only objective-mode safe. *Partially acknowledged (AGENTS.md:127); consequence undocumented.*
- H2 — 4/6 disciplines DARK on Codex (inert parity); destructive-ops dark on the sandbox-bypassed vendor; asymmetry undeclared & contradicts AGENTS.md:3.
- H3 — refine/verify path-binding to `$CLAUDE_PROJECT_DIR`/`.claude/` → state misroute / hard-fail under Codex (runtime-proven).

**MED**
- M1 — security/ 10/10 vestigial; asserts unexecuted enforcement → violates the system's own INTEGRITY principle.
- M2 — anchor-discipline R2 self-violation (123L/7 protocols).
- M3 — refine over-scoped (embedded wiki-authoring + scorer-evolution).

**LOW**
- L1 — sync additive-only: ground-truth deletions don't propagate; `--dry` blind to dest-only by design (latent — currently no zombies, c77d9bf clean).
- L2 — pre-commit Layer 2 (/refine multi-file warning) dormant: gated on `.refine/score.sh`, not shipped → never fires (symmetric); claim-vs-reality vs CLAUDE.md §2.
- L3 — wiki declares `Agent` tool but never spawns one (unneeded privilege).
- L4 — `.audit/` not gitignored (committable by `git add .`).

## 6. What is NOT a problem (fair framing — R1)
- Text-parity mechanism: faithful and verifiable.
- Cross-doc factual consistency: clean (no drift).
- Karpathy yardstick: self-consistent (`karpathy-consistency-check.sh` PASS).
- Hooks: functional essence equivalent across vendors; Codex *compensates* for missing native auto-memory by injecting MEMORY.md in its session-start hook (different mechanism, same outcome).
- secret-scan parity (prior loop's work) intact across both gates.
- The system **knows several of its own limits** (AGENTS.md:122–129 vendor-constraints table) — the gaps above are residual/undocumented consequences, not total blind spots.

## 7. Verdict

**Text parity PERFECT; essence parity SYSTEMATICALLY DEGRADED.** The polyagent model's foundational claim — "one ground truth feeds faithful per-vendor mirrors" — holds at the **byte** layer and breaks at the **semantic** layer in three structural ways (execution-model, activation, path-binding), plus a vendor-orthogonal liveness gap (security is documentation, not control) and a Karpathy self-compliance gap (anchor over-engineered; security violates the system's own INTEGRITY principle).

The single deepest finding: **byte-identical mirroring of an isolation-dependent agent and of Claude-path-bound skills produces Codex artifacts that assert guarantees the Codex runtime cannot honor** — and the system documents the *mechanism* (sync) far better than the *consequences* (which modes/rules are actually live on Codex).

This is an **audit/report only** — no system fix applied (no "수정" instruction). Findings recorded for disposition; remediation alternatives in the companion doc. Not pushed.

## 8. §4 external cross-check (evaluator, tool-isolated) — SIGN-OFF

**Verdict: SOUND, with two minor corrections (both applied above). Zero false positives.** The evaluator independently reproduced — with tool evidence — Text-parity-PERFECT, H1, H2, H3, M1, M2, M3, L2, L3, L4. No claimed gap turned out to actually work. Corrections folded in:
1. **M2 severity** — the anchor-FAIL vs refine-WARN split is now justified explicitly by *self-referential contradiction* (not size). See the §3 Layer-3 M2 bullet.
2. **H3 framing** — "HARD FAIL" qualified: the break is at the skill invocation path (verify:26), not `completion-checker.sh` (which is var-robust); status/wiki graceful-degradation flagged as the weakest-evidenced sub-claim. See the §3 Gap-3 precision note.

**Coverage split (honest):** the §4 evaluator covered HIGH/MED + L2/L3/L4; the auditor independently re-executed the rest (text-parity diffs, `karpathy-consistency-check` PASS, cross-doc drift grep, secret-scan parity, L1 empirical zombie-test) earlier in this audit. L1 was NOT re-checked by the evaluator (auditor-only); it is reported as a *latent* structural gap (currently zero zombies), the lowest-confidence finding by cross-check redundancy.

*Finalized 2026-06-24. Companion: `2026-06-24-remediation-and-alternatives.md`. Handoff: Codex (이어 작업).*
