# Audit Discipline

> Anti-patterns observed in a prior template audit cycle, codified after
> an external vendor re-audit found issues that the internal audit
> missed. The failures clustered in two structural areas: success-criteria
> scope and entry-path coverage.

## 1. Negative space declaration

**Before any audit, declare what you are *not* checking.**

Audits silently exclude axes. If the exclusion is not declared, the
audit reads as "all clear" when it actually means "all clear within the
chosen lens". Axes commonly missed in template audits:

- cross-document numerical/textual consistency (e.g. port number
  drift across docs, component counts that disagree between README
  and detailed reference);
- multi-entry-point parity (e.g. VS Code DevContainer mounts vs plain
  `docker compose up`);
- supply-chain time-axis stability (rolling tool versions producing
  different installed software on different days);
- marketing-vs-technical claim accuracy (e.g. "isolated" or "sandbox"
  framing that does not match the actual trust model).

**Required at audit start:**
- one sentence per excluded axis: what is excluded and why.
- if the user requested coverage for an excluded axis later, treat it
  as a redo of the audit, not a follow-up of the previous one.

**Required at audit end:**
- if any excluded axis turned out to matter (post-hoc external
  finding, regression, etc.), record it in the audit report as a
  scope error, not as a new finding. The lesson is the scoping, not
  the leak.

## 2. Counter-test scope

Counter-tests must verify two things, not one:

- **Detection works (positive)**: with a synthetic violation injected,
  the audit raises the violation. Standard.
- **Adjacent paths intact (regression)**: the fix does not break a
  path the audit did not exercise.

The triggering audit cycle had only positive counter-tests. The
textbook adjacent-path regression observed there: a fix touched
README to correct one number, the audit verified the fix, but the
same edit introduced a new inconsistency between the README and a
co-mounted reference doc (component-count drift).

**Required:** for any fix that edits a file, the counter-test must
include "what other claims in the same file or co-mounted files
should still hold true" — and verify them.

## 3. Mirror commits: re-verify locally

A mirror commit's body that says "Counter-tests verified upstream" is
an unstated assumption that the mirror is byte-identical to the
upstream and runs in an identical environment.

The assumption is rarely fully true:
- different git remote (GitHub upstream vs GitLab origin);
- different container registry / cache state;
- different `.gitignore` or LFS configuration;
- different CI/CD pipeline that touches the file post-commit.

**Required for mirror commits:**
- run the same counter-tests locally on the mirror, even if the diff
  is byte-identical to upstream;
- if the local re-verification is genuinely redundant (e.g.,
  hash-locked artifact distribution), record the basis for that
  judgment in the commit body — not by absence of information.

## 4. External cross-check thresholds

Self-audits structurally cannot catch their own scoping errors. For
high-value surfaces (public OSS templates, security-sensitive code,
governance-bearing files), the audit should include at least one
external cross-check before declaring done:

- a different vendor agent (e.g., a second AI coding assistant when
  the work was done in the first);
- an evaluator agent in a separate context window;
- a static-analysis tool the primary agent did not pick.

Single-agent self-audits remain valid for trivial, narrowly-scoped
work. The signal that an external cross-check is needed: the audit
is intended to certify a claim that other people will rely on.

---

*Source: a prior template audit cycle plus its external vendor
re-audit, the union of which surfaced these scoping and entry-path
failures.*
