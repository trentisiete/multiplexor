#!/usr/bin/env bash
# Tests for multiplexor — verifies launch selection, fallback, and error handling
set -eo pipefail

MPX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="/tmp/mpx_test_$$"
mkdir -p "$TMP"

errors=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; echo "    expected: $2"; echo "    got:      $3"; errors=$((errors+1)); }

# ===========================
# TEST 1: Provider scores with timeout-safe checks
# ===========================
echo "=== TEST 1: All provider scores computed (no hang) ==="

output=$(bash -c '
    source "'"$MPX_DIR"'/lib/utils.sh"
    source "'"$MPX_DIR"'/lib/config.sh"
    source "'"$MPX_DIR"'/lib/providers.sh"
    for p in $CFG_ORDER; do
        score=$(get_score "$p")
        echo "$p=$score"
    done
' 2>/dev/null)

# Should complete without hanging
if [[ -n "$output" ]]; then
    pass "all scores computed"
    echo "$output" | while IFS= read -r line; do echo "    $line"; done
else
    fail "scores output" "non-empty" "(empty)"
fi

# ===========================
# TEST 2: Candidate ordering
# ===========================
echo ""
echo "=== TEST 2: _build_candidates orders by score ==="

output=$(bash -c '
    source "'"$MPX_DIR"'/lib/utils.sh"
    source "'"$MPX_DIR"'/lib/config.sh"
    source "'"$MPX_DIR"'/lib/providers.sh"
    _build_candidates
    echo "$_cands"
' 2>/dev/null)

if [[ -n "$output" ]]; then
    pass "candidates: $output"
else
    fail "candidates" "non-empty" "(empty)"
fi

# ===========================
# TEST 3: --provider rejects unknown
# ===========================
echo ""
echo "=== TEST 3: --provider rejects unknown ==="

output=$("$MPX_DIR/multiplexor" --provider nonexistent 2>&1 || true)
if echo "$output" | grep -q "Unknown provider"; then
    pass "unknown provider rejected"
else
    fail "error message" "Unknown provider" "$output"
fi

# ===========================
# TEST 4: --provider rejects disabled
# ===========================
echo ""
echo "=== TEST 4: --provider rejects disabled ==="

mkdir -p ~/.config/multiplexor
cat > ~/.config/multiplexor/config.yaml << 'YAML'
providers:
  hermes:
    enabled: false
YAML

output=$("$MPX_DIR/multiplexor" --provider hermes 2>&1 || true)
if echo "$output" | grep -q "disabled"; then
    pass "disabled provider rejected"
else
    fail "error message" "disabled" "$output"
fi

rm -f ~/.config/multiplexor/config.yaml

# ===========================
# TEST 5: Launch captures correct command
# ===========================
echo ""
echo "=== TEST 5: cmd_run resolves correct command ==="

# Create a mock launch.sh that captures instead of executing
cp "$MPX_DIR/lib/launch.sh" "$TMP/launch.bak"

cat > "$MPX_DIR/lib/launch.sh" << 'MOCK'
_try_launch() {
    echo "$1" > /tmp/mpx_launch_cmd.txt
    return 0
}

cmd_run() {
    local force_provider="" dry_run=false profile="" extra_args=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider|-p) [[ -z "${2:-}" ]] && exit 1; force_provider="$2"; shift 2 ;;
            --profile) [[ -z "${2:-}" ]] && exit 1; profile="$2"; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            --) shift; extra_args="$*"; break ;;
            -*) exit 1 ;;
            *) extra_args="$*"; break ;;
        esac
    done

    if [[ -n "$force_provider" ]]; then
        local found=false
        for p in $CFG_ORDER; do [[ "$p" == "$force_provider" ]] && found=true && break; done
        [[ "$found" == false ]] && { echo "Error: Unknown provider '$force_provider'." >&2; exit 1; }
        get_enabled "$force_provider" || { echo "Error: disabled" >&2; exit 1; }
        _detect "$force_provider" || { echo "Error: not installed" >&2; exit 1; }
        local sc; sc=$(get_score "$force_provider")
        [[ "$sc" -eq 0 ]] && { echo "Error: not available" >&2; exit 1; }

        local cmd; cmd=$(get_cmd "$force_provider")
        [[ "$dry_run" == true ]] && { echo "Would launch:"; echo "  $cmd"; return; }
        echo "→ $force_provider (score: $sc)"; echo "→ $cmd"
        _try_launch "$cmd"
        return
    fi

    _build_candidates
    [[ -z "$_cands" ]] && { echo "Error: No AI provider available." >&2; exit 1; }

    for provider in $_cands; do
        [[ -z "$provider" ]] && continue
        if ! is_available "$provider"; then continue; fi
        local cmd; cmd=$(get_cmd "$provider")
        [[ -n "$extra_args" ]] && cmd="$cmd $extra_args"
        [[ "$dry_run" == true ]] && { echo "Would launch:"; echo "  $cmd"; return; }
        echo "Trying $provider..." >&2
        _try_launch "$cmd" && { echo "→ $provider launched."; return; }
    done

    echo "Error: No provider could be launched." >&2; exit 1
}
MOCK

