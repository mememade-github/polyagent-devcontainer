# Upgrading a consuming project

## v4.0.1-rebuild

Changes since `v3.3.3-rebuild`, as steps for a project built on this
template. Make steps 1 to 8 in one adoption commit: a registration left
without its hook file, a caller left without the file it calls, or a marker
reader left without its writer breaks or blocks commands. REFERENCE.md
describes the resulting behavior; this section lists only what to do.

1. **Keep what is yours.** Your project rules under `.claude/rules/project/`,
   your `PROJECT.md`, your own hooks, and the Git hooks under
   `core.hooksPath` stay. Nothing below removes them.

2. **Move shared duties into `AGENTS.md`.** All three vendors now read the
   shared duties and the four behavioral rules from `AGENTS.md` only.
   - Merge the duties of your `CLAUDE.md` into `AGENTS.md` once. A duty left
     in both files is read twice by Claude; a duty left only in `CLAUDE.md`
     never reaches Codex or Antigravity.
   - Reduce `CLAUDE.md` to `@AGENTS.md`, `@PROJECT.md`, and what applies to
     Claude Code alone.
   - Take the template's `AGENTS.md` sections and keep, if you rewrite them,
     the sentences that make Codex read `PROJECT.md` and every `.md` file
     under `.agents/rules/project/` at session start, and the one that says
     Antigravity receives `PROJECT.md` from the hook adapter. Keep
     `.agents/rules.json`.
   - Drop from your `CLAUDE.md` and `AGENTS.md`: the `MEMORY.md` clause of
     the session-start bullet, the `@` import and read instruction for
     `devcontainer-patterns.md`, the `karpathy-guidelines` invocation, the
     duty to run the checker before every commit, and any "Preserve
     verification markers" instruction. The removed check concerned a
     `MEMORY.md` at the repository root, which no template component
     creates; Claude Code's automatic memory is stored outside the
     repository and is not affected. A project that keeps its own memory
     file names its path and purpose in its own governance.
   - Where your documents or scripts ran `docker compose --project-directory
     <HOST_PATH>` from inside the container, set `HOST_WORKSPACE_PATH` alone
     (REFERENCE §Docker from inside the container): `--project-directory`
     also moves the build context to a path the CLI there cannot read.

3. **Delete the removed files.** Copying the new template files over yours
   does not remove these.

   | Kind | Paths |
   |------|-------|
   | Skills | `.claude/skills/refine/`, `.claude/skills/karpathy-guidelines/` |
   | Hooks | `.claude/hooks/refinement-gate.sh`, `.codex/hooks/refinement-gate.sh`, `.claude/hooks/pre-commit-gate.sh`, `.codex/hooks/pre-commit-gate.sh` |
   | Rules | `.claude/rules/behavioral-core.md`, `.claude/rules/devcontainer-patterns.md` |
   | Scripts | `scripts/meta/karpathy-consistency-check.sh`, `scripts/meta/lib/detect-root.sh`, and `scripts/meta/lib/` if it is then empty |

   Their generated copies under `.agents/skills/` and `.agents/rules/` go in
   step 7.

4. **Remove their registrations and callers.**
   - The `Stop` entries in `.claude/settings.json`, `.codex/hooks.json` and
     `.agents/hooks.json`.
   - The `PreToolUse` entries for `pre-commit-gate.sh` in
     `.claude/settings.json` and `.codex/hooks.json`.
   - The skill rows for `refine` and `karpathy-guidelines` in your README
     and REFERENCE.
   - Any script or setting of your own that calls a deleted file, and any
     tool of your own that waits for a verification marker: no template
     component writes one now.

5. **Remove the old local state, then its ignore lines.** Delete these if
   they exist, then remove their lines from `.gitignore`. A marker left
   behind without its ignore line is an untracked file that `git add -A`
   commits.

   | Where | Paths |
   |-------|-------|
   | `.claude/` | `.refinement-active`, `.stop-blocked-refinement.*`, `.refine-output`, `.refine-eval.json`, `agent-memory/refinement/`, `.last-verification.*`, `.allow-force-push.*` |
   | `.codex/state/` | `refinement-active`, `stop-blocked-refinement.*`, `.refine-output`, `.refine-eval.json`, `refinement/`, `last-verification.*`, `allow-force-push.*`, `.gitkeep`, then the directory if it is empty |
   | `.gitignore` lines | `.claude/.last-verification*`, `.claude/.stop-blocked*`, `.claude/.refinement-active`, `.claude/.refine-output`, `.claude/.refine-eval.json`, `.claude/agent-memory/refinement/`, `.claude/.allow-force-push*`, and the `.codex/state/` lines `last-verification*`, `allow-force-push*`, `stop-blocked*`, `refinement-active`, `.refine-output`, `.refine-eval.json`, `refinement/` |

   The `.allow-force-push.*` files were the pre-push gates' force-push
   approval markers; the gates no longer read them (step 8).

