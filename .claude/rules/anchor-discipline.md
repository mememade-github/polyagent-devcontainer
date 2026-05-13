# Anchor Discipline

> Prevents LLM-default substitution of the user's thesis in multi-iteration or
> multi-document work. Surfaced by a prior multi-iter authoring cycle in which
> ~75% of the user's verbatim thesis elements (5 of 7) were absent or
> demoted to subordinate clauses by iteration ~20, despite the cycle passing
> every internal audit. anchor-discipline enforces *output ↔ user-thesis gap*
> measurement that *output-internal audit* cannot catch.

## 1. Verbatim anchor required (P1)

When the user states a thesis that feeds a multi-stage task (cycle / multi-iter
/ multi-document cross-update), preserve a **verbatim quotation of the user's
message in a separate frozen file**. The *first step* of every subsequent
operation = **grep matrix** of output ↔ frozen file. Hit ratio below a
preset threshold (default 80%) auto-fails the task.

Frozen file location:
- task-scoped: `.audit/<task>-anchor.md`
- plan-scoped: `<plan-dir>/anchor.md`

Frozen file format:
- verbatim quotation of user messages 1..N (no edits)
- N extracted anchor elements (regex pattern + position requirement)
- self-referential / forbidden patterns (when applicable)
- cycle termination conditions (anchor hit + explicit user attestation)

Frozen file edit permission: **only on user dictation**. AI-initiated edits
prohibited.

## 2. Essence check = cycle termination condition (P2)

The termination condition of a cycle / multi-iter task is **all N user-stated
thesis elements present in *primary thesis* position (not subordinate clauses)**,
as the *primary* condition. Wording, self-reference suppression, length quota,
and vendor consensus are *secondary* conditions only.

Position requirement measurement:
- **primary thesis position**: paragraph opener, conclusion, or core sentence
- **subordinate position (violation)**: "also ...", "separately ...", "for
  reference ...", or "mentioned only once" forms

Meeting only secondary conditions while violating the primary one does NOT
terminate the cycle. Wording consensus ✓ with anchor violation → cycle
continues.

## 3. Quick-Answer Stop (P3)

User request → going straight to *options-presentation* or *direct execution*
without a *cause-analysis step* triggers self-stop. The cause-analysis step
requires all three of:

(a) **Verbatim re-quote of user request** — exact text, no paraphrase.
(b) **Prior-output ↔ anchor gap** — grep matrix or equivalent.
(c) **LLM-default origin of the gap** — which sub-pattern (role/fit-bias,
    quick-answer, vendor-single-lens, false-positive termination,
    auto-framing substitution) produced it.

A response missing any of (a)(b)(c) violates anchor-discipline. Repetition
within the same task triggers root-cause re-diagnosis.

## 4. Vendor-cross self-audit ≠ external verification + user-essence gate (P4)

Cross-audits across multiple LLM vendors (e.g., Claude, Codex, GPT, Gemini)
are *not external verification* — they are cross-audits within the shared LLM
prior. Anchor alignment has structural limits under this prior (all vendors
share the role-fit-bias and quick-answer defaults).

Therefore the cycle termination condition must include a **user-essence
attestation gate**:
- every N iterations (default 5), gate on *explicit user ack*.
- vendor consensus ✓ + LLM measurement pass ≠ cycle termination. User
  attestation is required.

Ack form: explicit user statement "essence aligned OK" or equivalent.
Silence ≠ ack.

## 5. Frame-of-reference externalization (P5)

Define the self-audit lens as *user-thesis ↔ output gap*, not *output
internals*. Every iteration deliverable = "output" + "anchor gap matrix"
together.

A deliverable without the gap matrix is an incomplete iteration. At cycle
termination, review all iterations' gap matrices cumulatively.

## 6. Protocol drift avoidance (P6)

A good analysis turn → an execution turn that regresses to LLM defaults is a
recurring pattern. P1-P5 derived in analysis → reverted to quick-answer /
single-lens / output-internal audit in execution → P3 (Quick-Answer Stop)
auto-applies.

Each response opens with a self-check section on *prior-turn protocol
application*:
- of P1-P5 analyzed in the prior turn, which were applied / not applied?
- if not applied, state the reason (or identify the omission itself as drift).

## 7. Counter-test (Karpathy 4-rule alignment)

Termination conditions (primary — all four required to terminate the task):
- output anchor hit ratio ≥ 80% (P1)
- user-essence attestation gate passed (P4)
- prior-turn protocol-application self-check section present (P6)
- self-reference / forbidden pattern grep = 0 (per §1 frozen-file forbidden patterns)

Process conditions (apply during iteration, not at termination — AUD-2026-010):
- P2 essence check (primary thesis position > subordinate clauses) — applied per iteration deliverable
- P3 Quick-Answer Stop on missing cause-analysis — applied at every response opening
- P5 frame-of-reference externalization (gap matrix in every iteration deliverable)

All four primary satisfied AND process conditions applied each iteration → task termination.
Any primary violated → P3 (Stop) applies.

---

*Source: a prior multi-iter authoring cycle in which anchor hit reached
~27% by iter ~20 (~5 of 7 user-stated thesis elements absent or demoted)
despite all internal audits passing. Codified after a user critique cycle
named the gap as a structural one. Complements
[`audit-discipline.md`](audit-discipline.md): audit-discipline operates at
level 4 (external cross-check); anchor-discipline operates at level 0
(user-thesis preservation).*