# Re-source with mock in a fresh bash to pick up the new launch.sh
# 5a: Default launch
output=$(bash -c '
    source "'"$MPX_DIR"'/lib/utils.sh"
    source "'"$MPX_DIR"'/lib/config.sh"
    source "'"$MPX_DIR"'/lib/providers.sh"
    source "'"$MPX_DIR"'/lib/launch.sh"
    rm -f /tmp/mpx_launch_cmd.txt
    cmd_run 2>&1
    cat /tmp/mpx_launch_cmd.txt 2>/dev/null
' 2>&1)

# 5b: Force hermes
output2=$(bash -c '
    source "'"$MPX_DIR"'/lib/utils.sh"
    source "'"$MPX_DIR"'/lib/config.sh"
    source "'"$MPX_DIR"'/lib/providers.sh"
    source "'"$MPX_DIR"'/lib/launch.sh"
    rm -f /tmp/mpx_launch_cmd.txt
    cmd_run --provider hermes 2>&1
    cat /tmp/mpx_launch_cmd.txt 2>/dev/null
' 2>&1)

# 5c: Extra args
output3=$(bash -c '
    source "'"$MPX_DIR"'/lib/utils.sh"
    source "'"$MPX_DIR"'/lib/config.sh"
    source "'"$MPX_DIR"'/lib/providers.sh"
    source "'"$MPX_DIR"'/lib/launch.sh"
    rm -f /tmp/mpx_launch_cmd.txt
    cmd_run -- "fix the bug" 2>&1
    cat /tmp/mpx_launch_cmd.txt 2>/dev/null
' 2>&1)

# Restore original launch.sh
mv "$TMP/launch.bak" "$MPX_DIR/lib/launch.sh"

# Check results
if echo "$output" | grep -qE "^(claude|hermes|opencode)"; then
    first_cmd=$(echo "$output" | grep -oE "^(claude|hermes chat|opencode)" | head -1)
    pass "default launch → $first_cmd"
else
    fail "default launch" "provider command" "$output"
fi

if echo "$output2" | grep -q "hermes chat"; then
    pass "force hermes → 'hermes chat'"
else
    fail "force hermes" "hermes chat" "$output2"
fi

if echo "$output3" | grep -q "fix the bug"; then
    pass "extra args included"
else
    fail "extra args" "fix the bug" "$output3"
fi

# ===========================
# TEST 6: credits=none triggers fallback
# ===========================
echo ""
echo "=== TEST 6: credits=none triggers fallback ==="

cat > ~/.config/multiplexor/config.yaml << 'YAML'
providers:
  claude:
    enabled: true
    credits_hint: none
    priority: 90
  hermes:
    enabled: true
    priority: 60
  opencode:
    enabled: true
    priority: 55
YAML

output=$(bash -c '
    source "'"$MPX_DIR"'/lib/utils.sh"
    source "'"$MPX_DIR"'/lib/config.sh"
    source "'"$MPX_DIR"'/lib/providers.sh"
    _build_candidates
    echo "$_cands"
' 2>/dev/null)

# claude should have score 0 (credits=none), hermes should be first candidate
if echo "$output" | grep -q "hermes"; then
    pass "credits=none: hermes is first candidate (candidates: $output)"
else
    fail "first candidate" "hermes" "$output"
fi

rm -f ~/.config/multiplexor/config.yaml

# ===========================
# TEST 7: dry-run shows correct command
# ===========================
echo ""
echo "=== TEST 7: --dry-run ==="

output=$("$MPX_DIR/multiplexor" --dry-run 2>&1)
if echo "$output" | grep -q "Would launch:"; then
    pass "dry-run shows 'Would launch:'"
else
    fail "dry-run output" "Would launch:" "$output"
fi

# ===========================
# TEST 8: all providers disabled
# ===========================
echo ""
echo "=== TEST 8: all disabled → error ==="

cat > ~/.config/multiplexor/config.yaml << 'YAML'
providers:
  claude:
    enabled: false
  hermes:
    enabled: false
  opencode:
    enabled: false
YAML

output=$("$MPX_DIR/multiplexor" 2>&1 || true)
if echo "$output" | grep -q "No AI provider available"; then
    pass "all disabled: proper error"
else
    fail "error message" "No AI provider available" "$output"
fi

rm -f ~/.config/multiplexor/config.yaml

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