6. **Take these files together.**
   - Hooks: `.claude/hooks/pre-push-gate.sh`, `.codex/hooks/pre-push-gate.sh`,
     both `session-start.sh` (no `MEMORY.md` block, no marker pruning),
     `.claude/settings.json`, `.codex/hooks.json`,
     `.agents/hooks.json`, and `.agents/hooks/claude-hooks-adapter.sh`. The
     adapter now calls only `pre-push-gate.sh` and `session-start.sh` and
     appends the repository root `PROJECT.md`, when it is non-empty and
     readable, to Antigravity's session-start message; agy 1.5.18 kept only
     about the first 48 KB of that message.
   - Roles and skills: `.claude/agents/evaluator.md`, the `status` and
     `verify` skills.
   - Scripts: `scripts/meta/run-isolated-role.sh`,
     `scripts/meta/completion-checker.sh`, `scripts/sync-agents-mirror.sh`,
     `scripts/git/git-status.sh`, `.devcontainer/verify-template.sh`.
   - Image files: `.devcontainer/Dockerfile` (its mount-point `mkdir -p`
     line now lists `${HOME}/.codex`; add it to the same line if you keep
     your own Dockerfile), `.devcontainer/setup-env.sh`,
     `.devcontainer/codex-launcher.sh`, `.devcontainer/entrypoint.sh`.
   - Configuration and documents: `.codex/config.toml`, `.gitignore`,
     `.gitattributes`, README, REFERENCE, and the `AGENTS.md` and `CLAUDE.md`
     of step 2.
   - Automatic memory: `.claude/settings.json` (`env`) and
     `.devcontainer/devcontainer.json` (`remoteEnv`) no longer set
     `CLAUDE_CODE_DISABLE_AUTO_MEMORY=0`, which forced Claude Code's
     automatic memory on. The default is still on, and a user setting that
     turns it off (`autoMemoryEnabled: false`, `--bare`) now takes effect.
     A project that wants it forced on keeps that variable in its own
     settings. On path A this takes effect after the rebuild of step 10.
   - Docker socket: step 1 of `.devcontainer/setup-env.sh` now changes the
     group of a socket whose group is 0 to the container's `docker` group;
     before, it left such a socket unusable by the container user without a
     warning. A socket with another group is still matched by changing the
     `docker` group's number, and a socket whose group cannot be read now
     prints a WARN. The changed group applies to the shared socket, which
     other containers and possibly the host see (REFERENCE §Docker from
     inside the container). If
     your own startup changes the socket's group whatever its number, take
     this step 1 block in its place. It takes effect after the rebuild of
     step 10.

7. **Regenerate the mirror** once, after steps 2 to 6:
   `bash scripts/sync-agents-mirror.sh`. It removes `.agents/skills/refine/`,
   `.agents/skills/karpathy-guidelines/`, `.agents/rules/behavioral-core.md`
   and `.agents/rules/devcontainer-patterns.md` and rewrites the evaluator,
   status and verify copies; `--dry` then reports 0 changes. It leaves
   `.agents/hooks.json`, `.agents/hooks/` and `.agents/rules.json` alone.

