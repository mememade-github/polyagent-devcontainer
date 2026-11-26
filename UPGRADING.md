# Upgrading a consuming project

## Unreleased

`/refine` and its Stop-hook loop are removed. Consumers who copy template files
must explicitly delete `.claude/skills/refine/` (and regenerate the mirror so
`.agents/skills/refine/` disappears), `.claude/hooks/refinement-gate.sh`, and
`.codex/hooks/refinement-gate.sh`; drop the `Stop` registrations from
`.claude/settings.json`, `.codex/hooks.json`, and `.agents/hooks.json`; and
remove the obsolete local state (`.claude/.refinement-active`,
`.claude/.stop-blocked-refinement.*`, `.claude/.refine-output`,
`.claude/.refine-eval.json`, `.claude/agent-memory/refinement/`, and the
matching `.codex/state/` entries `refinement-active`, `stop-blocked-refinement.*`,
`.refine-output`, `.refine-eval.json`, `refinement/`) together with their ignore
entries. Verification markers are covered by the commit-gate removal below.

Update `CLAUDE.md`, `AGENTS.md`, `.claude/agents/evaluator.md`,
`scripts/meta/run-isolated-role.sh`, the session-start hooks,
`.devcontainer/verify-template.sh` (its refinement-gate and Antigravity Stop
cases are gone), and the hand-maintained `.agents/hooks/claude-hooks-adapter.sh`,
then regenerate `.agents/rules` and `.agents/skills` with
`bash scripts/sync-agents-mirror.sh`.

Independent evaluation receives the authorized request, acceptance conditions,
actual diff, relevant repository facts, and execution evidence, without the
modifier's reasoning. Custom Codex callers must use
`scripts/meta/run-isolated-role.sh evaluate <project-root> <prompt-file> <output-file>`
and supply the evaluator role body, permitted inputs, repository location, and
matching report destination in the prompt. Consume the report's conclusion and
evidence; the helper requires a newly written, non-empty report without imposing
a content or format gate. No container rebuild is needed.

The session-start check of a repository-root `MEMORY.md` is removed: no
template component creates that file. Drop the `MEMORY.md` clause from the
session-start bullet in `CLAUDE.md` and `AGENTS.md`, and the "Known issues from
auto memory" block from `.codex/hooks/session-start.sh`. A project that keeps
its own memory file names its path and purpose in its own governance. Claude
Code's automatic memory is stored outside the repository and is not this file.

The `karpathy-guidelines` skill, its copy-equality check, and the root
detection helper only that check used are removed. Delete
`.claude/skills/karpathy-guidelines/`, `scripts/meta/karpathy-consistency-check.sh`,
and `scripts/meta/lib/detect-root.sh` (and `scripts/meta/lib/` if it is now
empty). Remove the checker call from `scripts/meta/completion-checker.sh` and
the "karpathy pair" case from the leak-scan section of `.devcontainer/verify-template.sh`,
the `karpathy-guidelines` invocation from `AGENTS.md`, and the skill from README
and REFERENCE skill lists. The "Source of truth" blockquote of
`.claude/rules/behavioral-core.md` named the skill and the check; that file is
removed below. After these edits, run `bash scripts/sync-agents-mirror.sh` so
`.agents/skills/karpathy-guidelines/` disappears;
`bash scripts/sync-agents-mirror.sh --dry` then reports 0 changes. Any project
script or setting that still calls the removed files breaks and must be changed
with them.

The always-loaded `.claude/rules/devcontainer-patterns.md` rule is removed; its
operating notes now live in REFERENCE.md §Docker from inside the container,
without the old `docker compose --project-directory <HOST_PATH>` instruction,
which also moved the build context to the host path. Delete the rule file, run
`bash scripts/sync-agents-mirror.sh` so `.agents/rules/devcontainer-patterns.md`
disappears, and drop its `@` import from `CLAUDE.md` and its read instruction
from `AGENTS.md`. Set `HOST_WORKSPACE_PATH` alone when the daemon cannot see the
container's paths.

