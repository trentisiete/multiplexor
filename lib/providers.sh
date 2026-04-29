# === multiplexor lib providers ===
# Provider interface: detection, scoring, availability, metadata access.

# --- Config value accessor ---
_cfg_val() {
    local key="$1"
    local up
    up="$(echo "$2" | tr '[:lower:]' '[:upper:]')"
    eval "echo \"\${CFG_${key}_$up:-}\""
}

# --- Command ---
get_cmd() {
    local val
    val="$(_cfg_val COMMAND "$1")"
    if [[ -n "$val" ]]; then
        echo "$val"
    else
        provider_meta "$1" command
    fi
}

# --- Model (for ollama and similar) ---
get_model() {
    local val
    val="$(_cfg_val MODEL "$1")"
    echo "$val"
}

# --- Enabled ---
get_enabled() {
    local val
    val="$(_cfg_val ENABLED "$1")"
    [[ "${val:-true}" == "true" ]]
}

# --- Installed detection ---
_detect() {
    _cmd_exists "$(get_cmd "$1")"
}

# --- Availability check ---
# Returns 0 if the provider can be used (auth/API/server ready).
is_available() {
    local name="$1"

    # Env vars check — config overrides adapter defaults
    local envs
    envs="$(_cfg_val ENVS "$name")"
    if [[ -z "$envs" ]]; then
        envs=$(provider_meta "$name" env_vars)
    fi

    if [[ -n "$envs" ]]; then
        _check_env_vars "$envs" && return 0
    fi

    # Type-specific check
    local ctype
    ctype="$(_cfg_val CTYPE "$name")"
    if [[ -z "$ctype" ]]; then
        ctype=$(provider_meta "$name" check_type)
    fi

    case "$ctype" in
        env)        return 1 ;;
        cli_status) _check_cli_status "$(get_cmd "$name")" ;;
        ollama)     _check_ollama ;;
        http*)
            local url=""
            if [[ "$ctype" == "http+"* ]]; then
                url="${ctype#http+}"
            else
                url="$(_cfg_val CURL "$name")"
                [[ -z "$url" ]] && url=$(provider_meta "$name" check_url)
            fi
            _check_http "$url"
            ;;
        installed)
            return 0  ;;
    esac
}

# --- Credits ---
get_credits() {
    local val
    val="$(_cfg_val CREDITS "$1")"
    echo "${val:-unknown}"
}

# --- Priority ---
get_priority() {
    local val
    val="$(_cfg_val PRIORITY "$1")"
    if [[ -n "$val" ]]; then
        echo "$val"
    else
        provider_meta "$1" priority
    fi
}

# --- Fallback flag ---
get_fallback() {
    local val
    val="$(_cfg_val FALLBACK "$1")"
    [[ "${val:-false}" == "true" ]]
}

# --- Score computation ---
get_score() {
    # Disabled → not eligible
    if ! get_enabled "$1"; then
        echo "0"
        return
    fi

    # Not installed → not eligible
    if ! _detect "$1"; then
        echo "0"
        return
    fi

    local score
    score=$(get_priority "$1")

    # Credits adjustment
    local credits
    credits=$(get_credits "$1")
    case "$credits" in
        high)   (( score += 20 )) ;;
        medium) (( score += 10 )) ;;
        low)    (( score -= 10 )) ;;
        none)   echo "0"; return ;;
        *)      ;; # unknown → +0
    esac

    # Not available (no auth/env/server) → not eligible
    if ! is_available "$1"; then
        echo "0"
        return
    fi

    echo "$score"
}

# --- Unavailability reason ---
get_unavail_reason() {
    local name="$1"

    local credits
    credits=$(get_credits "$name")
    case "$credits" in
        none) echo "credits exhausted" ; return ;;
    esac

    local envs
    envs="$(_cfg_val ENVS "$name")"
    if [[ -z "$envs" ]]; then
        envs=$(provider_meta "$name" env_vars)
    fi

    if [[ -n "$envs" ]]; then
        local missing=""
        IFS=',' read -ra KEYS <<< "$envs"
        for key in "${KEYS[@]}"; do
            if [[ -z "${!key:-}" ]]; then
                missing="$missing \$$key"
            fi
        done
        if [[ -n "$missing" ]]; then
            echo "missing env var(s):$missing"
            return
        fi
    fi

    # Ollama-specific: missing model
    if [[ "$name" == "ollama" ]]; then
        local model
        model=$(get_model "$name")
        if [[ -z "$model" ]]; then
            echo "no model configured (add default_model in config.yaml)"
            return
        fi
    fi

    local ctype
    ctype="$(_cfg_val CTYPE "$name")"
    if [[ -z "$ctype" ]]; then
        ctype=$(provider_meta "$name" check_type)
    fi

    case "$ctype" in
        env)        echo "no authentication configured" ;;
        cli_status) echo "CLI not authenticated" ;;
        ollama)     echo "ollama server not responding" ;;
        http*)      echo "service not responding" ;;
        installed)  echo "unknown reason" ;;
        *)          echo "not available" ;;
    esac
}

# --- Build launch command ---
# For providers like ollama, builds the full command with model.
# Returns: "ollama run llama3.2:3b" or just the raw command for others.
_build_cmd() {
    local name="$1"
    local cmd
    cmd=$(get_cmd "$name")

    # Ollama: build "ollama run <model>" if model is configured
    if [[ "$name" == "ollama" ]]; then
        local model
        model=$(get_model "$name")
        if [[ -n "$model" ]]; then
            echo "$cmd run $model"
            return
        fi
    fi

    echo "$cmd"
}

# --- Build sorted candidate list ---
# Sets global _cands (space-separated provider names).
# Non-fallback first (score desc), then fallback (score desc).
_build_candidates() {
    local main_items=""
    local fb_items=""

    for provider in $CFG_ORDER; do
        get_enabled "$provider" || continue

        local score
        score=$(get_score "$provider")
        [[ "$score" -eq 0 ]] && continue

        local item="${score}:${provider}"
        if get_fallback "$provider"; then
            fb_items="$fb_items $item"
        else
            main_items="$main_items $item"
        fi
    done

    _cands=""
    for prefix in "$main_items" "$fb_items"; do
        [[ -z "$prefix" ]] && continue
        local sorted
        sorted=$(echo "$prefix" | tr ' ' '\n' | grep -v '^$' | sort -t: -k1 -nr | cut -d: -f2 | tr '\n' ' ')
        _cands="$_cands $sorted"
    done
}

# --- Find best provider (for explain) ---
# Sets: _best, _best_score, _best_fb, _best_fb_score, _used_fallback
_find_best() {
    _best=""
    _best_score=0
    _best_fb=""
    _best_fb_score=0

    for provider in $CFG_ORDER; do
        get_enabled "$provider" || continue

        local score
        score=$(get_score "$provider")
        [[ "$score" -eq 0 ]] && continue

        if get_fallback "$provider"; then
            if (( score > _best_fb_score )); then
                _best_fb_score=$score
                _best_fb=$provider
            fi
        else
            if (( score > _best_score )); then
                _best_score=$score
                _best=$provider
            fi
        fi
    done

    _used_fallback=false
    if [[ -z "$_best" ]] && [[ -n "$_best_fb" ]]; then
        _best=$_best_fb
        _best_score=$_best_fb_score
        _used_fallback=true
    fi
}
