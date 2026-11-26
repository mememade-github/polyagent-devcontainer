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
entries. Preserve verification markers.

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
the "karpathy pair" case from section [6/7] of `.devcontainer/verify-template.sh`,
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
