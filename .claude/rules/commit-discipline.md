# Commit Discipline

> Source: a prior audit flagged commits bundling orthogonal changes (a runtime
> fix + setup logic + a README edit + a filemode tweak) with no stated coupling.

## 1. One concern per commit

If two changes can be reverted independently with no breakage, they belong in two
commits. The test is **reversibility, not file count**. Keep separate: runtime
fix vs docs, behavior vs formatting, one rule vs another.

## 2. Bundling requires an explicit `Coupling:` line

Bundle only when revert-of-one breaks the other, or all sub-changes share one
end-state that fails if any is missing — and state the reason in a `Coupling:`
line in the commit body. Without it, a reviewer cannot tell deliberate coupling
from oversight. (The pre-commit gate emits a non-blocking reminder on multi-file
commits whose message lacks this line.)

## 3. Forbidden bundles

Multi-defect bundle (several independently-revertible fixes as one); drive-by
docs (a README edit unmentioned in a build-change commit's body); mixed-layer
scope (parent + sub-project change as one when each was an independent decision —
allowed only with a "symmetric across layers" justification in the body).

## 4. Counter-test

"If I revert exactly this commit, what one end-state changes?" More than one
independent end-state → it should have been split. Applies to new commits;
history is retrospective.

---
*External anchor: atomic-commit practice — clean revert, `git bisect`, focused
review (Pro Git, git-scm.com/book).*
