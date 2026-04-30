#!/bin/bash
# Template verification script — run inside container
echo "=============================================="
echo "  Template Full Verification"
echo "=============================================="
echo ""

PASS=0
FAIL=0
record() { [ "$1" = "PASS" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1)); echo "$1: $2"; }

# --- PHASE 1a: Runtime ---
echo "=== Phase 1a: Runtime ==="
claude --version > /dev/null 2>&1 && record PASS "claude CLI" || record FAIL "claude CLI"
node --version > /dev/null 2>&1 && record PASS "node ($(node --version))" || record FAIL "node"
/home/vscode/.local/bin/uv --version > /dev/null 2>&1 && record PASS "uv" || record FAIL "uv"
python3 --version > /dev/null 2>&1 && record PASS "python3 ($(python3 --version 2>&1))" || record FAIL "python3"

# --- PHASE 1b: MCP ---
echo ""
echo "=== Phase 1b: MCP ==="
if [ -f /home/vscode/.claude.json ]; then
    ctx=$(grep -c '"context7"' /home/vscode/.claude.json 2>/dev/null || echo 0)
    ser=$(grep -c '"serena"' /home/vscode/.claude.json 2>/dev/null || echo 0)
    [ "$ctx" -gt 0 ] && record PASS "MCP context7" || record FAIL "MCP context7"
    [ "$ser" -gt 0 ] && record PASS "MCP serena" || record FAIL "MCP serena"
    [ -x "/home/vscode/.local/bin/uv" ] && record PASS "Serena uv path (/home/vscode/.local/bin/uv)" || record FAIL "Serena uv path"
    [ -d "/home/vscode/work/serena" ] && record PASS "Serena dir (/home/vscode/work/serena)" || record FAIL "Serena dir"
else
    record FAIL "~/.claude.json missing"
fi

# --- PHASE 1c: DS Runtime ---
echo ""
echo "=== Phase 1c: DS Runtime ==="
CONDA_DIR="/home/vscode/miniconda3"
[ -d "$CONDA_DIR" ] && record PASS "Miniconda installed" || record FAIL "Miniconda missing"

if [ -d "$CONDA_DIR" ]; then
    . "${CONDA_DIR}/etc/profile.d/conda.sh"

    # conda env ds 존재 확인
    conda env list 2>/dev/null | grep -q "^ds " && record PASS "conda env 'ds'" || record FAIL "conda env 'ds' missing"

    # Python import 테스트
    conda run -n ds python -c "import numpy; print(f'numpy {numpy.__version__}')" 2>/dev/null \
        && record PASS "import numpy" || record FAIL "import numpy"
    conda run -n ds python -c "import pandas; print(f'pandas {pandas.__version__}')" 2>/dev/null \
        && record PASS "import pandas" || record FAIL "import pandas"
    conda run -n ds python -c "import torch; print(f'torch {torch.__version__}')" 2>/dev/null \
        && record PASS "import torch" || record FAIL "import torch"
    conda run -n ds python -c "import sklearn; print(f'sklearn {sklearn.__version__}')" 2>/dev/null \
        && record PASS "import sklearn" || record FAIL "import sklearn"
    conda run -n ds python -c "import matplotlib" 2>/dev/null \
        && record PASS "import matplotlib" || record FAIL "import matplotlib"
    conda run -n ds python -c "import jupyterlab" 2>/dev/null \
        && record PASS "import jupyterlab" || record FAIL "import jupyterlab"
    conda run -n ds python -c "import duckdb" 2>/dev/null \
        && record PASS "import duckdb" || record FAIL "import duckdb"

    # Jupyter kernel 확인
    conda run -n ds python -m jupyter kernelspec list 2>/dev/null | grep -q "ds" \
        && record PASS "Jupyter kernel 'ds'" || record FAIL "Jupyter kernel 'ds' missing"
fi

# --- PHASE 2: Config files ---
echo ""
echo "=== Phase 2: Config Files ==="
[ -f /workspaces/.claude/settings.json ] && record PASS "settings.json exists" || record FAIL "settings.json"
grep -q '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"' /workspaces/.claude/settings.json 2>/dev/null && record PASS "Agent Teams env flag" || record FAIL "Agent Teams env flag"
grep -q '"SessionStart"' /workspaces/.claude/settings.json 2>/dev/null && record PASS "SessionStart hook registered" || record FAIL "SessionStart hook"
grep -q '"Stop"' /workspaces/.claude/settings.json 2>/dev/null && record PASS "Stop hook registered" || record FAIL "Stop hook"

# --- PHASE 3: Hooks ---
echo ""
echo "=== Phase 3A: Hook Syntax ==="
for f in /workspaces/.claude/hooks/*.sh; do
    bash -n "$f" 2>/dev/null && record PASS "$(basename $f)" || record FAIL "$(basename $f)"
done

# --- PHASE 3B: test-hooks.sh ---
echo ""
echo "=== Phase 3B: test-hooks.sh ==="
bash /workspaces/.claude/hooks/test-hooks.sh 2>&1 | tail -3

# --- PHASE 2b: Agents ---
echo ""
echo "=== Phase 2b: Agents ==="
count=0
for f in /workspaces/.claude/agents/*.md; do
    name=$(basename "$f")
    [ "$name" = "_schema.md" ] && continue
    [[ "$name" == _* ]] && continue
    head -1 "$f" 2>/dev/null | grep -q "^---" && count=$((count+1)) || record FAIL "frontmatter: $name"
done
record PASS "Agent frontmatter ($count/13)"

# --- PHASE 2c: Skills ---
echo ""
echo "=== Phase 2c: Skills ==="
skills=$(ls /workspaces/.claude/skills/*/SKILL.md 2>/dev/null | wc -l)
[ "$skills" -eq 8 ] && record PASS "Skills: $skills/8" || record FAIL "Skills: $skills (expected 8)"

# --- PHASE 2d: Rules ---
echo ""
echo "=== Phase 2d: Rules ==="
rules=$(ls /workspaces/.claude/rules/*.md 2>/dev/null | wc -l)
[ "$rules" -ge 3 ] && record PASS "Rules: $rules (devcontainer-patterns, iterative-retrieval, testing)" || record FAIL "Rules: $rules"
standards=$(ls /workspaces/.claude/rules/standards/*.md 2>/dev/null | wc -l)
[ "$standards" -eq 6 ] && record PASS "Standards: $standards/6" || record FAIL "Standards: $standards (expected 6)"

# --- Summary ---
echo ""
echo "=============================================="
echo "  RESULT: $PASS PASS / $FAIL FAIL"
echo "=============================================="
[ "$FAIL" -eq 0 ] && echo "  ALL PASS" || echo "  FAILURES DETECTED"
