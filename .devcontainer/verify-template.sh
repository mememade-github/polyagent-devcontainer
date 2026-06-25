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

# --- PHASE 1b: setup-env.sh lifecycle integrity ---
echo ""
echo "=== Phase 1b: setup-env.sh lifecycle ==="
SETUP="$PROJECT_DIR/.devcontainer/setup-env.sh"
grep -q 'STEP_TOTAL=5' "$SETUP" 2>/dev/null && record PASS "setup-env: STEP_TOTAL=5" || record FAIL "setup-env: STEP_TOTAL (expected 5)"
grep -q 'SKIP_CLAUDE_UPDATE' "$SETUP" 2>/dev/null && record PASS "setup-env: Claude update step" || record FAIL "setup-env: Claude update step"
grep -q 'SKIP_CODEX_UPDATE' "$SETUP" 2>/dev/null && record PASS "setup-env: Codex update step (SKIP_CODEX_UPDATE)" || record FAIL "setup-env: Codex update step"
grep -q '@openai/codex@latest' "$SETUP" 2>/dev/null && record PASS "setup-env: Codex update via prefix npm (not codex update)" || record FAIL "setup-env: Codex update mechanism"
grep -Fq 'npm config set prefix "${HOME}/.npm-global"' "$PROJECT_DIR/.devcontainer/Dockerfile" 2>/dev/null && record PASS "Dockerfile: npm prefix matches Codex install" || record FAIL "Dockerfile: npm prefix"
grep -Fq 'npm config set prefix "$CODEX_NPM_PREFIX"' "$SETUP" 2>/dev/null && record PASS "setup-env: npm prefix reconciled" || record FAIL "setup-env: npm prefix reconciled"
grep -q 'CODEX_UPDATE_LOG' "$SETUP" 2>/dev/null && record PASS "setup-env: Codex update failures are visible" || record FAIL "setup-env: Codex update failure visibility"

# --- PHASE 1c: Codex config hygiene ---
echo ""
echo "=== Phase 1c: Codex config hygiene ==="
CODEX_CONFIG="$PROJECT_DIR/.codex/config.toml"
grep -q '^hooks = true$' "$CODEX_CONFIG" 2>/dev/null && ! grep -q 'codex_hooks' "$CODEX_CONFIG" 2>/dev/null && record PASS "Codex config: modern hooks feature flag" || record FAIL "Codex config: hooks feature flag"
! grep -Eq 'model_availability_nux|model_migrations|^\[tui\.|^\[notice\.' "$CODEX_CONFIG" 2>/dev/null && record PASS "Codex config: no runtime-state blocks" || record FAIL "Codex config: runtime-state block leaked"
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
grep -Fq 'touch "$MARKER"' "$CODEX_PRECOMMIT" 2>/dev/null && record PASS "Codex pre-commit: writes Codex marker" || record FAIL "Codex pre-commit: marker write"
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
[ -f "$PROJECT_DIR/.codex/config.toml" ] && record PASS ".codex/config.toml exists" || record FAIL ".codex/config.toml"
[ -f "$PROJECT_DIR/.codex/hooks.json" ] && record PASS ".codex/hooks.json exists" || record FAIL ".codex/hooks.json"
jq -e . "$PROJECT_DIR/.codex/hooks.json" >/dev/null 2>&1 && record PASS "hooks.json valid JSON" || record FAIL "hooks.json invalid JSON"
[ -f "$PROJECT_DIR/AGENTS.md" ] && record PASS "AGENTS.md exists" || record FAIL "AGENTS.md"

# --- PHASE 2a: Karpathy alignment ---
echo ""
echo "=== Phase 2a: Karpathy Alignment ==="
grep -q "behavioral-core" "$PROJECT_DIR/CLAUDE.md" 2>/dev/null && record PASS "CLAUDE.md -> behavioral-core import" || record FAIL "CLAUDE.md -> behavioral-core import"
grep -q "behavioral-core" "$PROJECT_DIR/AGENTS.md" 2>/dev/null && record PASS "AGENTS.md -> behavioral-core import" || record FAIL "AGENTS.md -> behavioral-core import"
[ -f "$PROJECT_DIR/.claude/rules/behavioral-core.md" ] && record PASS ".claude/rules/behavioral-core.md exists" || record FAIL ".claude/rules/behavioral-core.md"
[ -f "$PROJECT_DIR/.agents/rules/behavioral-core.md" ] && record PASS ".agents/rules/behavioral-core.md (mirror) exists" || record FAIL ".agents/rules/behavioral-core.md (mirror)"

