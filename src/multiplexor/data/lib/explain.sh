# === multiplexor lib explain ===
# Explain subcommand: shows why a provider was selected and scores of others.

cmd_explain() {
    _find_best

    local selected="$_best"
    local selected_score=$_best_score

    echo "multiplexor $VERSION — Explain"
    echo ""

    if [[ -z "$selected" ]]; then
        echo "No provider selected."
        echo ""
        echo "Reasons:"
        for provider in $CFG_ORDER; do
            local enabled="no"
            get_enabled "$provider" && enabled="yes"
            local detected="no"
            [[ "$enabled" == "yes" ]] && _detect "$provider" && detected="yes"
            local fallback="no"
            get_fallback "$provider" && fallback="yes"
            local reason="unknown"
            if [[ "$enabled" == "no" ]]; then
                reason="disabled"
            elif [[ "$detected" == "no" ]]; then
                reason="not installed"
            elif [[ "$fallback" == "yes" ]]; then
                reason="fallback only"
            else
                reason="no auth / not available"
            fi
            echo "  $provider: $reason"
        done
        return
    fi

    echo "Selected provider: $selected"
    echo ""

    # Show reasons
    echo "Reason:"

    local enabled="no"
    get_enabled "$selected" && enabled="yes"
    [[ "$enabled" == "yes" ]] && echo "  - Provider is enabled." || echo "  - Provider is disabled (override)."

    local detected="no"
    _detect "$selected" && detected="yes"
    if [[ "$detected" == "yes" ]]; then
        local cmd_val
        cmd_val=$(get_cmd "$selected")
        echo "  - Command found: $cmd_val"
    else
        echo "  - Command NOT found."
    fi

    # Show model for ollama
    if [[ "$selected" == "ollama" ]]; then
        local model
        model=$(get_model "$selected")
        if [[ -n "$model" ]]; then
            echo "  - Model: $model"
            echo "  - Launch command: ollama run $model"
        else
            echo "  - Model: NOT SET (add default_model in config.yaml)"
        fi
    fi

    local priority
    priority=$(get_priority "$selected")
    echo "  - Priority: $priority"

    local credits
    credits=$(get_credits "$selected")
    echo "  - Credits: $credits"

    # Show credits adjustment
    case "$credits" in
        high)   echo "  - Credits bonus: +20" ;;
        medium) echo "  - Credits bonus: +10" ;;
        low)    echo "  - Credits penalty: -10" ;;
        none)   echo "  - Credits: not eligible" ;;
        *)      echo "  - Credits adjustment: +0 (unknown)" ;;
    esac

    echo "  - Final score: $selected_score"

    if [[ "$_used_fallback" == true ]]; then
        echo "  - Note: selected as fallback (no other provider available)"
    fi

    echo ""

    # Show other providers
    echo "Other providers:"
    for provider in $CFG_ORDER; do
        [[ "$provider" == "$selected" ]] && continue

        local enabled2="no"
        get_enabled "$provider" && enabled2="yes"
        local detected2="no"
        [[ "$enabled2" == "yes" ]] && _detect "$provider" && detected2="yes"
        local fallback2="no"
        get_fallback "$provider" && fallback2="yes"
        local score2
        score2=$(get_score "$provider")
        local credits2
        credits2=$(get_credits "$provider")

        local summary=""
        if [[ "$enabled2" == "no" ]]; then
            summary="disabled"
        elif [[ "$detected2" == "no" ]]; then
            summary="not installed"
        elif [[ "$score2" -eq 0 ]]; then
            summary="not available (no auth)"
        elif [[ "$fallback2" == "yes" ]]; then
            summary="fallback only"
        else
            summary="score $score2"
        fi
        echo "  $provider: $summary"
    done
}
