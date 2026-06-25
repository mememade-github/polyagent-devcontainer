# Anchor Discipline

> Source: a multi-iter cycle where ~5 of 7 of the user's verbatim thesis elements
> went missing or were demoted by iteration ~20 — while every internal audit
> passed. Internal audits measure output internals; they cannot measure the
> *output ↔ user-thesis gap*. This rule measures that gap.

## 1. Verbatim anchor

For a multi-stage task driven by a user thesis, keep a **verbatim frozen quote**
of the user's messages in a separate file (`.audit/<task>-anchor.md` or
`<plan-dir>/anchor.md`). The first step of each turn is a grep matrix of output
against that file; below ~80% element coverage, stop and re-anchor. Edit the
frozen file only on user dictation.

## 2. Essence over wording

Terminate the task only when every user-stated thesis element sits in *primary*
position (paragraph opener / conclusion / core sentence), not demoted to
"also…", "separately…", "for reference…". Wording polish or cross-vendor
consensus with the thesis demoted does **not** terminate the task.

## 3. User-attestation gate

Cross-audits across LLM vendors are *not* external verification — all share the
same role-fit and quick-answer priors. Gate termination on an explicit user ack
("essence aligned" or equivalent); silence ≠ ack.

---
*Level 0 (user-thesis preservation); complements
[`audit-discipline.md`](audit-discipline.md) at level 4 (external cross-check).
No external best-practice source — retained as a bespoke guard, deliberately
kept short.*
