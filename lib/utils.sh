# === multiplexor lib utils ===
# Shared helpers: platform detection, command checks, availability helpers.

# --- colors ---
_COLOR_BOLD='\033[1m'
_COLOR_GREEN='\033[0;32m'
_COLOR_YELLOW='\033[0;33m'
_COLOR_RED='\033[0;31m'
_COLOR_RESET='\033[0m'

_log_ok()  { printf "${_COLOR_GREEN}✓${_COLOR_RESET} %s\n" "$1"; }
_log_warn() { printf "${_COLOR_YELLOW}⚠${_COLOR_RESET} %s\n" "$1"; }
_log_err() { printf "${_COLOR_RED}✗${_COLOR_RESET} %s\n" "$1"; }
_log_info() { printf "  %s\n" "$1"; }

# --- platform detection ---
_detect_platform() {
    local os
    os="$(uname -s 2>/dev/null || echo "Unknown")"
    case "$os" in
        Darwin)  echo "macos" ;;
        Linux)   echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)       echo "$os" ;;
    esac
}

_detect_arch() {
    local arch
    arch="$(uname -m 2>/dev/null || echo "unknown")"
    case "$arch" in
        x86_64)  echo "x64" ;;
        arm64|aarch64) echo "arm64" ;;
        *)       echo "$arch" ;;
    esac
}

# --- command existence ---
_cmd_exists() {
    local cmd_str="$1"
    local bin="${cmd_str%% *}"
    if [[ "$bin" == */* ]]; then
        [[ -x "$bin" ]] && return 0
        return 1
    fi
    command -v "$bin" &>/dev/null
}

# --- availability checks ---
_check_env_vars() {
    IFS=',' read -ra KEYS <<< "$1"
    for key in "${KEYS[@]}"; do
        [[ -n "${!key:-}" ]] && return 0
    done
    return 1
}

_check_cli_status() {
    local cmd="$1"
    if _cmd_exists "$cmd"; then
        local bin="${cmd%% *}"
        local tmpfile="/tmp/mpx_cli_$$.txt"
        $bin status > "$tmpfile" 2>&1 &
        local pid=$!
        local i=0
        while kill -0 $pid 2>/dev/null; do
            sleep 0.5
            i=$((i + 1))
            if (( i >= 6 )); then
                kill $pid 2>/dev/null
                wait $pid 2>/dev/null
                rm -f "$tmpfile"
                return 1
            fi
        done
        wait $pid 2>/dev/null
        if grep -qiE "authenticated|ready|credits" "$tmpfile" 2>/dev/null; then
            rm -f "$tmpfile"
            return 0
        fi
        rm -f "$tmpfile"
    fi
    return 1
}

# Ollama: check via `ollama list` (returns 0 if server responds)
_check_ollama() {
    if ! _cmd_exists "ollama"; then
        return 1
    fi
    local tmpfile="/tmp/mpx_ollama_$$.txt"
    ollama list > "$tmpfile" 2>&1 &
    local pid=$!
    local i=0
    while kill -0 $pid 2>/dev/null; do
        sleep 0.5
        i=$((i + 1))
        if (( i >= 6 )); then
            kill $pid 2>/dev/null
            wait $pid 2>/dev/null
            rm -f "$tmpfile"
            return 1
        fi
    done
    wait $pid 2>/dev/null
    local rc=$?
    rm -f "$tmpfile"
    return $rc
}

_check_http() {
    [[ -n "$1" ]] && curl -sf "$1" &>/dev/null
}