# --- PHASE 3: Hooks syntax ---
echo ""
echo "=== Phase 3A: Hook Syntax (Claude side) ==="
claude_hooks=$(ls "$PROJECT_DIR"/.claude/hooks/*.sh 2>/dev/null | wc -l)
[ "$claude_hooks" -eq 4 ] && record PASS "Claude hooks: $claude_hooks/4 (session-start, pre-commit-gate, pre-push-gate, refinement-gate)" || record FAIL "Claude hooks: $claude_hooks (expected 4)"
for f in "$PROJECT_DIR"/.claude/hooks/*.sh; do
    [ -f "$f" ] || continue
    bash -n "$f" 2>/dev/null && record PASS "$(basename $f)" || record FAIL "$(basename $f)"
done

# --- PHASE 2b: Agents ---
echo ""
echo "=== Phase 2b: Agents ==="
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

# --- PHASE 2c: Skills (4 + karpathy-guidelines reference) ---
echo ""
echo "=== Phase 2c: Skills ==="
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

# --- PHASE 2d: Rules (6 portable) ---
echo ""
echo "=== Phase 2d: Rules ==="
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

# --- PHASE 2e: Codex hooks (4) ---
echo ""
echo "=== Phase 2e: Codex Hooks ==="
codex_hook_count=$(ls "$PROJECT_DIR"/.codex/hooks/*.sh 2>/dev/null | wc -l)
[ "$codex_hook_count" -eq 4 ] && record PASS "Codex hooks: $codex_hook_count/4 (session-start, pre-commit-gate, pre-push-gate, refinement-gate)" || record FAIL "Codex hooks: $codex_hook_count (expected 4)"
for f in "$PROJECT_DIR"/.codex/hooks/*.sh; do
    [ -f "$f" ] || continue
    bash -n "$f" 2>/dev/null && record PASS "$(basename $f)" || record FAIL "$(basename $f)"
done

# --- PHASE 2f: Mirror integrity ---
echo ""
echo "=== Phase 2f: Mirror Integrity ==="
[ -d "$PROJECT_DIR/.agents/skills/evaluator" ] && record PASS ".agents/skills/evaluator (agent->skill mirror)" || record FAIL ".agents/skills/evaluator missing"
[ -d "$PROJECT_DIR/.agents/skills/wip-manager" ] && record PASS ".agents/skills/wip-manager (agent->skill mirror)" || record FAIL ".agents/skills/wip-manager missing"
[ -x "$PROJECT_DIR/scripts/sync-agents-mirror.sh" ] && record PASS "sync-agents-mirror.sh executable" || record FAIL "sync-agents-mirror.sh"
[ -x "$PROJECT_DIR/scripts/meta/run-isolated-role.sh" ] && record PASS "run-isolated-role.sh executable" || record FAIL "run-isolated-role.sh"

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

ROLE_FIXTURE=$(mktemp -d)
ROLE_BIN_DIR=$(mktemp -d)
ROLE_LOG_FILE=$(mktemp)
mkdir -p "$ROLE_FIXTURE/.codex/state" "$ROLE_FIXTURE/scripts/meta"
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
printf '.codex/state/\nignored-mutation\n' > "$ROLE_FIXTURE/.gitignore"
printf 'contract and diff only\n' > "$ROLE_FIXTURE/prompt"
printf 'tracked\n' > "$ROLE_FIXTURE/tracked.txt"
printf 'target a\n' > "$ROLE_FIXTURE/target-a"
printf 'target b\n' > "$ROLE_FIXTURE/target-b"
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
