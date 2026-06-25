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
grep -q '"SessionStart"' "$PROJECT_DIR/.claude/settings.json" 2>/dev/null && record PASS "SessionStart hook registered" || record FAIL "SessionStart hook"
grep -q '"Stop"' "$PROJECT_DIR/.claude/settings.json" 2>/dev/null && record PASS "Stop hook registered" || record FAIL "Stop hook"
[ -f "$PROJECT_DIR/.codex/config.toml" ] && record PASS ".codex/config.toml exists" || record FAIL ".codex/config.toml"
[ -f "$PROJECT_DIR/.codex/hooks.json" ] && record PASS ".codex/hooks.json exists" || record FAIL ".codex/hooks.json"
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
for f in "$PROJECT_DIR"/.claude/agents/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [ "$name" = "_schema.md" ] && continue
    [[ "$name" == _* ]] && continue
    total=$((total+1))
    head -1 "$f" 2>/dev/null | grep -q "^---" && count=$((count+1)) || record FAIL "frontmatter: $name"
done
[ "$total" -eq 2 ] && record PASS "Agent count: $total (evaluator, wip-manager)" || record FAIL "Agent count: $total (expected 2)"
record PASS "Agent frontmatter ($count/$total)"

# --- PHASE 2c: Skills (4 + karpathy-guidelines reference) ---
echo ""
echo "=== Phase 2c: Skills ==="
skills=$(ls "$PROJECT_DIR"/.claude/skills/*/SKILL.md 2>/dev/null | wc -l)
[ "$skills" -eq 4 ] && record PASS "Skills: $skills/4 (refine, status, verify, karpathy-guidelines)" || record FAIL "Skills: $skills (expected 4)"

# --- PHASE 2d: Rules (5 portable) ---
echo ""
echo "=== Phase 2d: Rules ==="
EXPECTED_RULES="audit-discipline behavioral-core commit-discipline destructive-ops-discipline devcontainer-patterns"
missing=""
for r in $EXPECTED_RULES; do
    [ -f "$PROJECT_DIR/.claude/rules/$r.md" ] || missing="$missing $r"
done
if [ -z "$missing" ]; then
    record PASS "Rules: all 5 portable rules present ($EXPECTED_RULES)"
else
    record FAIL "Rules: missing$missing"
fi
rules_total=$(ls "$PROJECT_DIR"/.claude/rules/*.md 2>/dev/null | wc -l)
[ "$rules_total" -eq 6 ] && record PASS "Rules count: $rules_total/6" || record FAIL "Rules count: $rules_total (expected 6)"

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

# --- Summary ---
echo ""
echo "=============================================="
echo "  RESULT: $PASS PASS / $FAIL FAIL"
echo "=============================================="
[ "$FAIL" -eq 0 ] && echo "  ALL PASS" || { echo "  FAILURES DETECTED"; exit 1; }
