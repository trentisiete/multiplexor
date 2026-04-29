#!/usr/bin/env bash
# Minimal tests for multiplexor — core logic only.
# Uses mock commands; no real providers or credentials needed.
set -eo pipefail

MPX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="/tmp/mpx_test_$$"
MOCK_BIN="$TMP/mock_bin"
mkdir -p "$MOCK_BIN" "$TMP"

errors=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; echo "    expected: $2"; echo "    got:      $3"; errors=$((errors+1)); }

# --- Run a snippet with a clean config path (no system config) ---
_run_lib() {
    local snippet="$1"
    local config_file="${2:-$TMP/empty.yaml}"
    CONFIG_PATH="$config_file" bash -c '
        source "'"$MPX_DIR"'/lib/utils.sh"
        source "'"$MPX_DIR"'/lib/config.sh"
        source "'"$MPX_DIR"'/lib/providers.sh"
        '"$snippet"'
    ' 2>/dev/null
}

_make_mock() {
    cat > "$MOCK_BIN/$1" << 'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
    status) echo "authenticated"; exit 0 ;;
    list)   echo "NAME     ID    SIZE"; exit 0 ;;
    *)      echo "mock $0 running"; exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/$1"
}

# ===========================
# TEST 1: Default config loads all providers
# ===========================
echo "=== TEST 1: Default config loads providers ==="

output=$(_run_lib 'echo "$CFG_ORDER"')

if echo "$output" | grep -q "claude" && echo "$output" | grep -q "ollama"; then
    pass "all providers loaded ($output)"
else
    fail "provider list" "contains claude,ollama" "$output"
fi

# ===========================
# TEST 2: Disabled provider gets score 0
# ===========================
echo ""
echo "=== TEST 2: Disabled provider → score 0 ==="

cat > "$TMP/cfg.yaml" << 'YAML'
providers:
  hermes:
    enabled: false
    priority: 60
YAML

_make_mock "hermes"
export PATH="$MOCK_BIN:$PATH"

output=$(_run_lib 'echo "hermes=$(get_score hermes)"' "$TMP/cfg.yaml")

if echo "$output" | grep -q "hermes=0"; then
    pass "disabled hermes → score 0"
else
    fail "disabled score" "hermes=0" "$output"
fi

# ===========================
# TEST 3: Not-installed provider → score 0
# ===========================
echo ""
echo "=== TEST 3: Not-installed provider → score 0 ==="

output=$(_run_lib 'echo "gemini=$(get_score gemini)"')

# gemini is not in PATH → not installed → score 0
if echo "$output" | grep -q "gemini=0"; then
    pass "not-installed gemini → score 0"
else
    fail "not-installed score" "gemini=0" "$output"
fi

# ===========================
# TEST 4: Score = priority + credits bonus
# ===========================
echo ""
echo "=== TEST 4: Score calculation ==="

_make_mock "claude"
_make_mock "codex"

cat > "$TMP/cfg.yaml" << 'YAML'
providers:
  claude:
    enabled: true
    priority: 70
    credits_hint: high
  codex:
    enabled: true
    priority: 50
    credits_hint: low
YAML

