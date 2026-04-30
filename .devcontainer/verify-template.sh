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
[ "$skills" -eq 5 ] && record PASS "Skills: $skills/5 (refine, status, verify, wiki, karpathy-guidelines)" || record FAIL "Skills: $skills (expected 5)"

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
[ "$rules_total" -eq 5 ] && record PASS "Rules count: $rules_total/5" || record FAIL "Rules count: $rules_total (expected 5)"

# --- PHASE 2e: Codex hooks (4) ---
echo ""
echo "=== Phase 2e: Codex Hooks ==="
codex_hooks=$(ls "$PROJECT_DIR"/.codex/hooks/*.sh 2>/dev/null | wc -l)
[ "$codex_hooks" -eq 4 ] && record PASS "Codex hooks: $codex_hooks/4 (session-start, pre-commit-gate, pre-push-gate, refinement-gate)" || record FAIL "Codex hooks: $codex_hooks (expected 4)"
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