8. **Update your own callers for the changed contracts.**

   | Component | What a caller must now read |
   |-----------|-----------------------------|
   | Pre-push gates | Exit 2 blocks. The Claude gate exits 1 when it could not check a command and Claude Code still runs the command; treat only 2 as a block. The Codex gate exits 0 for both checked and unchecked. The cause is the stderr line `pre-push gate: not checked: <cause>`. The gates no longer block force pushes and read no approval marker; a force push passes them like any other push. Where your operation relied on that block, get approval as `AGENTS.md` requires and set each vendor's permission settings to ask before such a command; remove any script or instruction of your own that creates an approval marker. |
   | Antigravity adapter | Gate exit 2 answers `deny`; every other result answers `ask`, which is not an approval, and an unchecked run writes the not-checked line to the adapter's stderr. For a `Cwd` outside any repository the gate gets `Cwd`, so a push there is not checked. |
   | `run-isolated-role.sh evaluate <project-root> <prompt-file> <output-file>` | The prompt supplies the evaluator role body, the permitted inputs (authorized request, acceptance conditions, actual diff, relevant repository facts, execution evidence) and the repository location; the helper appends a line naming `<output-file>` as the report path, which overrides any report path in the prompt. It fails when the evaluator process fails or leaves no non-empty report at `<output-file>`, and it does not check the report's content or format. |
   | `completion-checker.sh` | Writes no marker. Prints `Leak patterns:`, then `NOT CHECKED:` for a check that could not run (the TOML parse without python3 `tomllib`, as in this image's python3 3.10), then `OK:` or `FAILED:`. Exits 1 when a check failed or could not read its input, including a missing `jq`, an unreadable pattern file, a `scripts/meta/leak-patterns.txt` with no patterns, and a `git grep` error. |
   | `verify-template.sh` | No `RESULT: N PASS / N FAIL / N SKIP` line and no Compose section. Exits 0 (all required checks ran and passed), 1 (a check failed) or 2 (nothing failed but a required check did not run); a missing optional tool, including Docker, does not change the exit code. |
   | `sync-agents-mirror.sh` | Exits 1 when `find`, `diff` or `stat` fails, before printing a result or changing files. Rejects symlinks only in `.agents/rules/`, `.agents/skills/` and their `.claude/` sources. No longer rejects text naming `CLAUDE_PROJECT_DIR`. |
   | `codex-launcher --update-only` | 0: reinstalled or already latest, or `SKIP_CODEX_UPDATE=1` is set, in which case nothing was checked or changed. 3: nothing checked or changed (npm missing, or the registry unreachable while the real binary is executable). 4: the reinstall failed and a working previous `codex` was restored. 5: the reinstall failed and no working `codex` is installed. Run the binary yourself when you need to know that it works. |
   | Antigravity in this container | In `agy -p` sessions (agy 1.5.18) commands did not run without `--dangerously-skip-permissions` or a session setting that replaces it (`"toolPermission": "always-proceed"`, or `--mode accept-edits` with a matching `permissions.allow` rule): they went to the terminal sandbox, which fails under Docker's default seccomp profile. Commands run that way are not sandboxed; see REFERENCE §Antigravity CLI (agy). |
   | Startup steps 3 and 4 | Step 3 prints a "not installed" WARN and skips the update when `claude` is not on PATH; step 4 does the same when the real `codex` binary is not executable and npm is missing. Otherwise `SKIP_CLAUDE_UPDATE=1` or `SKIP_CODEX_UPDATE=1` makes the step print `Skipped (...)`, and the step does not check for or install an update. When the update runs, "already latest" appears only after a checked update, and a failed update, or a Codex update whose latest version could not be checked, prints a WARN. |

9. **Ignore and line-ending rules.** `.gitignore` now ignores every `.env.*`
   file except `.env.example`, in place of `.env.local` and `.env.*.local`.
   Files already tracked stay tracked; `git ls-files -ci --exclude-standard`
   lists any that the new line covers. `.gitignore` no longer ignores
   `/.gitlab-ci.yml`, so a local-only `.gitlab-ci.yml` now shows as an
   untracked file; to keep it local, add `/.gitlab-ci.yml` to your
   `.gitignore` or to `.git/info/exclude`. `.gitattributes` now keeps `*.json`,
   `*.yml`, `*.yaml`, `.gitattributes` and `.gitignore` LF;
   `git add --renormalize .` stages any of them stored with CRLF.

10. **Rebuild only for the image files and path A's configuration.** The
    image copies `setup-env.sh`, `codex-launcher.sh` and `entrypoint.sh` into
    `/usr/local/bin/`, and the Dockerfile creates the `~/.codex` mount point.
    Rebuild the image and recreate the container for those (A: **Dev
    Containers: Rebuild Container**; B: the `up -d --build --force-recreate`
    command in REFERENCE §DevContainer lifecycle). On A the same rebuild
    applies the `devcontainer.json` of step 6; until then, terminals of the
    existing container and every process started from them, Claude
    sessions included, keep `CLAUDE_CODE_DISABLE_AUTO_MEMORY=0`. An
    existing `codex-config` volume keeps its owner. Everything else runs
    from the mounted checkout: start new agent sessions, and on Codex review
    the changed hooks in `/hooks`.

11. **Check.** Run `bash scripts/meta/completion-checker.sh` and
    `bash .devcontainer/verify-template.sh`. They check the files and feed
    synthetic input to the hooks; observe a normal container start and an
    agent session separately.

To roll back, restore the earlier version's hook files, registrations,
adapter, scripts, skills, roles, ignore lines, image files and documents
together, run the sync, and rebuild if you had rebuilt. An old verification
marker is not evidence that the current tree was checked.

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
