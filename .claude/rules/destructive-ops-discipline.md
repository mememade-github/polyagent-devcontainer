# Destructive Operations Discipline

> Source: a prior cycle chose a full git-history rewrite for a single-name leak
> when a revert + token rotation would have done — R2/R3 FAIL. The narrower
> options were never surfaced in the plan.

## 1. Surface alternatives first

Before any approval-required destructive op (`rm -rf`, `mv`/`cp` overwrite,
`git push --force`, `git reset --hard`, `DROP`/`DELETE`) or irreversible op
(`git filter-repo`, `rebase --root`, repo-wide replace, `docker volume rm`),
state: the proposed op, **≥1 narrower alternative**, the blast-radius asymmetry,
and why the broader op was chosen. Skipping this fails Karpathy R1 (don't pick
silently) and R2 (minimum that solves it).

## 2. Narrower alternatives by operation

| Operation | Consider first |
|-----------|----------------|
| `git filter-repo --replace-text` | BFG; revert + secret rotation if recent; `--path`-scoped |
| `git push --force` | `--force-with-lease`; coordinate timing |
| `git reset --hard` | `--soft` + selective checkout; recovery branch first |
| `rm -rf <dir>` | enumerate `rm <files>`; move to `.trash/`; check refs first |
| repo-wide regex replace | path-scoped; one-by-one Edit |
| `docker volume rm` | inspect first; rename to `<name>-archived-YYYYMMDD` |
| `docker rm -f` | `docker stop` first; `-f` only after it fails |
| `mv`/`cp` overwrite | back up `<dst>.bak`; `diff` first; `--no-clobber` |
| `DROP`/`DELETE` bulk | soft-delete; archive table; verify a restorable backup |

Principle: ask "what's the smallest action that reaches the end-state?" first.

## 3. Rotate before scrub

For credential-leak removal, *rotate the credential first*. History scrub is
cleanup for an already-mitigated leak; reversing the order leaves the token live
while you spend time on the rewrite.

## 4. Counter-test

The plan must contain a sentence naming a narrower alternative and why it was
rejected. No such sentence → the plan is incomplete; do not execute.

---
*External anchor: least-blast-radius / staged rollout — Google SRE.*
