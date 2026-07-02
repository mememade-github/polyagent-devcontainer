#!/bin/bash
# Template verification — defaults to /workspaces, override via PROJECT_DIR.
# Designed for use both inside a polyagent-derived devcontainer (where /workspaces IS the
# project) and from outside (where PROJECT_DIR points at the template directory).
PROJECT_DIR="${PROJECT_DIR:-/workspaces}"

echo "=============================================="
echo "  Template Full Verification"
echo "  PROJECT_DIR: $PROJECT_DIR"
echo "=============================================="
echo ""

PASS=0
FAIL=0
record() { [ "$1" = "PASS" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1)); echo "$1: $2"; }
workspace_marker_ok() {
    root=$1
    [ -d "$root/.git" ] ||
        [ -f "$root/AGENTS.md" ] ||
        [ -f "$root/CLAUDE.md" ] ||
        [ -f "$root/README.md" ] ||
        [ -d "$root/.devcontainer" ]
}
resolve_host_workspace_path() {
    if [ -n "${HOST_WORKSPACE_PATH:-}" ]; then
        printf '%s\n' "$HOST_WORKSPACE_PATH"
        return 0
    fi
    case "$PROJECT_DIR" in
        /workspaces|/workspaces/*)
            if [ -f /.dockerenv ] && command -v docker >/dev/null 2>&1; then
                container_id=$(cat /etc/hostname 2>/dev/null || true)
                host_root=$(docker inspect "$container_id" --format '{{range .Mounts}}{{if eq .Destination "/workspaces"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)
                if [ -n "$host_root" ]; then
                    printf '%s%s\n' "$host_root" "${PROJECT_DIR#/workspaces}"
                    return 0
                fi
            fi
            ;;
    esac
    printf '%s\n' "$PROJECT_DIR"
}
compose_run_probe() {
    project=$1
    host_workspace=$2
    shift 2
    (
        cd "$PROJECT_DIR/.devcontainer" &&
            COMPOSE_PROJECT_NAME="$project" HOST_WORKSPACE_PATH="$host_workspace" \
            docker compose run --rm --no-deps \
                -e SKIP_CLAUDE_UPDATE=1 -e SKIP_CODEX_UPDATE=1 \
                --entrypoint bash polyagent-devcontainer -lc "$*"
    )
}
compose_cleanup() {
    project=$1
    (
        cd "$PROJECT_DIR/.devcontainer" &&
            COMPOSE_PROJECT_NAME="$project" docker compose down -v --remove-orphans >/dev/null 2>&1 || true
    )
}
frontmatter_header() {
    awk 'BEGIN{n=0} /^---$/{n++; if(n==2) exit; next} n==1{print}' "$1"
}
flat_frontmatter_valid() {
    file=$1
    expected_keys=$2
    [ "$(head -1 "$file" 2>/dev/null)" = "---" ] || return 1
    [ "$(grep -n '^---$' "$file" 2>/dev/null | sed -n '2p' | cut -d: -f1)" -gt 1 ] 2>/dev/null || return 1
    header=$(frontmatter_header "$file")
    actual_keys=$(printf '%s\n' "$header" | sed -n 's/^\([A-Za-z][A-Za-z0-9-]*\):.*/\1/p' | sort)
    expected_sorted=$(printf '%s\n' $expected_keys | sort)
    [ "$actual_keys" = "$expected_sorted" ] || return 1
    while IFS= read -r line; do
        printf '%s\n' "$line" | grep -qE '^[A-Za-z][A-Za-z0-9-]*:[[:space:]]+[^[:space:]].*$' || return 1
        value=${line#*:}
        value=$(printf '%s' "$value" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$value" ] && [ "$value" != '""' ] && [ "$value" != "''" ] && [ "$value" != "|" ] && [ "$value" != ">" ] || return 1
    done <<< "$header"
}

# --- PHASE 1: Runtime ---
echo "=== Phase 1: Runtime ==="
claude --version > /dev/null 2>&1 && record PASS "claude CLI" || record FAIL "claude CLI"
(command -v codex >/dev/null 2>&1 || [ -x /home/vscode/.npm-global/bin/codex ]) \
    && (codex --version > /dev/null 2>&1 || /home/vscode/.npm-global/bin/codex --version > /dev/null 2>&1) \
    && record PASS "codex CLI" || record FAIL "codex CLI"
node --version > /dev/null 2>&1 && record PASS "node ($(node --version))" || record FAIL "node"
/home/vscode/.local/bin/uv --version > /dev/null 2>&1 && record PASS "uv" || record FAIL "uv"
python3 --version > /dev/null 2>&1 && record PASS "python3 ($(python3 --version 2>&1))" || record FAIL "python3"

# --- PHASE 1a: Workspace mount and persistence ---
echo ""
echo "=== Phase 1a: Workspace Mount + Persistence ==="
workspace_marker_ok "$PROJECT_DIR" && record PASS "workspace marker: PROJECT_DIR recognizable" || record FAIL "workspace marker: PROJECT_DIR recognizable"
if grep -Fq 'SKIP_CODEX_UPDATE=1 codex --version' "$PROJECT_DIR/.devcontainer/docker-compose.yml" 2>/dev/null &&
    grep -Fq 'test -f /workspaces/AGENTS.md' "$PROJECT_DIR/.devcontainer/docker-compose.yml" 2>/dev/null; then
    record PASS "docker-compose healthcheck: CLI + workspace marker"
else
    record FAIL "docker-compose healthcheck: CLI + workspace marker"
fi
if grep -Fq 'workspace_marker_ok "$WS"' "$PROJECT_DIR/.devcontainer/setup-env.sh" 2>/dev/null &&
    grep -Fq 'ERROR: /workspaces has no project marker' "$PROJECT_DIR/.devcontainer/setup-env.sh" 2>/dev/null; then
    record PASS "setup-env: missing workspace marker is explicit"
else
    record FAIL "setup-env: missing workspace marker is explicit"
fi
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    HOST_PROJECT_DIR=$(resolve_host_workspace_path)
    COMPOSE_PROJECT="polyagent-verify-$$"
    WORKSPACE_PROBE=$(compose_run_probe "$COMPOSE_PROJECT" "$HOST_PROJECT_DIR" 'test -d /workspaces/.git && test -f /workspaces/AGENTS.md && test -f /workspaces/.devcontainer/verify-template.sh && echo workspace-ok' 2>&1 || true)
    if printf '%s' "$WORKSPACE_PROBE" | grep -Fq 'workspace-ok'; then
        record PASS "compose runtime: /workspaces contains template repo"
    else
        record FAIL "compose runtime: /workspaces contains template repo"
        printf '%s\n' "$WORKSPACE_PROBE" | tail -20 | sed 's/^/      compose: /'
    fi
    PERSIST_PROJECT="polyagent-persist-$$"
    PERSIST_WRITE=$(compose_run_probe "$PERSIST_PROJECT" "$HOST_PROJECT_DIR" 'printf persisted > "$HOME/.codex/verify-persistence" && echo wrote' 2>&1 || true)
    PERSIST_READ=$(compose_run_probe "$PERSIST_PROJECT" "$HOST_PROJECT_DIR" 'grep -qx persisted "$HOME/.codex/verify-persistence" && echo persistence-ok' 2>&1 || true)
    if printf '%s' "$PERSIST_WRITE" | grep -Fq 'wrote' && printf '%s' "$PERSIST_READ" | grep -Fq 'persistence-ok'; then
        record PASS "compose runtime: codex-config named volume persists across containers"
    else
        record FAIL "compose runtime: codex-config named volume persists across containers"
        printf '%s\n' "$PERSIST_WRITE" "$PERSIST_READ" | tail -20 | sed 's/^/      compose: /'
    fi
    compose_cleanup "$COMPOSE_PROJECT"
    compose_cleanup "$PERSIST_PROJECT"
else
    record FAIL "compose runtime: docker daemon unavailable"
fi

# --- PHASE 1b: setup-env.sh lifecycle integrity ---
echo ""
echo "=== Phase 1b: setup-env.sh lifecycle ==="
SETUP="$PROJECT_DIR/.devcontainer/setup-env.sh"
grep -q 'STEP_TOTAL=5' "$SETUP" 2>/dev/null && record PASS "setup-env: STEP_TOTAL=5" || record FAIL "setup-env: STEP_TOTAL (expected 5)"
grep -q 'SKIP_CLAUDE_UPDATE' "$SETUP" 2>/dev/null && record PASS "setup-env: Claude update step" || record FAIL "setup-env: Claude update step"
grep -q 'SKIP_CODEX_UPDATE' "$SETUP" 2>/dev/null && record PASS "setup-env: Codex update step (SKIP_CODEX_UPDATE)" || record FAIL "setup-env: Codex update step"
grep -Fq '${localEnv:HOME}${localEnv:USERPROFILE}/.ssh' "$PROJECT_DIR/.devcontainer/devcontainer.json" 2>/dev/null && record PASS "devcontainer: SSH mount supports Windows USERPROFILE fallback" || record FAIL "devcontainer: SSH mount USERPROFILE fallback"
grep -Fq 'No SSH files (optional)' "$SETUP" 2>/dev/null && record PASS "setup-env: empty SSH dir is not reported as keys" || record FAIL "setup-env: empty SSH dir diagnostic"
grep -q '@openai/codex@latest' "$PROJECT_DIR/.devcontainer/codex-launcher.sh" 2>/dev/null && record PASS "codex-launcher: Codex update via prefix npm (not codex update)" || record FAIL "codex-launcher: Codex update mechanism"
grep -Fq 'npm install -g --prefix "${HOME}/.npm-global" @openai/codex' "$PROJECT_DIR/.devcontainer/Dockerfile" 2>/dev/null && record PASS "Dockerfile: Codex install uses explicit npm prefix" || record FAIL "Dockerfile: Codex install prefix"
grep -Fq 'COPY codex-launcher.sh /usr/local/bin/codex-launcher' "$PROJECT_DIR/.devcontainer/Dockerfile" 2>/dev/null && record PASS "Dockerfile: Codex launcher copied" || record FAIL "Dockerfile: Codex launcher copied"
grep -Fq 'ln -sf /usr/local/bin/codex-launcher /usr/local/bin/codex' "$PROJECT_DIR/.devcontainer/Dockerfile" 2>/dev/null && record PASS "Dockerfile: Codex command points at launcher" || record FAIL "Dockerfile: Codex launcher command"
grep -Fq 'npm config set prefix' "$PROJECT_DIR/.devcontainer/Dockerfile" 2>/dev/null && record FAIL "Dockerfile: persistent npm prefix mutation" || record PASS "Dockerfile: no persistent npm prefix mutation"
LAUNCHER="$PROJECT_DIR/.devcontainer/codex-launcher.sh"
[ -f "$LAUNCHER" ] && record PASS "codex-launcher: exists" || record FAIL "codex-launcher: exists"
bash -n "$LAUNCHER" 2>/dev/null && record PASS "codex-launcher: syntax" || record FAIL "codex-launcher: syntax"
grep -Fq 'CODEX_REAL_BIN="${CODEX_REAL_BIN:-${CODEX_NPM_PREFIX}/bin/codex}"' "$LAUNCHER" 2>/dev/null && record PASS "codex-launcher: real npm binary explicit" || record FAIL "codex-launcher: real npm binary explicit"
grep -Fq 'codex_latest_version()' "$LAUNCHER" 2>/dev/null && record PASS "codex-launcher: latest-version probe" || record FAIL "codex-launcher: latest-version probe"
grep -Fq 'npm install -g --prefix "$CODEX_NPM_PREFIX" @openai/codex@latest' "$LAUNCHER" 2>/dev/null && record PASS "codex-launcher: update uses explicit npm prefix" || record FAIL "codex-launcher: update uses explicit npm prefix"
grep -Fq -- '--update-only' "$LAUNCHER" 2>/dev/null && record PASS "codex-launcher: update-only entrypoint" || record FAIL "codex-launcher: update-only entrypoint"
grep -Fq 'exec "$CODEX_REAL_BIN" "$@"' "$LAUNCHER" 2>/dev/null && record PASS "codex-launcher: re-execs real binary" || record FAIL "codex-launcher: re-execs real binary"
grep -nE '^[^#]*\bcodex[[:space:]]+update\b' "$LAUNCHER" >/dev/null 2>&1 && record FAIL "codex-launcher: avoids direct codex update" || record PASS "codex-launcher: avoids direct codex update"
grep -Fq '"$CODEX_LAUNCHER" --update-only' "$SETUP" 2>/dev/null && record PASS "setup-env: Codex update delegated to launcher" || record FAIL "setup-env: Codex update delegated to launcher"
grep -Fq 'CODEX_LAUNCHER="/usr/local/bin/codex-launcher"' "$SETUP" 2>/dev/null && record PASS "setup-env: Codex launcher reconciliation" || record FAIL "setup-env: Codex launcher reconciliation"
grep -q 'CODEX_UPDATE_LOG' "$SETUP" 2>/dev/null && record PASS "setup-env: Codex update failures are visible" || record FAIL "setup-env: Codex update failure visibility"
if grep -Fq '/usr/local/bin/codex-launcher' "$PROJECT_DIR/REFERENCE.md" 2>/dev/null &&
    grep -Fq '~/.npm-global/bin/codex' "$PROJECT_DIR/REFERENCE.md" 2>/dev/null &&
    grep -Fq 're-execs' "$PROJECT_DIR/REFERENCE.md" 2>/dev/null; then
    record PASS "REFERENCE: Codex launcher/runtime boundary documented"
else
    record FAIL "REFERENCE: Codex launcher/runtime boundary documented"
fi
grep -Fq "set npm's global prefix" "$PROJECT_DIR/REFERENCE.md" 2>/dev/null && record FAIL "REFERENCE: stale persistent npm prefix claim" || record PASS "REFERENCE: no stale persistent npm prefix claim"
if grep -Fq 'cp "$WORKSPACE_CODEX_CONFIG" "$USER_CODEX_CONFIG"' "$SETUP" 2>/dev/null; then
    record FAIL "setup-env: project config copied into persistent user config"
else
    record PASS "setup-env: project config loaded directly, not copied"
fi

# --- PHASE 1c: Codex config hygiene ---
echo ""
echo "=== Phase 1c: Codex config hygiene ==="
CODEX_CONFIG="$PROJECT_DIR/.codex/config.toml"
grep -q '^hooks = true$' "$CODEX_CONFIG" 2>/dev/null && ! grep -q 'codex_hooks' "$CODEX_CONFIG" 2>/dev/null && record PASS "Codex config: modern hooks feature flag" || record FAIL "Codex config: hooks feature flag"
grep -q '^approval_policy = "on-request"$' "$CODEX_CONFIG" 2>/dev/null && ! grep -q '^ask_for_approval[[:space:]]*=' "$CODEX_CONFIG" 2>/dev/null && record PASS "Codex config: current approval_policy key" || record FAIL "Codex config: obsolete approval key"
! grep -Eq 'model_availability_nux|model_migrations|^\[tui\.|^\[notice\.' "$CODEX_CONFIG" 2>/dev/null && record PASS "Codex config: no runtime-state blocks" || record FAIL "Codex config: runtime-state block leaked"
STRICT_HOME=$(mktemp -d)
cp "$CODEX_CONFIG" "$STRICT_HOME/config.toml"
CODEX_CMD=$(command -v codex 2>/dev/null || echo /home/vscode/.npm-global/bin/codex)
STRICT_OUTPUT=$(CODEX_HOME="$STRICT_HOME" "$CODEX_CMD" exec --strict-config --ephemeral -c model_provider='"__config_probe__"' "configuration probe" 2>&1 || true)
if printf '%s' "$STRICT_OUTPUT" | grep -Fq 'Model provider `__config_probe__` not found' && ! printf '%s' "$STRICT_OUTPUT" | grep -Fq 'unknown configuration field'; then
    record PASS "Codex config: strict parser accepts tracked schema"
else
    record FAIL "Codex config: strict parser rejected tracked schema"
fi
rm -r "$STRICT_HOME"
USER_CODEX_CONFIG="${HOME}/.codex/config.toml"
if [ -L "$USER_CODEX_CONFIG" ] && [ "$(readlink "$USER_CODEX_CONFIG")" = "$CODEX_CONFIG" ]; then
    record FAIL "Codex user config: legacy symlink still points at tracked config"
else
    record PASS "Codex user config: no tracked-config symlink"
fi

# --- PHASE 1d: Governance regression guards ---
echo ""
echo "=== Phase 1d: Governance regression guards ==="
CODEX_PRECOMMIT="$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh"
CLAUDE_PRECOMMIT="$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh"
grep -Fq '[ -f "$CHECKER" ]' "$CODEX_PRECOMMIT" 2>/dev/null && record PASS "Codex pre-commit: checker may be 0644" || record FAIL "Codex pre-commit: checker exec contract"
if grep -Fq 'MARKER=' "$CODEX_PRECOMMIT" 2>/dev/null && ! grep -Fq 'touch "$MARKER"' "$CODEX_PRECOMMIT" 2>/dev/null; then record PASS "Codex pre-commit: marker read-only (checker writes it)"; else record FAIL "Codex pre-commit: marker read-only contract"; fi
grep -Fq 'sk-[A-Za-z0-9_-]{20,}' "$CODEX_PRECOMMIT" 2>/dev/null && record PASS "Codex pre-commit: sk-* secret pattern" || record FAIL "Codex pre-commit: sk-* secret pattern"
grep -Fq 'sk-[A-Za-z0-9_-]{20,}' "$CLAUDE_PRECOMMIT" 2>/dev/null && record PASS "Claude pre-commit: sk-* secret pattern" || record FAIL "Claude pre-commit: sk-* secret pattern"
grep -Fq 'bash "$WORKSPACE_ROOT/scripts/git/git-status.sh" --brief' "$PROJECT_DIR/.claude/skills/status/SKILL.md" 2>/dev/null && record PASS "status skill: bash invocation contract" || record FAIL "status skill: bash invocation contract"
grep -Fq 'scripts/meta/completion-checker.sh"' "$PROJECT_DIR/.claude/skills/verify/SKILL.md" 2>/dev/null && record PASS "verify skill: bash invocation contract" || record FAIL "verify skill: bash invocation contract"
grep -Fq 'bash "$WORKSPACE_ROOT/scripts/git/git-status.sh" --brief' "$PROJECT_DIR/.agents/skills/status/SKILL.md" 2>/dev/null && record PASS "status skill mirror: bash invocation contract" || record FAIL "status skill mirror: bash invocation contract"
grep -Fq 'scripts/meta/completion-checker.sh"' "$PROJECT_DIR/.agents/skills/verify/SKILL.md" 2>/dev/null && record PASS "verify skill mirror: bash invocation contract" || record FAIL "verify skill mirror: bash invocation contract"
grep -Fq 'CODEX_CI' "$PROJECT_DIR/.claude/skills/refine/SKILL.md" 2>/dev/null && grep -Fq '.codex/state' "$PROJECT_DIR/.claude/skills/refine/SKILL.md" 2>/dev/null && record PASS "refine: Codex host/state resolver" || record FAIL "refine: Codex host/state resolver"
grep -Fq 'codex exec --ephemeral' "$PROJECT_DIR/.claude/skills/refine/SKILL.md" 2>/dev/null && record PASS "refine: Codex fresh-role isolation" || record FAIL "refine: Codex fresh-role isolation"
grep -Fq 'CODEX_CI' "$PROJECT_DIR/.claude/skills/status/SKILL.md" 2>/dev/null && grep -Fq 'MARKER_PREFIX=".last-verification."' "$PROJECT_DIR/.claude/skills/status/SKILL.md" 2>/dev/null && grep -Fq 'MARKER_PREFIX="last-verification."' "$PROJECT_DIR/.claude/skills/status/SKILL.md" 2>/dev/null && record PASS "status: vendor state/marker resolver" || record FAIL "status: vendor state/marker resolver"
grep -Fq 'CODEX_CI' "$PROJECT_DIR/scripts/meta/completion-checker.sh" 2>/dev/null && grep -Fq 'last-verification.$BRANCH_SAFE' "$PROJECT_DIR/scripts/meta/completion-checker.sh" 2>/dev/null && record PASS "completion-checker: vendor marker resolver" || record FAIL "completion-checker: vendor marker resolver"
if [ -e "$PROJECT_DIR/.cursor" ]; then
    record FAIL "scope-membership: .cursor removed"
else
    record PASS "scope-membership: .cursor removed"
fi
if [ -d "$PROJECT_DIR/variants" ]; then
    record FAIL "scope-membership: stale variants/ removed"
else
    record PASS "scope-membership: stale variants/ removed"
fi
grep -Fq '.vscode/' "$PROJECT_DIR/PROJECT.md" 2>/dev/null && record PASS "scope-membership: .vscode documented as editor settings" || record FAIL "scope-membership: .vscode documentation"

# --- PHASE 1e: secret-pattern false-positive regression (audit-discipline §2) ---
# Phase 1d asserts the sk- pattern STRING is present (positive axis only). This
# guard exercises BOTH axes against BOTH live hook patterns: a real sk- key is
# still detected, AND the repo's own `task-YYYYMMDD-description` convention is
# NOT flagged (the bare sk- run over-matched any "...sk-<20+ word/hyphen chars>").
# Fixtures are fragment-built / boundary-safe so this file never trips the gate it
# tests.
echo ""
echo "=== Phase 1e: Secret-pattern false-positive regression ==="
_sk_key="sk-proj-$(printf '%s' 'T3BlbkFJabcdefghij0123456789')"
_task_path="wip/task-YYYYMMDD-description/README.md"
_claude_secret_line=$(grep -m1 '^SECRET_PATTERNS=' "$CLAUDE_PRECOMMIT" 2>/dev/null)
_codex_secret_line=$(grep -m1 '^SECRET_PATTERNS=' "$CODEX_PRECOMMIT" 2>/dev/null)
[ -n "$_claude_secret_line" ] && [ "$_claude_secret_line" = "$_codex_secret_line" ] && record PASS "secret-pattern: Claude/Codex pattern parity" || record FAIL "secret-pattern: Claude/Codex pattern parity"
for _hook_spec in "Claude:$_claude_secret_line" "Codex:$_codex_secret_line"; do
    _hook_name=${_hook_spec%%:*}
    _secret_line=${_hook_spec#*:}
    _secret_pattern=${_secret_line#SECRET_PATTERNS=}
    _secret_pattern=${_secret_pattern#\'}
    _secret_pattern=${_secret_pattern%\'}
    if [ -z "$_secret_line" ] || [ "$_secret_pattern" = "$_secret_line" ]; then
        record FAIL "$_hook_name secret-pattern: live pattern parse"
        continue
    fi
    printf '%s' "$_sk_key" | grep -qE "$_secret_pattern" && record PASS "$_hook_name secret-pattern: detects real sk- key (positive)" || record FAIL "$_hook_name secret-pattern: missed real sk- key"
    printf '%s' "$_task_path" | grep -qE "$_secret_pattern" && record FAIL "$_hook_name secret-pattern: FALSE POSITIVE on task-YYYYMMDD-description" || record PASS "$_hook_name secret-pattern: no FP on hyphenated identifier (regression)"
done

# --- PHASE 2: Config files ---
echo ""
echo "=== Phase 2: Config Files ==="
[ -f "$PROJECT_DIR/.claude/settings.json" ] && record PASS "settings.json exists" || record FAIL "settings.json"
jq -e . "$PROJECT_DIR/.claude/settings.json" >/dev/null 2>&1 && record PASS "settings.json valid JSON" || record FAIL "settings.json invalid JSON"
grep -q '"SessionStart"' "$PROJECT_DIR/.claude/settings.json" 2>/dev/null && record PASS "SessionStart hook registered" || record FAIL "SessionStart hook"
grep -q '"Stop"' "$PROJECT_DIR/.claude/settings.json" 2>/dev/null && record PASS "Stop hook registered" || record FAIL "Stop hook"
if jq -e '[.hooks.PreToolUse[]?.hooks[]? | select((.command // "") | contains("pre-commit-gate.sh") or contains("pre-push-gate.sh")) | has("if")] | any | not' "$PROJECT_DIR/.claude/settings.json" >/dev/null 2>&1; then
    record PASS "Claude PreToolUse: git gates run on all Bash commands"
else
    record FAIL "Claude PreToolUse: git gates still have narrow if filters"
fi
[ -f "$PROJECT_DIR/.codex/config.toml" ] && record PASS ".codex/config.toml exists" || record FAIL ".codex/config.toml"
[ -f "$PROJECT_DIR/.codex/hooks.json" ] && record PASS ".codex/hooks.json exists" || record FAIL ".codex/hooks.json"
jq -e . "$PROJECT_DIR/.codex/hooks.json" >/dev/null 2>&1 && record PASS "hooks.json valid JSON" || record FAIL "hooks.json invalid JSON"
CODEX_HOOK_SCHEMA='
  (.hooks | type == "object") and
  ((.hooks | keys | sort) == ["PreToolUse", "SessionStart", "Stop"]) and
  ([.hooks | to_entries[] | .value[]] | all(
    (.hooks | type == "array") and
    (.hooks | length > 0) and
    (.hooks | all(
      (. | type == "object") and
      .type == "command" and
      (.command | type == "string") and
      (.command | length > 0) and
      ((.timeout // 600) | type == "number")
    ))
  )) and
  (.hooks.PreToolUse | all(.matcher == "Bash"))
'
if jq -e "$CODEX_HOOK_SCHEMA" "$PROJECT_DIR/.codex/hooks.json" >/dev/null 2>&1; then
    record PASS "hooks.json current Codex nested schema"
else
    record FAIL "hooks.json unsupported Codex schema"
fi
LEGACY_HOOKS='{"hooks":{"Stop":[{"command":"true","timeout":10}]}}'
if printf '%s' "$LEGACY_HOOKS" | jq -e "$CODEX_HOOK_SCHEMA" >/dev/null 2>&1; then
    record FAIL "hooks.json schema guard accepted legacy direct command"
else
    record PASS "hooks.json schema guard rejects legacy direct command"
fi
[ -f "$PROJECT_DIR/AGENTS.md" ] && record PASS "AGENTS.md exists" || record FAIL "AGENTS.md"
NON_EXEC_755=$(git -C "$PROJECT_DIR" ls-files -s 2>/dev/null | awk '$1 == "100755" && $4 !~ /^(\.claude\/hooks\/.*\.sh|\.codex\/hooks\/.*\.sh|\.devcontainer\/entrypoint\.sh|\.devcontainer\/setup-env\.sh|\.devcontainer\/verify-template\.sh|scripts\/sync-agents-mirror\.sh|scripts\/meta\/run-isolated-role\.sh)$/ { print $4 }')
if [ -z "$NON_EXEC_755" ]; then
    record PASS "file modes: executable bit limited to executable scripts"
else
    record FAIL "file modes: unexpected executable bit"
    printf '%s\n' "$NON_EXEC_755" | sed 's/^/      mode: /'
fi
if [ -f "$PROJECT_DIR/LICENSE" ] && grep -Fq "MIT License" "$PROJECT_DIR/LICENSE" 2>/dev/null; then
    record PASS "OSS license: MIT LICENSE present"
else
    record FAIL "OSS license: MIT LICENSE present"
fi
grep -Fq "Licensed under the MIT License" "$PROJECT_DIR/README.md" 2>/dev/null && record PASS "README: MIT license declared" || record FAIL "README: MIT license declared"
INTERNAL_REF_PATTERN='products/[A-Za-z0-9._/-]*[A-Z][A-Z0-9_]*_ROOT|gitlab[.]local|cp[0-9]{3}[.]|172[.]10[.]'
INTERNAL_REF_HITS=$(git -C "$PROJECT_DIR" grep -n -i -E "$INTERNAL_REF_PATTERN" -- ':!.devcontainer/verify-template.sh' 2>/dev/null || true)
if [ -z "$INTERNAL_REF_HITS" ]; then
    record PASS "OSS hygiene: tracked files contain no internal topology refs"
else
    record FAIL "OSS hygiene: tracked files contain internal topology refs"
    printf '%s\n' "$INTERNAL_REF_HITS" | sed 's/^/      internal-ref: /'
fi

# --- PHASE 2a: Karpathy alignment ---
echo ""
echo "=== Phase 2a: Karpathy Alignment ==="
grep -q "behavioral-core" "$PROJECT_DIR/CLAUDE.md" 2>/dev/null && record PASS "CLAUDE.md -> behavioral-core import" || record FAIL "CLAUDE.md -> behavioral-core import"
grep -q "behavioral-core" "$PROJECT_DIR/AGENTS.md" 2>/dev/null && record PASS "AGENTS.md -> behavioral-core import" || record FAIL "AGENTS.md -> behavioral-core import"
[ -f "$PROJECT_DIR/.claude/rules/behavioral-core.md" ] && record PASS ".claude/rules/behavioral-core.md exists" || record FAIL ".claude/rules/behavioral-core.md"
[ -f "$PROJECT_DIR/.agents/rules/behavioral-core.md" ] && record PASS ".agents/rules/behavioral-core.md (mirror) exists" || record FAIL ".agents/rules/behavioral-core.md (mirror)"
KARPATHY_GLOBAL_FIXTURE=$(mktemp -d)
mkdir -p "$KARPATHY_GLOBAL_FIXTURE/.claude/rules" "$KARPATHY_GLOBAL_FIXTURE/.claude/skills/karpathy-guidelines" "$KARPATHY_GLOBAL_FIXTURE/products"
cp "$PROJECT_DIR/.claude/rules/behavioral-core.md" "$KARPATHY_GLOBAL_FIXTURE/.claude/rules/behavioral-core.md"
cp "$PROJECT_DIR/.claude/skills/karpathy-guidelines/SKILL.md" "$KARPATHY_GLOBAL_FIXTURE/.claude/skills/karpathy-guidelines/SKILL.md"
if bash "$PROJECT_DIR/scripts/meta/karpathy-consistency-check.sh" "$KARPATHY_GLOBAL_FIXTURE" >/dev/null 2>&1; then
    record FAIL "karpathy checker: GLOBAL default count fails closed"
else
    record PASS "karpathy checker: GLOBAL default count fails closed"
fi
if EXPECTED_KARPATHY_COUNT=1 bash "$PROJECT_DIR/scripts/meta/karpathy-consistency-check.sh" "$KARPATHY_GLOBAL_FIXTURE" >/dev/null 2>&1; then
    record PASS "karpathy checker: explicit GLOBAL count override"
else
    record FAIL "karpathy checker: explicit GLOBAL count override"
fi
rm -r "$KARPATHY_GLOBAL_FIXTURE"

# --- PHASE 2b: Hooks syntax ---
echo ""
echo "=== Phase 2b: Hook Syntax (Claude side) ==="
claude_hooks=$(ls "$PROJECT_DIR"/.claude/hooks/*.sh 2>/dev/null | wc -l)
[ "$claude_hooks" -eq 4 ] && record PASS "Claude hooks: $claude_hooks/4 (session-start, pre-commit-gate, pre-push-gate, refinement-gate)" || record FAIL "Claude hooks: $claude_hooks (expected 4)"
for f in "$PROJECT_DIR"/.claude/hooks/*.sh; do
    [ -f "$f" ] || continue
    bash -n "$f" 2>/dev/null && record PASS "$(basename $f)" || record FAIL "$(basename $f)"
done

# --- PHASE 2c: Agents ---
echo ""
echo "=== Phase 2c: Agents ==="
count=0
total=0
agent_schema_ok=0
for f in "$PROJECT_DIR"/.claude/agents/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [ "$name" = "_schema.md" ] && continue
    [[ "$name" == _* ]] && continue
    total=$((total+1))
    head -1 "$f" 2>/dev/null | grep -q "^---" && count=$((count+1)) || record FAIL "frontmatter: $name"
    schema_ok=1
    header=$(frontmatter_header "$f")
    flat_frontmatter_valid "$f" "name description tools model maxTurns color" || schema_ok=0
    declared_name=$(printf '%s\n' "$header" | sed -n 's/^name:[[:space:]]*//p')
    [ "$declared_name" = "${name%.md}" ] || schema_ok=0
    [ "$schema_ok" -eq 1 ] && agent_schema_ok=$((agent_schema_ok+1)) || record FAIL "agent schema: $name"
done
[ "$total" -eq 2 ] && record PASS "Agent count: $total (evaluator, wip-manager)" || record FAIL "Agent count: $total (expected 2)"
record PASS "Agent frontmatter ($count/$total)"
[ "$agent_schema_ok" -eq "$total" ] && record PASS "Agent schema ($agent_schema_ok/$total)" || record FAIL "Agent schema ($agent_schema_ok/$total)"

# --- PHASE 2d: Skills (4 + karpathy-guidelines reference) ---
echo ""
echo "=== Phase 2d: Skills ==="
skills=$(ls "$PROJECT_DIR"/.claude/skills/*/SKILL.md 2>/dev/null | wc -l)
[ "$skills" -eq 4 ] && record PASS "Skills: $skills/4 (refine, status, verify, karpathy-guidelines)" || record FAIL "Skills: $skills (expected 4)"
skill_schema_ok=0
for f in "$PROJECT_DIR"/.claude/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    header=$(frontmatter_header "$f")
    skill_name=$(basename "$(dirname "$f")")
    if [ "$skill_name" = "karpathy-guidelines" ]; then
        keys="name description license"
    elif [ "$skill_name" = "status" ]; then
        keys="name description user-invocable allowed-tools"
    else
        keys="name description argument-hint user-invocable allowed-tools"
    fi
    schema_ok=1
    flat_frontmatter_valid "$f" "$keys" || schema_ok=0
    declared_name=$(printf '%s\n' "$header" | sed -n 's/^name:[[:space:]]*//p')
    [ "$declared_name" = "$skill_name" ] || schema_ok=0
    [ "$schema_ok" -eq 1 ] && skill_schema_ok=$((skill_schema_ok+1)) || record FAIL "skill schema: $(basename "$(dirname "$f")")"
done
[ "$skill_schema_ok" -eq "$skills" ] && record PASS "Skill schema ($skill_schema_ok/$skills)" || record FAIL "Skill schema ($skill_schema_ok/$skills)"

# --- PHASE 2e: Rules (6 portable) ---
echo ""
echo "=== Phase 2e: Rules ==="
EXPECTED_RULES="audit-discipline behavioral-core commit-discipline destructive-ops-discipline anchor-discipline devcontainer-patterns"
missing=""
for r in $EXPECTED_RULES; do
    [ -f "$PROJECT_DIR/.claude/rules/$r.md" ] || missing="$missing $r"
done
if [ -z "$missing" ]; then
    record PASS "Rules: all 6 portable rules present ($EXPECTED_RULES)"
else
    record FAIL "Rules: missing$missing"
fi
rules_total=$(ls "$PROJECT_DIR"/.claude/rules/*.md 2>/dev/null | wc -l)
[ "$rules_total" -eq 6 ] && record PASS "Rules count: $rules_total/6" || record FAIL "Rules count: $rules_total (expected 6)"

for r in $EXPECTED_RULES; do
    grep -Fq "@.claude/rules/$r.md" "$PROJECT_DIR/CLAUDE.md" 2>/dev/null || missing="$missing CLAUDE:$r"
    grep -Fq ".agents/rules/$r.md" "$PROJECT_DIR/AGENTS.md" 2>/dev/null || missing="$missing AGENTS:$r"
    cmp -s "$PROJECT_DIR/.claude/rules/$r.md" "$PROJECT_DIR/.agents/rules/$r.md" || missing="$missing MIRROR:$r"
done
[ -z "$missing" ] && record PASS "Rules: imported, loaded, and mirrored by name" || record FAIL "Rules parity:$missing"

# --- PHASE 2f: Codex hooks (4) ---
echo ""
echo "=== Phase 2f: Codex Hooks ==="
codex_hook_count=$(ls "$PROJECT_DIR"/.codex/hooks/*.sh 2>/dev/null | wc -l)
[ "$codex_hook_count" -eq 4 ] && record PASS "Codex hooks: $codex_hook_count/4 (session-start, pre-commit-gate, pre-push-gate, refinement-gate)" || record FAIL "Codex hooks: $codex_hook_count (expected 4)"
for f in "$PROJECT_DIR"/.codex/hooks/*.sh; do
    [ -f "$f" ] || continue
    bash -n "$f" 2>/dev/null && record PASS "$(basename $f)" || record FAIL "$(basename $f)"
done
CODEX_SESSION_OUTPUT=$(cd "$PROJECT_DIR/.codex" && printf '{"source":"startup"}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/session-start.sh")
if printf '%s' "$CODEX_SESSION_OUTPUT" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | contains("Git branch:"))' >/dev/null 2>&1; then
    record PASS "Codex SessionStart: emits project context from subdirectory"
else
    record FAIL "Codex SessionStart: runtime context output"
fi
if printf '{"tool_input":{"command":"git commit --no-verify -m probe"}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex PreToolUse: --no-verify bypass accepted"
else
    record PASS "Codex PreToolUse: --no-verify bypass blocked"
fi
HOOK_FIXTURE=$(mktemp -d)
git -C "$HOOK_FIXTURE" init -q
git -C "$HOOK_FIXTURE" -c user.name=verify -c user.email=verify@example.invalid commit -q --allow-empty -m init
HOOK_BRANCH=$(git -C "$HOOK_FIXTURE" rev-parse --abbrev-ref HEAD)
mkdir -p "$HOOK_FIXTURE/.codex/state" "$HOOK_FIXTURE/.claude"
touch "$HOOK_FIXTURE/.codex/state/last-verification.$HOOK_BRANCH" "$HOOK_FIXTURE/.claude/.last-verification.$HOOK_BRANCH"
if printf '{"tool_input":{"command":"git -C %s commit -n -m probe"}}' "$HOOK_FIXTURE" | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex PreToolUse: git -C commit -n bypass accepted"
else
    record PASS "Codex PreToolUse: git -C commit -n bypass blocked"
fi
for wrapper in "timeout 60" "nice -n 10" "nohup" "setsid -w" "stdbuf -oL" "ionice -c 2 -n 7" "chrt -i 0" "xargs" "flock $HOOK_FIXTURE/hook.lock"; do
    if jq -n --arg c "$wrapper git -C $HOOK_FIXTURE commit -n -m probe" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
        record FAIL "Codex PreToolUse: $wrapper git commit wrapper bypass accepted"
    else
        record PASS "Codex PreToolUse: $wrapper git commit wrapper bypass blocked"
    fi
done
for wrapper in "xargs echo" "flock $HOOK_FIXTURE/hook.lock echo"; do
    if jq -n --arg c "$wrapper hook-regression" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
        record PASS "Codex PreToolUse: $wrapper non-git command allowed"
    else
        record FAIL "Codex PreToolUse: $wrapper non-git command blocked"
    fi
done
if jq -n --arg c "flock -c 'git -C $HOOK_FIXTURE commit -n -m probe' $HOOK_FIXTURE/hook.lock" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex PreToolUse: flock -c git commit wrapper bypass accepted"
else
    record PASS "Codex PreToolUse: flock -c git commit wrapper bypass blocked"
fi
if jq -n --arg c "flock -c 'echo hook-regression' $HOOK_FIXTURE/hook.lock" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex PreToolUse: flock -c non-git command allowed"
else
    record FAIL "Codex PreToolUse: flock -c non-git command blocked"
fi
if jq -n --arg c "timeout 60 echo hook-regression" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex PreToolUse: timeout non-git command allowed"
else
    record FAIL "Codex PreToolUse: timeout non-git command blocked"
fi
if printf '{"tool_input":{"command":"NV=--no-verify; git commit $NV -m probe"}}' | CODEX_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex PreToolUse: variable-expanded commit flag accepted"
else
    record PASS "Codex PreToolUse: variable-expanded commit flag blocked"
fi
if printf '{"tool_input":{"command":"g\\"i\\"t commit --no-verify -m probe"}}' | CODEX_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex PreToolUse: quoted git commit bypass accepted"
else
    record PASS "Codex PreToolUse: quoted git commit bypass blocked"
fi
HOOK_FIXTURE_2=$(mktemp -d)
git -C "$HOOK_FIXTURE_2" init -q
git -C "$HOOK_FIXTURE_2" -c user.name=verify -c user.email=verify@example.invalid commit -q --allow-empty -m init
if printf '{"tool_input":{"command":"git -C %s commit -m ok && git -C %s commit -m bypass"}}' "$HOOK_FIXTURE" "$HOOK_FIXTURE_2" | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex PreToolUse: compound git commit accepted"
else
    record PASS "Codex PreToolUse: compound git commit blocked"
fi
CHECKER_FIXTURE=$(mktemp -d)
git -C "$CHECKER_FIXTURE" init -q
git -C "$CHECKER_FIXTURE" -c user.name=verify -c user.email=verify@example.invalid commit -q --allow-empty -m init
CHECKER_BRANCH=$(git -C "$CHECKER_FIXTURE" rev-parse --abbrev-ref HEAD)
mkdir -p "$CHECKER_FIXTURE/scripts/meta"
cat > "$CHECKER_FIXTURE/scripts/meta/completion-checker.sh" <<EOF
#!/bin/bash
printf '%s\n' "\${CLAUDE_PROJECT_DIR:-\${CODEX_PROJECT_DIR:-}}" > "$CHECKER_FIXTURE/seen-root"
exit 0
EOF
# Fail-closed contract: stale marker in the target root must block within the
# PreToolUse timeout budget (timeout 5 mirrors settings.json/hooks.json), print
# guidance naming the TARGET root's checker (not the session root's), and must
# NOT execute the checker in-hook (fixture checker records seen-root if run).
CODEX_STALE_ERR=$(jq -n --arg c "git -C $CHECKER_FIXTURE commit -m probe" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$HOOK_FIXTURE" timeout 5 bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" 2>&1 >/dev/null)
CODEX_STALE_RC=$?
if [ "$CODEX_STALE_RC" -eq 2 ] &&
   printf '%s' "$CODEX_STALE_ERR" | grep -Fq "$CHECKER_FIXTURE/scripts/meta/completion-checker.sh" &&
   [ ! -f "$CHECKER_FIXTURE/seen-root" ]; then
    record PASS "Codex PreToolUse: stale marker fails closed with target-root guidance"
else
    record FAIL "Codex PreToolUse: stale marker fail-closed contract"
fi
CLAUDE_STALE_ERR=$(jq -n --arg c "git -C $CHECKER_FIXTURE commit -m probe" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$HOOK_FIXTURE" timeout 5 bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" 2>&1 >/dev/null)
CLAUDE_STALE_RC=$?
if [ "$CLAUDE_STALE_RC" -eq 2 ] &&
   printf '%s' "$CLAUDE_STALE_ERR" | grep -Fq "$CHECKER_FIXTURE/scripts/meta/completion-checker.sh" &&
   [ ! -f "$CHECKER_FIXTURE/seen-root" ] &&
   [ ! -f "$CHECKER_FIXTURE/.claude/.last-verification.$CHECKER_BRANCH" ]; then
    record PASS "Claude PreToolUse: stale marker fails closed with target-root guidance"
else
    record FAIL "Claude PreToolUse: stale marker fail-closed contract"
fi
# Static tripwire: reintroducing in-hook checker execution reverts the gate to
# a run that cannot finish inside the hook timeout budget.
if grep -Fq 'bash "$CHECKER"' "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" || grep -Fq 'bash "$CHECKER"' "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh"; then
    record FAIL "pre-commit gates: in-hook checker execution present (exceeds hook timeout budget)"
else
    record PASS "pre-commit gates: no in-hook checker execution"
fi
if printf '{"tool_input":{"command":"if true; then git commit -n -m bypass; fi"}}' | CODEX_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex PreToolUse: control-structure git commit accepted"
else
    record PASS "Codex PreToolUse: control-structure git commit blocked"
fi
if printf '{"tool_input":{"command":"git -C %s commit -m probe"}}' "$HOOK_FIXTURE" | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex PreToolUse: git -C commit allowed after fresh verification"
else
    record FAIL "Codex PreToolUse: git -C commit false positive after fresh verification"
fi
if jq -n --arg c "git -C $HOOK_FIXTURE commit -m \"fix: handle {id}\"" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex PreToolUse: brace literal in commit message allowed"
else
    record FAIL "Codex PreToolUse: brace literal in commit message false positive"
fi
if jq -n --arg c "git -C $HOOK_FIXTURE commit -m \"handle empty {} object\"" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex PreToolUse: empty-brace literal in commit message allowed"
else
    record FAIL "Codex PreToolUse: empty-brace literal in commit message false positive"
fi
if jq -n --arg c "git -C $HOOK_FIXTURE commit -m wip -- file-{a,b}.txt" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex PreToolUse: brace pathspec allowed"
else
    record FAIL "Codex PreToolUse: brace pathspec false positive"
fi
if jq -n --arg c "{ git -C $HOOK_FIXTURE commit -n -m bypass; }" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex PreToolUse: brace-group commit bypass accepted"
else
    record PASS "Codex PreToolUse: brace-group commit bypass blocked"
fi
if printf '{"tool_input":{"command":"git -C %s push https://oauth2:TOK@example.invalid/x.git main"}}' "$HOOK_FIXTURE" | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex pre-push: inline credential URL accepted"
else
    record PASS "Codex pre-push: inline credential URL blocked"
fi
for wrapper in "timeout 60" "nice -n 10" "nohup" "setsid -w" "stdbuf -oL" "ionice -c 2 -n 7" "chrt -i 0" "xargs" "flock $HOOK_FIXTURE/hook.lock"; do
    if jq -n --arg c "$wrapper git -C $HOOK_FIXTURE push https://oauth2:TOK@example.invalid/x.git main" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
        record FAIL "Codex pre-push: $wrapper git push wrapper credential accepted"
    else
        record PASS "Codex pre-push: $wrapper git push wrapper credential blocked"
    fi
done
for wrapper in "xargs echo" "flock $HOOK_FIXTURE/hook.lock echo"; do
    if jq -n --arg c "$wrapper hook-regression" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
        record PASS "Codex pre-push: $wrapper non-git command allowed"
    else
        record FAIL "Codex pre-push: $wrapper non-git command blocked"
    fi
done
if jq -n --arg c "flock -c 'git -C $HOOK_FIXTURE push https://oauth2:TOK@example.invalid/x.git main' $HOOK_FIXTURE/hook.lock" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex pre-push: flock -c git push wrapper credential accepted"
else
    record PASS "Codex pre-push: flock -c git push wrapper credential blocked"
fi
if jq -n --arg c "flock -c 'echo hook-regression' $HOOK_FIXTURE/hook.lock" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex pre-push: flock -c non-git command allowed"
else
    record FAIL "Codex pre-push: flock -c non-git command blocked"
fi
if jq -n --arg c "timeout 60 echo hook-regression" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex pre-push: timeout non-git command allowed"
else
    record FAIL "Codex pre-push: timeout non-git command blocked"
fi
if printf '{"tool_input":{"command":"R=https://oauth2:TOK@example.invalid/x.git; git push $R main"}}' | CODEX_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex pre-push: variable-expanded credential URL accepted"
else
    record PASS "Codex pre-push: variable-expanded credential URL blocked"
fi
if printf '{"tool_input":{"command":"if true; then git push https://example.invalid/x.git main; fi"}}' | CODEX_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex pre-push: control-structure git push accepted"
else
    record PASS "Codex pre-push: control-structure git push blocked"
fi
if jq -n --arg c "for r in a b; do echo x; done; git -C $HOOK_FIXTURE push https://example.invalid/x.git main" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex pre-push: preceding shell loop does not false-positive"
else
    record FAIL "Codex pre-push: preceding shell loop false positive"
fi
if jq -n --arg c "{ git -C $HOOK_FIXTURE push https://example.invalid/x.git main; }" '{tool_input:{command:$c}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex pre-push: brace-group push accepted"
else
    record PASS "Codex pre-push: brace-group push blocked"
fi
if printf '{"tool_input":{"command":"git -c include.path=/tmp/evil.gitconfig push origin main"}}' | CODEX_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex pre-push: transient include.path accepted"
else
    record PASS "Codex pre-push: transient include.path blocked"
fi
if printf '{"tool_input":{"command":"git -C %s commit -n -m probe"}}' "$HOOK_FIXTURE" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude PreToolUse: git -C commit -n bypass accepted"
else
    record PASS "Claude PreToolUse: git -C commit -n bypass blocked"
fi
for wrapper in "timeout 60" "nice -n 10" "nohup" "setsid -w" "stdbuf -oL" "ionice -c 2 -n 7" "chrt -i 0" "xargs" "flock $HOOK_FIXTURE/hook.lock"; do
    if jq -n --arg c "$wrapper git -C $HOOK_FIXTURE commit -n -m probe" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
        record FAIL "Claude PreToolUse: $wrapper git commit wrapper bypass accepted"
    else
        record PASS "Claude PreToolUse: $wrapper git commit wrapper bypass blocked"
    fi
done
for wrapper in "xargs echo" "flock $HOOK_FIXTURE/hook.lock echo"; do
    if jq -n --arg c "$wrapper hook-regression" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
        record PASS "Claude PreToolUse: $wrapper non-git command allowed"
    else
        record FAIL "Claude PreToolUse: $wrapper non-git command blocked"
    fi
done
if jq -n --arg c "flock -c 'git -C $HOOK_FIXTURE commit -n -m probe' $HOOK_FIXTURE/hook.lock" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude PreToolUse: flock -c git commit wrapper bypass accepted"
else
    record PASS "Claude PreToolUse: flock -c git commit wrapper bypass blocked"
fi
if jq -n --arg c "flock -c 'echo hook-regression' $HOOK_FIXTURE/hook.lock" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Claude PreToolUse: flock -c non-git command allowed"
else
    record FAIL "Claude PreToolUse: flock -c non-git command blocked"
fi
if jq -n --arg c "timeout 60 echo hook-regression" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Claude PreToolUse: timeout non-git command allowed"
else
    record FAIL "Claude PreToolUse: timeout non-git command blocked"
fi
if printf '{"tool_input":{"command":"NV=--no-verify; git commit $NV -m probe"}}' | CLAUDE_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude PreToolUse: variable-expanded commit flag accepted"
else
    record PASS "Claude PreToolUse: variable-expanded commit flag blocked"
fi
if printf '{"tool_input":{"command":"git -C %s commit -m ok && git -C %s commit -m bypass"}}' "$HOOK_FIXTURE" "$HOOK_FIXTURE_2" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude PreToolUse: compound git commit accepted"
else
    record PASS "Claude PreToolUse: compound git commit blocked"
fi
if printf '{"tool_input":{"command":"if true; then git commit -n -m bypass; fi"}}' | CLAUDE_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude PreToolUse: control-structure git commit accepted"
else
    record PASS "Claude PreToolUse: control-structure git commit blocked"
fi
if printf '{"tool_input":{"command":"git -C %s commit -m probe"}}' "$HOOK_FIXTURE" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Claude PreToolUse: git -C commit allowed after fresh verification"
else
    record FAIL "Claude PreToolUse: git -C commit false positive after fresh verification"
fi
if jq -n --arg c "git -C $HOOK_FIXTURE commit -m \"fix: handle {id}\"" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Claude PreToolUse: brace literal in commit message allowed"
else
    record FAIL "Claude PreToolUse: brace literal in commit message false positive"
fi
if jq -n --arg c "git -C $HOOK_FIXTURE commit -m \"handle empty {} object\"" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Claude PreToolUse: empty-brace literal in commit message allowed"
else
    record FAIL "Claude PreToolUse: empty-brace literal in commit message false positive"
fi
if jq -n --arg c "git -C $HOOK_FIXTURE commit -m wip -- file-{a,b}.txt" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Claude PreToolUse: brace pathspec allowed"
else
    record FAIL "Claude PreToolUse: brace pathspec false positive"
fi
if jq -n --arg c "{ git -C $HOOK_FIXTURE commit -n -m bypass; }" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude PreToolUse: brace-group commit bypass accepted"
else
    record PASS "Claude PreToolUse: brace-group commit bypass blocked"
fi
if printf '{"tool_input":{"command":"git -C %s push https://oauth2:TOK@example.invalid/x.git main"}}' "$HOOK_FIXTURE" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude pre-push: inline credential URL accepted"
else
    record PASS "Claude pre-push: inline credential URL blocked"
fi
for wrapper in "timeout 60" "nice -n 10" "nohup" "setsid -w" "stdbuf -oL" "ionice -c 2 -n 7" "chrt -i 0" "xargs" "flock $HOOK_FIXTURE/hook.lock"; do
    if jq -n --arg c "$wrapper git -C $HOOK_FIXTURE push https://oauth2:TOK@example.invalid/x.git main" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
        record FAIL "Claude pre-push: $wrapper git push wrapper credential accepted"
    else
        record PASS "Claude pre-push: $wrapper git push wrapper credential blocked"
    fi
done
for wrapper in "xargs echo" "flock $HOOK_FIXTURE/hook.lock echo"; do
    if jq -n --arg c "$wrapper hook-regression" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
        record PASS "Claude pre-push: $wrapper non-git command allowed"
    else
        record FAIL "Claude pre-push: $wrapper non-git command blocked"
    fi
done
if jq -n --arg c "flock -c 'git -C $HOOK_FIXTURE push https://oauth2:TOK@example.invalid/x.git main' $HOOK_FIXTURE/hook.lock" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude pre-push: flock -c git push wrapper credential accepted"
else
    record PASS "Claude pre-push: flock -c git push wrapper credential blocked"
fi
if jq -n --arg c "flock -c 'echo hook-regression' $HOOK_FIXTURE/hook.lock" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record PASS "Claude pre-push: flock -c non-git command allowed"
else
    record FAIL "Claude pre-push: flock -c non-git command blocked"
fi
if jq -n --arg c "timeout 60 echo hook-regression" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record PASS "Claude pre-push: timeout non-git command allowed"
else
    record FAIL "Claude pre-push: timeout non-git command blocked"
fi
if printf '{"tool_input":{"command":"R=https://oauth2:TOK@example.invalid/x.git; git push $R main"}}' | CLAUDE_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude pre-push: variable-expanded credential URL accepted"
else
    record PASS "Claude pre-push: variable-expanded credential URL blocked"
fi
if printf '{"tool_input":{"command":"if true; then git push https://example.invalid/x.git main; fi"}}' | CLAUDE_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude pre-push: control-structure git push accepted"
else
    record PASS "Claude pre-push: control-structure git push blocked"
fi
if jq -n --arg c "for r in a b; do echo x; done; git -C $HOOK_FIXTURE push https://example.invalid/x.git main" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record PASS "Claude pre-push: preceding shell loop does not false-positive"
else
    record FAIL "Claude pre-push: preceding shell loop false positive"
fi
if jq -n --arg c "{ git -C $HOOK_FIXTURE push https://example.invalid/x.git main; }" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude pre-push: brace-group push accepted"
else
    record PASS "Claude pre-push: brace-group push blocked"
fi
if printf '{"tool_input":{"command":"git -c include.path=/tmp/evil.gitconfig push origin main"}}' | CLAUDE_PROJECT_DIR="$HOOK_FIXTURE" bash "$PROJECT_DIR/.claude/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record FAIL "Claude pre-push: transient include.path accepted"
else
    record PASS "Claude pre-push: transient include.path blocked"
fi
NO_JQ_PATH=$(mktemp -d)
if printf '{"tool_input":{"command":"git commit -m probe"}}' | PATH="$NO_JQ_PATH" CODEX_PROJECT_DIR="$HOOK_FIXTURE" /bin/bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record FAIL "Codex PreToolUse: missing jq accepted"
else
    record PASS "Codex PreToolUse: missing jq fails closed"
fi
rm -r "$NO_JQ_PATH" "$HOOK_FIXTURE" "$HOOK_FIXTURE_2" "$CHECKER_FIXTURE"
if printf '{"tool_input":{"command":"echo hook-regression"}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-commit-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex PreToolUse: unrelated Bash command allowed"
else
    record FAIL "Codex PreToolUse: unrelated Bash command blocked"
fi
if printf '{"tool_input":{"command":"echo hook-regression"}}' | CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/pre-push-gate.sh" >/dev/null 2>&1; then
    record PASS "Codex pre-push: unrelated Bash command allowed"
else
    record FAIL "Codex pre-push: unrelated Bash command blocked"
fi
if CODEX_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/.codex/hooks/refinement-gate.sh" </dev/null >/dev/null 2>&1; then
    record PASS "Codex Stop: no active refinement exits cleanly"
else
    record FAIL "Codex Stop: no-marker regression"
fi
REFINE_FIXTURE=$(mktemp -d)
git -C "$REFINE_FIXTURE" init -q
mkdir -p "$REFINE_FIXTURE/.codex/state/refinement/attempts" "$REFINE_FIXTURE/.claude/agent-memory/refinement/attempts"
printf '{"task_id":"strict","threshold":"1.2.3","max_iterations":"bad"}\n' > "$REFINE_FIXTURE/.codex/state/refinement-active"
printf '{"score":0.9}\n' > "$REFINE_FIXTURE/.codex/state/refinement/attempts/strict.jsonl"
CODEX_REFINE_OUTPUT=$(CODEX_PROJECT_DIR="$REFINE_FIXTURE" bash "$PROJECT_DIR/.codex/hooks/refinement-gate.sh" </dev/null 2>&1 || true)
if [ -z "$CODEX_REFINE_OUTPUT" ]; then
    record PASS "Codex Stop: invalid numeric fields reset safely"
else
    record FAIL "Codex Stop: invalid numeric fields caused block output"
fi
printf '{"task_id":"strict","threshold":"1.2.3","max_iterations":"bad"}\n' > "$REFINE_FIXTURE/.claude/.refinement-active"
printf '{"score":0.9}\n' > "$REFINE_FIXTURE/.claude/agent-memory/refinement/attempts/strict.jsonl"
CLAUDE_REFINE_OUTPUT=$(CLAUDE_PROJECT_DIR="$REFINE_FIXTURE" bash "$PROJECT_DIR/.claude/hooks/refinement-gate.sh" </dev/null 2>&1 || true)
if [ -z "$CLAUDE_REFINE_OUTPUT" ]; then
    record PASS "Claude Stop: invalid numeric fields reset safely"
else
    record FAIL "Claude Stop: invalid numeric fields caused block output"
fi
rm -r "$REFINE_FIXTURE"

# --- PHASE 2g: Mirror integrity ---
echo ""
echo "=== Phase 2g: Mirror Integrity ==="
[ -d "$PROJECT_DIR/.agents/skills/evaluator" ] && record PASS ".agents/skills/evaluator (agent->skill mirror)" || record FAIL ".agents/skills/evaluator missing"
[ -d "$PROJECT_DIR/.agents/skills/wip-manager" ] && record PASS ".agents/skills/wip-manager (agent->skill mirror)" || record FAIL ".agents/skills/wip-manager missing"
[ -x "$PROJECT_DIR/scripts/sync-agents-mirror.sh" ] && record PASS "sync-agents-mirror.sh executable" || record FAIL "sync-agents-mirror.sh"
[ -x "$PROJECT_DIR/scripts/meta/run-isolated-role.sh" ] && record PASS "run-isolated-role.sh executable" || record FAIL "run-isolated-role.sh"
if SYNC_REAL_DRY=$(bash "$PROJECT_DIR/scripts/sync-agents-mirror.sh" --dry 2>&1) && printf '%s' "$SYNC_REAL_DRY" | grep -Fq '0 change(s) detected.'; then
    record PASS "sync dry-run: actual .agents mirror has no drift"
else
    record FAIL "sync dry-run: actual .agents mirror drift detected"
fi

SYNC_FIXTURE=$(mktemp -d)
mkdir -p "$SYNC_FIXTURE/scripts"
cp -R "$PROJECT_DIR/.claude" "$PROJECT_DIR/.agents" "$SYNC_FIXTURE/"
cp "$PROJECT_DIR/scripts/sync-agents-mirror.sh" "$SYNC_FIXTURE/scripts/"
touch "$SYNC_FIXTURE/.agents/skills/refine/nested-orphan.txt"
mkdir -p "$SYNC_FIXTURE/.agents/unexpected"
touch "$SYNC_FIXTURE/.agents/unexpected/top-level-orphan.txt"
SYNC_DRY=$(bash "$SYNC_FIXTURE/scripts/sync-agents-mirror.sh" --dry 2>&1 || true)
if printf '%s' "$SYNC_DRY" | grep -Fq 'nested-orphan.txt' && printf '%s' "$SYNC_DRY" | grep -Fq 'unexpected'; then
    record PASS "sync dry-run: nested and top-level orphans detected"
else
    record FAIL "sync dry-run: orphan coverage incomplete"
fi
if bash "$SYNC_FIXTURE/scripts/sync-agents-mirror.sh" --check >/dev/null 2>&1; then
    record FAIL "sync: unknown argument rejected"
else
    record PASS "sync: unknown argument rejected"
fi
if bash "$SYNC_FIXTURE/scripts/sync-agents-mirror.sh" --dry --check >/dev/null 2>&1; then
    record FAIL "sync: trailing argument rejected"
else
    record PASS "sync: trailing argument rejected"
fi
ln -s /tmp "$SYNC_FIXTURE/.agents/unsafe-link"
if bash "$SYNC_FIXTURE/scripts/sync-agents-mirror.sh" --dry >/dev/null 2>&1; then
    record FAIL "sync: destination symlink accepted"
else
    record PASS "sync: destination symlink rejected"
fi
rm -r "$SYNC_FIXTURE"

PREMUT_FIXTURE=$(mktemp -d)
mkdir -p "$PREMUT_FIXTURE/scripts"
cp -R "$PROJECT_DIR/.claude" "$PREMUT_FIXTURE/"
cp "$PROJECT_DIR/scripts/sync-agents-mirror.sh" "$PREMUT_FIXTURE/scripts/"
ln -s /tmp "$PREMUT_FIXTURE/.claude/skills/unsafe-link"
if bash "$PREMUT_FIXTURE/scripts/sync-agents-mirror.sh" >/dev/null 2>&1 || [ -e "$PREMUT_FIXTURE/.agents" ]; then
    record FAIL "sync: source symlink mutated destination"
else
    record PASS "sync: source symlink rejected pre-mutation"
fi
rm -r "$PREMUT_FIXTURE"

TYPE_FIXTURE=$(mktemp -d)
mkdir -p "$TYPE_FIXTURE/scripts"
cp -R "$PROJECT_DIR/.claude" "$PROJECT_DIR/.agents" "$TYPE_FIXTURE/"
cp "$PROJECT_DIR/scripts/sync-agents-mirror.sh" "$TYPE_FIXTURE/scripts/"
rm -r "$TYPE_FIXTURE/.agents/skills/refine"
printf 'conflict\n' > "$TYPE_FIXTURE/.agents/skills/refine"
if bash "$TYPE_FIXTURE/scripts/sync-agents-mirror.sh" >/dev/null 2>&1 && [ -d "$TYPE_FIXTURE/.agents/skills/refine" ] && bash "$TYPE_FIXTURE/scripts/sync-agents-mirror.sh" --dry 2>&1 | grep -Fq '0 change(s)'; then
    record PASS "sync: file/directory conflict reconciled"
else
    record FAIL "sync: file/directory conflict"
fi
rm -r "$TYPE_FIXTURE"

ROOT_TYPE_FIXTURE=$(mktemp -d)
mkdir -p "$ROOT_TYPE_FIXTURE/scripts"
cp -R "$PROJECT_DIR/.claude" "$ROOT_TYPE_FIXTURE/"
cp "$PROJECT_DIR/scripts/sync-agents-mirror.sh" "$ROOT_TYPE_FIXTURE/scripts/"
printf 'conflict\n' > "$ROOT_TYPE_FIXTURE/.agents"
if bash "$ROOT_TYPE_FIXTURE/scripts/sync-agents-mirror.sh" >/dev/null 2>&1 && [ -d "$ROOT_TYPE_FIXTURE/.agents/skills" ] && bash "$ROOT_TYPE_FIXTURE/scripts/sync-agents-mirror.sh" --dry 2>&1 | grep -Fq '0 change(s)'; then
    record PASS "sync: root file/directory conflict reconciled"
else
    record FAIL "sync: root file/directory conflict"
fi
rm -r "$ROOT_TYPE_FIXTURE"

MODE_FIXTURE=$(mktemp -d)
mkdir -p "$MODE_FIXTURE/scripts"
cp -R "$PROJECT_DIR/.claude" "$PROJECT_DIR/.agents" "$MODE_FIXTURE/"
cp "$PROJECT_DIR/scripts/sync-agents-mirror.sh" "$MODE_FIXTURE/scripts/"
chmod 755 "$MODE_FIXTURE/.claude/skills/refine/SKILL.md"
chmod 644 "$MODE_FIXTURE/.agents/skills/refine/SKILL.md"
MODE_DRY=$(bash "$MODE_FIXTURE/scripts/sync-agents-mirror.sh" --dry 2>&1 || true)
if printf '%s' "$MODE_DRY" | grep -Fq 'Mode differs:'; then
    record PASS "sync dry-run: file-mode drift detected"
else
    record FAIL "sync dry-run: file-mode drift missed"
fi
if bash "$MODE_FIXTURE/scripts/sync-agents-mirror.sh" >/dev/null 2>&1 &&
    [ "$(stat -c '%a' "$MODE_FIXTURE/.agents/skills/refine/SKILL.md")" = "755" ] &&
    bash "$MODE_FIXTURE/scripts/sync-agents-mirror.sh" --dry 2>&1 | grep -Fq '0 change(s)'; then
    record PASS "sync: file-mode parity restored"
else
    record FAIL "sync: file-mode parity not restored"
fi
rm -r "$MODE_FIXTURE"

ROLE_FIXTURE=$(mktemp -d)
ROLE_BIN_DIR=$(mktemp -d)
ROLE_LOG_FILE=$(mktemp)
mkdir -p "$ROLE_FIXTURE/.codex/state" "$ROLE_FIXTURE/products/app" "$ROLE_FIXTURE/scripts/meta"
cp "$PROJECT_DIR/scripts/meta/run-isolated-role.sh" "$ROLE_FIXTURE/scripts/meta/"
cat > "$ROLE_FIXTURE/fake-codex" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$ROLE_LOG"
FINAL_OUTPUT=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
        shift
        FINAL_OUTPUT=$1
    fi
    shift
done
[ -z "${ROLE_REPORT:-}" ] || printf '{"contract_score":1,"findings":["full report survives"]}\n' > "$ROLE_REPORT"
[ -z "$FINAL_OUTPUT" ] || printf '{"score":1,"suggestion":"ok"}\n' > "$FINAL_OUTPUT"
cat >/dev/null
EOF
chmod +x "$ROLE_FIXTURE/fake-codex"
printf '.codex/state/\nignored-mutation\nproducts/\n' > "$ROLE_FIXTURE/.gitignore"
printf 'contract and diff only\n' > "$ROLE_FIXTURE/prompt"
printf 'tracked\n' > "$ROLE_FIXTURE/tracked.txt"
printf 'target a\n' > "$ROLE_FIXTURE/target-a"
printf 'target b\n' > "$ROLE_FIXTURE/target-b"
printf 'baseline\n' > "$ROLE_FIXTURE/products/app/ignored.txt"
ln -s target-a "$ROLE_FIXTURE/tracked-link"
git -C "$ROLE_FIXTURE" init -q
git -C "$ROLE_FIXTURE" add -A
git -C "$ROLE_FIXTURE" -c user.name=audit -c user.email=audit@example.invalid commit -qm fixture
if ROLE_LOG="$ROLE_LOG_FILE" CODEX_BIN="$ROLE_FIXTURE/fake-codex" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" audit "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" >/dev/null; then
    record PASS "Codex audit role: no-mutation path accepted"
else
    record FAIL "Codex audit role: no-mutation path rejected"
fi
ROLE_LOG="$ROLE_LOG_FILE" CODEX_BIN="$ROLE_FIXTURE/fake-codex" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" modify "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" >/dev/null
eval_score=$(ROLE_REPORT="$ROLE_FIXTURE/.codex/state/.refine-eval.json" ROLE_LOG="$ROLE_LOG_FILE" CODEX_BIN="$ROLE_FIXTURE/fake-codex" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" evaluate "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" "$ROLE_FIXTURE/.codex/state/.refine-eval.json")
role_count=$(grep -c 'exec --ephemeral' "$ROLE_LOG_FILE" 2>/dev/null || true)
[ "$role_count" -eq 3 ] && record PASS "Codex roles: three ephemeral process invocations" || record FAIL "Codex roles: isolation invocation count $role_count/3"
if grep -Fq -- '--ignore-user-config --disable hooks' "$ROLE_LOG_FILE"; then
    record PASS "Codex roles: user config ignored and hooks disabled"
else
    record FAIL "Codex roles: child automation config isolation"
fi
evaluate_line=$(grep -F -- '--skip-git-repo-check' "$ROLE_LOG_FILE" | tail -1)
if printf '%s' "$evaluate_line" | grep -Fq -- '--skip-git-repo-check' && ! printf '%s' "$evaluate_line" | grep -Fq -- "-C $ROLE_FIXTURE"; then
    record PASS "Codex evaluator: repository rules not auto-loaded"
else
    record FAIL "Codex evaluator: recursive rules-loading risk"
fi
git -C "$ROLE_FIXTURE" check-ignore -q .codex/state/.refine-eval.json && record PASS "Codex evaluator output: gitignored" || record FAIL "Codex evaluator output: tracked risk"
if grep -Fq '"full report survives"' "$ROLE_FIXTURE/.codex/state/.refine-eval.json" && [ "$eval_score" = '{"score":1,"suggestion":"ok"}' ]; then
    record PASS "Codex evaluator: full report preserved and final score emitted separately"
else
    record FAIL "Codex evaluator: report/final-score separation"
fi
if ROLE_LOG="$ROLE_LOG_FILE" CODEX_BIN="$ROLE_FIXTURE/fake-codex" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" evaluate "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" "$ROLE_FIXTURE/.codex/state/.refine-eval.json" >/dev/null 2>&1; then
    record FAIL "Codex evaluator: missing full report accepted"
else
    record PASS "Codex evaluator: missing full report rejected"
fi

ROLE_WORKTREE=$(mktemp -d)
rmdir "$ROLE_WORKTREE"
if git -C "$ROLE_FIXTURE" worktree add -q --detach "$ROLE_WORKTREE" HEAD &&
    ROLE_LOG="$ROLE_LOG_FILE" CODEX_BIN="$ROLE_FIXTURE/fake-codex" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" audit "$ROLE_WORKTREE" "$ROLE_FIXTURE/prompt" >/dev/null; then
    record PASS "Codex audit role: linked worktree accepted"
else
    record FAIL "Codex audit role: linked worktree rejected"
fi
git -C "$ROLE_FIXTURE" worktree remove "$ROLE_WORKTREE" >/dev/null 2>&1

cat > "$ROLE_BIN_DIR/fake-visible-mutator" <<'EOF'
#!/bin/bash
touch "$ROLE_PROJECT/visible-mutation"
cat >/dev/null
EOF
chmod +x "$ROLE_BIN_DIR/fake-visible-mutator"
if ROLE_PROJECT="$ROLE_FIXTURE" CODEX_BIN="$ROLE_BIN_DIR/fake-visible-mutator" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" audit "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" >/dev/null 2>&1; then
    record FAIL "Codex audit role: visible mutation not detected"
else
    record PASS "Codex audit role: visible mutation detected"
fi
rm -f "$ROLE_FIXTURE/visible-mutation"

cat > "$ROLE_BIN_DIR/fake-commit-mutator" <<'EOF'
#!/bin/bash
printf 'committed mutation\n' >> "$ROLE_PROJECT/tracked.txt"
git -C "$ROLE_PROJECT" add tracked.txt
git -C "$ROLE_PROJECT" -c user.name=audit -c user.email=audit@example.invalid commit -qm mutation
cat >/dev/null
EOF
chmod +x "$ROLE_BIN_DIR/fake-commit-mutator"
if ROLE_PROJECT="$ROLE_FIXTURE" CODEX_BIN="$ROLE_BIN_DIR/fake-commit-mutator" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" audit "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" >/dev/null 2>&1; then
    record FAIL "Codex audit role: clean-status commit not detected"
else
    record PASS "Codex audit role: clean-status commit detected"
fi

cat > "$ROLE_BIN_DIR/fake-ignored-mutator" <<'EOF'
#!/bin/bash
printf 'ignored mutation\n' > "$ROLE_PROJECT/ignored-mutation"
cat >/dev/null
EOF
chmod +x "$ROLE_BIN_DIR/fake-ignored-mutator"
if ROLE_PROJECT="$ROLE_FIXTURE" CODEX_BIN="$ROLE_BIN_DIR/fake-ignored-mutator" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" audit "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" >/dev/null 2>&1; then
    record FAIL "Codex audit role: ignored mutation not detected"
else
    record PASS "Codex audit role: ignored mutation detected"
fi
rm -f "$ROLE_FIXTURE/ignored-mutation"

cat > "$ROLE_BIN_DIR/fake-products-mutator" <<'EOF'
#!/bin/bash
printf 'products mutation\n' > "$ROLE_PROJECT/products/app/ignored.txt"
cat >/dev/null
EOF
chmod +x "$ROLE_BIN_DIR/fake-products-mutator"
if ROLE_PROJECT="$ROLE_FIXTURE" CODEX_BIN="$ROLE_BIN_DIR/fake-products-mutator" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" audit "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" >/dev/null 2>&1; then
    record FAIL "Codex audit role: ignored products/ mutation not detected"
else
    record PASS "Codex audit role: ignored products/ mutation detected"
fi

cat > "$ROLE_BIN_DIR/fake-skip-worktree-mutator" <<'EOF'
#!/bin/bash
git -C "$ROLE_PROJECT" update-index --skip-worktree tracked.txt
cat >/dev/null
EOF
chmod +x "$ROLE_BIN_DIR/fake-skip-worktree-mutator"
if ROLE_PROJECT="$ROLE_FIXTURE" CODEX_BIN="$ROLE_BIN_DIR/fake-skip-worktree-mutator" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" audit "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" >/dev/null 2>&1; then
    record FAIL "Codex audit role: skip-worktree mutation not detected"
else
    record PASS "Codex audit role: skip-worktree mutation detected"
fi
git -C "$ROLE_FIXTURE" update-index --no-skip-worktree tracked.txt

cat > "$ROLE_BIN_DIR/fake-assume-unchanged-mutator" <<'EOF'
#!/bin/bash
git -C "$ROLE_PROJECT" update-index --assume-unchanged tracked.txt
cat >/dev/null
EOF
chmod +x "$ROLE_BIN_DIR/fake-assume-unchanged-mutator"
if ROLE_PROJECT="$ROLE_FIXTURE" CODEX_BIN="$ROLE_BIN_DIR/fake-assume-unchanged-mutator" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" audit "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" >/dev/null 2>&1; then
    record FAIL "Codex audit role: assume-unchanged mutation not detected"
else
    record PASS "Codex audit role: assume-unchanged mutation detected"
fi
git -C "$ROLE_FIXTURE" update-index --no-assume-unchanged tracked.txt

cat > "$ROLE_BIN_DIR/fake-mode-mutator" <<'EOF'
#!/bin/bash
chmod 755 "$ROLE_PROJECT/tracked.txt"
cat >/dev/null
EOF
chmod +x "$ROLE_BIN_DIR/fake-mode-mutator"
if ROLE_PROJECT="$ROLE_FIXTURE" CODEX_BIN="$ROLE_BIN_DIR/fake-mode-mutator" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" audit "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" >/dev/null 2>&1; then
    record FAIL "Codex audit role: file-mode mutation not detected"
else
    record PASS "Codex audit role: file-mode mutation detected"
fi
chmod 644 "$ROLE_FIXTURE/tracked.txt"

cat > "$ROLE_BIN_DIR/fake-symlink-mutator" <<'EOF'
#!/bin/bash
ln -sfn target-b "$ROLE_PROJECT/tracked-link"
cat >/dev/null
EOF
chmod +x "$ROLE_BIN_DIR/fake-symlink-mutator"
if ROLE_PROJECT="$ROLE_FIXTURE" CODEX_BIN="$ROLE_BIN_DIR/fake-symlink-mutator" bash "$ROLE_FIXTURE/scripts/meta/run-isolated-role.sh" audit "$ROLE_FIXTURE" "$ROLE_FIXTURE/prompt" >/dev/null 2>&1; then
    record FAIL "Codex audit role: symlink mutation not detected"
else
    record PASS "Codex audit role: symlink mutation detected"
fi
ln -sfn target-a "$ROLE_FIXTURE/tracked-link"

rm -r "$ROLE_FIXTURE"
rm -r "$ROLE_BIN_DIR"
rm -f "$ROLE_LOG_FILE"

grep -Fq 'pushed only if explicitly requested' "$PROJECT_DIR/.claude/agents/wip-manager.md" 2>/dev/null && record PASS "wip-manager: local-only completion supported" || record FAIL "wip-manager: push incorrectly required"
if grep -Fq 'preserve-extras' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
    record FAIL "docs: stale preserve-extras claim"
else
    record PASS "docs: exact-mirror claim aligned"
fi

# --- Summary ---
echo ""
echo "=============================================="
echo "  RESULT: $PASS PASS / $FAIL FAIL"
echo "=============================================="
[ "$FAIL" -eq 0 ] && echo "  ALL PASS" || { echo "  FAILURES DETECTED"; exit 1; }