The shared duties and the four behavioral rules now have one hand-maintained
source, `AGENTS.md`, which Codex loads by itself and Claude imports.
`CLAUDE.md` keeps only `@AGENTS.md`, `@PROJECT.md`, and Claude Code specifics,
and `.claude/rules/behavioral-core.md` is removed; its rules and the Karpathy
source and license notice are now the "Behavioral rules" section of
`AGENTS.md`. To adopt:

1. Merge the duties of your `CLAUDE.md` into `AGENTS.md` once. A duty left in
   both files is read twice by Claude, and a duty left only in `CLAUDE.md`
   never reaches Codex or Antigravity.
2. Reduce `CLAUDE.md` to the two imports plus anything that applies to Claude
   Code alone.
3. Delete `.claude/rules/behavioral-core.md` and run
   `bash scripts/sync-agents-mirror.sh` so `.agents/rules/behavioral-core.md`
   disappears.
4. Keep `.agents/rules.json`. `AGENTS.md` now tells Codex to read `PROJECT.md`
   and every `.md` file under `.agents/rules/project/` at session start, and
   tells Antigravity to read `PROJECT.md`; keep those sentences if you rewrite
   the file.
5. Start new agent sessions. No container rebuild is needed.

The evaluation duty in `AGENTS.md` now states its boundaries: a change is
meaningful when it alters behavior, a duty, an interface, an operating
procedure, or a generation relationship, including in documentation alone,
and an evaluation is incomplete when no fresh evaluator context can be created,
when no report is left, or when the report does not judge the actual diff.
`.claude/agents/evaluator.md` drops `maxTurns: 20` (a full-repository
evaluation once hit that limit and ended without a report) and says an
unavailable fresh context means an incomplete evaluation. Copy both changes and run
`bash scripts/sync-agents-mirror.sh` to regenerate
`.agents/skills/evaluator/SKILL.md`.

The commit gate and its verification markers are removed. Running
`scripts/meta/completion-checker.sh` no longer writes a marker, no template hook
blocks a commit (for a missing or old marker or for `--no-verify`), and
`AGENTS.md` no longer requires the checker before every commit: it is run for a
change that touches what it checks, and the report says which checks ran,
failed, or were skipped. The fast checks and independent evaluation remain;
neither is evidence of completion beyond what it observed, and a passing
`/verify` or `verify-template.sh` run establishes only the properties it checks. The
pre-push gate, its single-use force-push approval markers
(`.claude/.allow-force-push.*`, `.codex/state/allow-force-push.*`), their ignore
entries, and `.codex/state/.gitkeep` are unchanged. Make all of the following
changes in one adoption commit; a registration left without its hook file, or a
marker reader left without its writer, breaks or blocks commands:

1. Delete `.claude/hooks/pre-commit-gate.sh` and `.codex/hooks/pre-commit-gate.sh`.
   Copying the new template files over yours does not remove them.
2. Remove their `PreToolUse` entries from `.claude/settings.json` and
   `.codex/hooks.json`. Keep `.agents/hooks.json`, and take the new
   `.agents/hooks/claude-hooks-adapter.sh`, which now calls only
   `pre-push-gate.sh`.
3. Take the new `scripts/meta/completion-checker.sh` (no marker write), both
   session-start hooks (no marker pruning), the `status` and `verify` skills,
   and `.devcontainer/verify-template.sh` (its commit cases and its
   checker-marker-hook round-trip section are gone), then run
   `bash scripts/sync-agents-mirror.sh`.
4. Replace the commit-check bullet, the `status`/`verify` bullet, and the
   marker sentences of the trust model in `AGENTS.md`, and the hook lists and
   verification table in README and REFERENCE. The "Preserve verification
   markers" instruction in earlier versions of this file no longer applies.
5. Delete existing verification markers (`.claude/.last-verification.*`,
   `.codex/state/last-verification.*`) and then remove the
   `.claude/.last-verification*` and `.codex/state/last-verification*` lines
   from `.gitignore`; markers left behind become untracked files that
   `git add -A` would commit. Leftover `/refine` state is a separate cleanup,
   listed above.
