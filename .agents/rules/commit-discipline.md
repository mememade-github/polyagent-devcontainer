# Commit Discipline

> Anti-pattern observed: commits bundling orthogonal changes (e.g.,
> a runtime path fix + setup-script logic + README copy edit + a
> filesystem-permission tweak in a single commit) without justifying
> the coupling. Surfaced by a Karpathy-4-rule re-audit finding —
> "Bundled commits with unjustified coupling".

## 1. Default: one concern per commit

If two changes can be reverted independently with no breakage, they
belong in two commits. The test is reversibility, not file count.

Examples of orthogonal concerns to keep separate:
- runtime fix vs. documentation update;
- behavior change vs. style/format change;
- application code vs. test code (only when test is for the same
  behavior — fixture additions can ride along);
- one rule vs. another rule (each rule is its own concern).

## 2. Bundling allowed only with explicit coupling

A bundle is acceptable when:
- the changes are tightly coupled (revert of one breaks the other);
- the changes share a single end-state success criterion that fails
  if any sub-change is missing;
- the commit body explicitly states the coupling reason in a
  "Coupling:" line.

Without that line, the reviewer cannot tell whether bundling was
deliberate or an oversight.

## 3. Forbidden bundle patterns (from observed failures)

- **Multi-defect bundle**: combining several independently reversible
  fixes (e.g., a runtime path symlink fix + a setup-env logic change
  + a README copy edit + a filemode tweak) into one commit. Revert of
  any one would have left the others in place — proof of independence.
- **Drive-by docs**: editing README in a commit whose body is about a
  build-system change, without mentioning the README in the body.
- **Mixed scope across layers**: changing parent-workspace and
  sub-project Dockerfiles in one commit when each layer was an
  independent decision (acceptable when coupled, with explicit
  "Symmetric across layers" justification in the commit body).

## 4. Counter-test for this rule

For each commit, ask: "If I revert exactly this commit, what one
end-state changes?" If the answer is more than one independent
end-state, the commit should have been split.

For commits already in history, this is retrospective. The rule
applies to new commits.

---

*Source: a prior template audit cycle in which several recent
commits each bundled multiple orthogonal changes; flagged by a
Karpathy 4-rule self-audit.*