# claude uses check_type=cli_status (mock passes status check)
# codex uses check_type=env — set OPENAI_API_KEY to make it available
output=$(_run_lib '
    echo "claude=$(get_score claude)"
    echo "codex=$(get_score codex)"
' "$TMP/cfg.yaml")

# claude: 70 + 20 = 90
# codex: 50 - 10 = 40 (needs OPENAI_API_KEY, which is NOT set → score 0)
# Actually codex has check_type=env and OPENAI_API_KEY is not set → not available → 0
# So we test claude only for the bonus, and verify codex=0 due to no env
if echo "$output" | grep -q "claude=90"; then
    pass "claude=90 (priority 70 + credits high 20)"
else
    fail "claude score" "claude=90" "$output"
fi

# codex without env var should be 0 (not available)
if echo "$output" | grep -q "codex=0"; then
    pass "codex=0 (env check fails without OPENAI_API_KEY)"
else
    fail "codex score (no env)" "codex=0" "$output"
fi

# Now with the env var set, codex should get 40
output=$(OPENAI_API_KEY=fake-key bash -c '
    CONFIG_PATH="'"$TMP/cfg.yaml"'"
    source "'"$MPX_DIR"'/lib/utils.sh"
    source "'"$MPX_DIR"'/lib/config.sh"
    source "'"$MPX_DIR"'/lib/providers.sh"
    echo "codex=$(get_score codex)"
' 2>/dev/null)

if echo "$output" | grep -q "codex=40"; then
    pass "codex=40 (priority 50 - credits low 10, with OPENAI_API_KEY set)"
else
    fail "codex score (with env)" "codex=40" "$output"
fi

# ===========================
# TEST 5: Highest score wins selection
# ===========================
echo ""
echo "=== TEST 5: Selection picks highest score ==="

# Use the same config with OPENAI_API_KEY so both are available
output=$(OPENAI_API_KEY=fake-key bash -c '
    CONFIG_PATH="'"$TMP/cfg.yaml"'"
    source "'"$MPX_DIR"'/lib/utils.sh"
    source "'"$MPX_DIR"'/lib/config.sh"
    source "'"$MPX_DIR"'/lib/providers.sh"
    _build_candidates
    echo "$_cands"
' 2>/dev/null)

# claude (90) should come before codex (40)
if echo "$output" | grep -q "claude" && echo "$output" | grep -q "codex"; then
    pos_claude=$(echo "$output" | awk '{for(i=1;i<=NF;i++) if($i=="claude") print i}')
    pos_codex=$(echo "$output" | awk '{for(i=1;i<=NF;i++) if($i=="codex") print i}')
    if [[ "$pos_claude" -lt "$pos_codex" ]]; then
        pass "claude selected before codex"
    else
        fail "selection order" "claude before codex" "$output"
    fi
else
    fail "candidates" "claude,codex" "$output"
fi

# ===========================
# TEST 6: Fallback used when primary unavailable
# ===========================
echo ""
echo "=== TEST 6: Fallback when primary unavailable ==="

# Disable all default non-fallback providers, enable codex as fallback
# and claude as primary without env var (unavailable)
cat > "$TMP/cfg.yaml" << 'YAML'
providers:
  claude:
    enabled: true
    priority: 80
  codex:
    enabled: true
    priority: 30
    fallback_only: true
  gemini:
    enabled: false
  openrouter:
    enabled: false
  hermes:
    enabled: false
  opencode:
    enabled: false
  ollama:
    enabled: false
YAML

# Without OPENAI_API_KEY, claude is available (cli_status with mock)
# but codex is not (env check). We need to make claude unavailable.
# Since claude mock returns "authenticated" on status, it IS available.
# Let's instead disable claude and test with codex fallback only.

_make_mock "claude"

# With claude available (mock status passes), it wins over codex fallback
output=$(bash -c '
    CONFIG_PATH="'"$TMP/cfg.yaml"'"
    PATH="'"$MOCK_BIN"':$PATH"
    source "'"$MPX_DIR"'/lib/utils.sh"
    source "'"$MPX_DIR"'/lib/config.sh"
    source "'"$MPX_DIR"'/lib/providers.sh"
    _find_best
    echo "best=$_best score=$_best_score fallback=$_used_fallback"
' 2>/dev/null)

# claude has mock status → available → wins
if echo "$output" | grep -q "best=claude" && echo "$output" | grep -q "fallback=false"; then
    pass "claude wins when available (not fallback)"
else
    fail "selection" "best=claude fallback=false" "$output"
fi

# Now disable claude → codex fallback should win
cat > "$TMP/cfg2.yaml" << 'YAML'
providers:
  claude:
    enabled: false
  codex:
    enabled: true
    priority: 30
    fallback_only: true
  gemini:
    enabled: false
  openrouter:
    enabled: false
  hermes:
    enabled: false
  opencode:
    enabled: false
  ollama:
    enabled: false
YAML

output=$(OPENAI_API_KEY=fake-key bash -c '
    CONFIG_PATH="'"$TMP/cfg2.yaml"'"
    PATH="'"$MOCK_BIN"':$PATH"
    source "'"$MPX_DIR"'/lib/utils.sh"
    source "'"$MPX_DIR"'/lib/config.sh"
    source "'"$MPX_DIR"'/lib/providers.sh"
    _find_best
    echo "best=$_best score=$_best_score fallback=$_used_fallback"
' 2>/dev/null)

if echo "$output" | grep -q "best=codex" && echo "$output" | grep -q "fallback=true"; then
    pass "codex selected as fallback when claude disabled"
else
    fail "fallback selection" "best=codex fallback=true" "$output"
fi

# ===========================
# TEST 7: doctor works with no providers
# ===========================
echo ""
echo "=== TEST 7: doctor works with empty config ==="

cat > "$TMP/cfg.yaml" << 'YAML'
providers:
  claude:
    enabled: false
  codex:
    enabled: false
  gemini:
    enabled: false
  openrouter:
    enabled: false
  hermes:
    enabled: false
  opencode:
    enabled: false
  ollama:
    enabled: false
YAML

output=$(CONFIG_PATH="$TMP/cfg.yaml" "$MPX_DIR/multiplexor" doctor 2>&1)
exit_code=$?

if [[ $exit_code -eq 0 ]] && echo "$output" | grep -q "Recommended:"; then
    pass "doctor exits 0 with no available providers"
else
    fail "doctor" "exit 0 + Recommended:" "$output (exit: $exit_code)"
fi

# ===========================
# TEST 8: list works with no providers
# ===========================
echo ""
echo "=== TEST 8: list works with empty config ==="

output=$(CONFIG_PATH="$TMP/cfg.yaml" "$MPX_DIR/multiplexor" list 2>&1)
exit_code=$?

if [[ $exit_code -eq 0 ]] && echo "$output" | grep -q "PROVEEDOR"; then
    pass "list exits 0 with header"
else
    fail "list" "exit 0 + PROVEEDOR" "$output (exit: $exit_code)"
fi

# ===========================
# TEST 9: --explain works with no providers
# ===========================
echo ""
echo "=== TEST 9: --explain works with no providers ==="

output=$(CONFIG_PATH="$TMP/cfg.yaml" "$MPX_DIR/multiplexor" --explain 2>&1)
exit_code=$?

if [[ $exit_code -eq 0 ]] && echo "$output" | grep -q "No provider selected"; then
    pass "--explain shows 'No provider selected'"
else
    fail "--explain" "exit 0 + No provider selected" "$output (exit: $exit_code)"
fi

# ===========================
# Summary
# ===========================
echo ""
echo "============================="
if [[ "$errors" -eq 0 ]]; then
    echo "All tests passed!"
else
    echo "$errors test(s) failed."
fi
echo "============================="

rm -rf "$TMP"
exit $errors
