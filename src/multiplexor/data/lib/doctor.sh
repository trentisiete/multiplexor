# === multiplexor lib doctor ===
# Doctor subcommand: diagnostics for config and all providers.

cmd_doctor() {
    echo "multiplexor $VERSION — Doctor"
    echo ""

    # --- Config ---
    echo "Config:"
    if [[ -f "$CONFIG_PATH" ]]; then
        local pretty_path="${CONFIG_PATH/#$HOME/~}"
        _log_ok "$pretty_path"
    else
        _log_warn "no config — using defaults"
        local pretty_path="${CONFIG_PATH/#$HOME/~}"
        _log_info "(create $pretty_path to customize)"
    fi
    echo ""

    # --- Providers ---
    echo "Providers:"

    local best=""
    local best_score=0
    local best_fb=""
    local best_fb_score=0
    local found_any=false

    for provider in $CFG_ORDER; do
        local enabled="no"
        get_enabled "$provider" && enabled="yes"

        local detected="no"
        local cmd_path=""
        if [[ "$enabled" == "yes" ]] && _detect "$provider"; then
            detected="yes"
            cmd_path=$(get_cmd "$provider")
        fi

        local available="no"
        local priority
        priority=$(get_priority "$provider")
        local score
        score=$(get_score "$provider")
        local credits
        credits=$(get_credits "$provider")
        local fallback="no"
        get_fallback "$provider" && fallback="yes"

        [[ "$detected" == "yes" ]] && is_available "$provider" && available="yes"

        # Build status
        local icon="" reason=""
        if [[ "$enabled" == "no" ]]; then
            icon="✗"; reason="disabled"
        elif [[ "$detected" == "no" ]]; then
            icon="✗"; reason="not found"
        elif [[ "$available" == "no" ]]; then
            icon="✗"; reason="no auth"
        else
            icon="✓"; reason="ready"
        fi

        # Shorten path / model info
        local display_extra=""
        if [[ -n "$cmd_path" ]]; then
            local first_word="${cmd_path%% *}"
            if [[ "$first_word" == */* ]]; then
                display_extra="(${first_word/#$HOME/~})"
            fi
        fi
        if [[ "$provider" == "ollama" ]] && [[ "$detected" == "yes" ]]; then
            local model
            model=$(get_model "$provider")
            if [[ -n "$model" ]]; then
                display_extra="model: $model"
            else
                display_extra="⚠ no model set (add default_model in config)"
            fi
        fi

        printf "  %s %-12s %-10s score %-4s enabled %-3s priority %-3s credits %-7s fallback %s\n" \
            "$icon" "$provider" "$reason" "$score" "$enabled" "$priority" "$credits" "$fallback"
        [[ -n "$display_extra" ]] && printf "               %s\n" "$display_extra"

        # Track best (non-fallback vs fallback)
        if (( score > 0 )); then
            if [[ "$fallback" == "yes" ]]; then
                if (( score > best_fb_score )); then
                    best_fb_score=$score
                    best_fb=$provider
                fi
            else
                if (( score > best_score )); then
                    best_score=$score
                    best=$provider
                fi
            fi
        fi

        [[ "$detected" == "yes" ]] && found_any=true
    done

    echo ""

    # Prefer non-fallback; only use fallback if nothing else
    if [[ -z "$best" ]] && [[ -n "$best_fb" ]]; then
        best=$best_fb
        best_score=$best_fb_score
    fi

    echo "Recommended:"
    if [[ -n "$best" ]] && (( best_score > 0 )); then
        echo "  $best (score $best_score)"
    else
        echo "  none"
        if [[ "$found_any" == false ]]; then
            echo "  No provider detected. Install at least one CLI."
        fi
    fi
}