6. Do not remove your project's own hooks or the Git hooks under
   `core.hooksPath` because of this list; it covers only the two template
   files above. Change any tool of your own that waited for a verification
   marker, because none will appear.
7. Start new agent sessions; on Codex, review the changed hooks in `/hooks`.
   No container rebuild is needed: the hooks and scripts run from the mounted
   checkout, not from the image.

To roll back, restore the earlier version's hook files, registrations, adapter,
checker, skills, session-start hooks, ignore lines, and documents together. An
old marker is not evidence that the current tree was checked.

`scripts/meta/completion-checker.sh` now reports what it could not check
instead of passing it. A failed `git ls-files` fails the shell-syntax check
rather than leaving it with nothing to check. A pattern file that exists but
cannot be read, a `scripts/meta/leak-patterns.txt` with no patterns, a
`git grep` that exits above 1 or writes any error, and a
`sync-agents-mirror.sh --dry` error each fail with their own message, and the
checker prints which pattern sources it used. Without
python3 `tomllib` (Python 3.10 and older, including this template image's
system python3) the TOML parse is printed as `NOT CHECKED` and left out of the
`OK:` line, and the run still exits 0 when the other checks pass. The script
checks the checkout that contains it, so a worktree's copy checks that
worktree. Take the new script together with the `AGENTS.md` checker bullet,
the `verify` skill, and REFERENCE §Verification and §Shared status and
verification, then run `bash scripts/sync-agents-mirror.sh`. A tool of your own
that parsed the old `OK:` line must read the new `OK:`, `NOT CHECKED:`,
`FAILED:`, and `Leak patterns:` lines. No container rebuild is needed.

`scripts/sync-agents-mirror.sh` now rejects symlinks only in `.agents/rules/`,
`.agents/skills/` and their `.claude/` sources, so a symlink under a
hand-maintained path such as `.agents/hooks/` no longer stops the sync or the
fast checker. A failed `find`, `grep`, `diff` or `stat` now exits 1 before the
sync reports a result or changes files; before, a `diff` error read as "no
difference". Its comments and closing note no longer call `.claude/` the
ground truth: `AGENTS.md` holds the shared duties, and `.claude/` is the source
of the generated trees. Take the new script with REFERENCE §Polyagent parity.
No container rebuild is needed.

`.devcontainer/verify-template.sh` is reduced to what it observes. Its Compose
section, which replaced the entrypoint with Bash and therefore never showed a
normal start or the healthcheck, is removed; observe a normal start
separately. Its own mirror, leak and shell-syntax sections are replaced by
one run of `scripts/meta/completion-checker.sh`, so the leak policy and
pattern files are the checker's (the suite's fixed pattern copy, its
`git grep` error swallowing and its printing of matched lines are gone), and
the checker no longer excludes `verify-template.sh` from its leak scan. The
hook cases are unchanged and show the hook scripts' and adapter's output for
synthetic input only. The count line is replaced by a summary of what failed
and what did not run; exit 2 now means a required check did not run, and a
missing optional tool, including Docker, is listed as absent. Update the `AGENTS.md`
bullet, the `verify` skill, the README initialization prompt and REFERENCE
§Verification with it, then run `bash scripts/sync-agents-mirror.sh`. A tool of
your own that read the `RESULT: N PASS / N FAIL / N SKIP` line or treated a
missing Docker as a skip must change. No container rebuild is needed.

Startup step 3 of `.devcontainer/setup-env.sh` no longer prints "already
latest" when `claude update` fails. Before, the update's exit status and output
were discarded, so a failed update with an unchanged version read as already
latest. Now a failed update prints a WARN, the version still in use, and the
last 20 lines of its output, and startup continues as before. Take the new
`setup-env.sh` with REFERENCE §DevContainer lifecycle and §Tool versioning
policy. The image copies `setup-env.sh` to `/usr/local/bin/`, so rebuild the
container for the new startup output.

The Codex launcher (`.devcontainer/codex-launcher.sh`) and startup step 4 no
longer report "already latest" when the latest version was not checked or a
reinstall failed. Before, `--update-only` exited 0 when npm was missing, when
the registry was unreachable, and when a failed reinstall was rolled back to a
working previous install. Now `--update-only` exits 0 (reinstalled or already
at the latest version), 3 (latest version not checked; the install is left as
it was, working or not), 4 (reinstall failed; a working previous install was
restored), or 5 (reinstall failed; no working `codex`), and step 4 prints a
WARN for every status but 0. A normal `codex` run prints one line on stderr
when the reinstall fails and nothing more on stdout. Restoring the previous
install, the offline guard, and the update lock are unchanged. A script of
your own that called `codex-launcher --update-only` and treated any non-zero
status as a missing `codex` must now read 4 as "a working previous `codex` was
restored" and 3 as "nothing was checked or changed", and run the binary itself
when it needs to know whether it works. Take the new launcher and
`setup-env.sh` with REFERENCE §DevContainer lifecycle and §Tool versioning
policy, and rebuild the container: the image copies both files to
`/usr/local/bin/`.

The pre-push gate (`.claude/hooks/pre-push-gate.sh`,
`.codex/hooks/pre-push-gate.sh`) no longer exits 0 silently when it could not
check a command. When its input cannot be read or parsed, `jq` or `git` is
missing, `sed`, `grep`, or `git config` fails, no repository is found for a
push-shaped command, or an approval marker that allowed a force push cannot be
removed, it writes `pre-push gate: not checked: <cause>` to stderr
and does not block. The Claude gate now exits 1 in that case, which Claude
Code shows as a non-blocking hook error; the Codex gate still exits 0, because
the Codex hooks documentation defines only exit 0 and exit 2. The Antigravity
adapter still answers `ask` for every exit but 2, and now writes the same
line to its stderr when the gate exits with anything but 0 or 2 (including a
timeout) or when the adapter cannot run the gate. For a `Cwd` outside any
repository the adapter now passes `Cwd` to the gate instead of the project
root, so a push there is reported as not checked. Block decisions, the
patterns, and the approval markers and their names are unchanged. The force-push block
message now says that the command text matched and that the approval's branch
is the one checked out, not the refspec's, and the credential block message
says the command text matched. A wrapper of your own that read a non-zero
exit from the Claude gate as a block must treat only 2 as a block. Take both
gates, `.agents/hooks/claude-hooks-adapter.sh`, `.devcontainer/verify-template.sh`
(two new cases for the exit codes), the `AGENTS.md` trust-model section, and
REFERENCE §Hooks and §Codex sandbox bypass. No container rebuild is needed:
the hooks run from the mounted checkout.

`.gitignore` now ignores every `.env.*` file except `.env.example` (in place of
`.env.local` and `.env.*.local`), so another instance's env file such as
`.devcontainer/.env.project-b` is no longer offered for commit; take the new
line, no container rebuild is needed. Files already tracked stay tracked, and
`git ls-files -ci --exclude-standard` lists any that the new line covers.

## v3.3.3-rebuild

For an environment that already includes `agy`, update the Claude and Codex
session-start hooks and start a
new agent session. WIP paths containing spaces now keep their task names and
README context. No container rebuild is needed for this hook-only change: the
hooks run from the mounted checkout, not from the image.

### Upgrading from v3.2.0 — container rebuild required

The image adds `agy`; Compose adds `gemini-config` and `antigravity-secrets`
volumes, and the healthcheck runs `agy --version`. This release also corrects
the installer's log prefix display.

1. Merge the template's [.devcontainer/ changes](https://github.com/mememade-github/polyagent-devcontainer/compare/v3.2.0...v3.3.3-rebuild)
   into your project's configuration before rebuilding.
2. Rebuild the image from the merged configuration, then recreate and start the container.
3. Run `agy` inside the started container and complete the [first login](README.md#agents-and-first-login).
4. Update your custom `.claude/rules/` files and regenerate the mirror using the
   [rule registration procedure](REFERENCE.md#registering-deeper-rule-folders).
