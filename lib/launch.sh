# === multiplexor lib launch ===
# Launch logic: terminal detection, fallback retry, error summary.

# --- Try launching a command in a terminal ---
_try_launch() {
    local cmd="$1"
    local os
    os="$(uname -s 2>/dev/null || echo "Unknown")"

    case "$os" in
        Darwin)
            osascript -e "tell app \"Terminal\" to do script \"$cmd\"" 2>/dev/null
            return $?
            ;;
        Linux)
            gnome-terminal -- bash -c "$cmd" 2>/dev/null && return 0
            x-terminal-emulator -e "$cmd" 2>/dev/null && return 0
            exec bash -c "$cmd"
            return $?
            ;;
        MINGW*|MSYS*|CYGWIN*)
            cmd //c "$cmd" 2>/dev/null
            return $?
            ;;
        *)
            exec bash -c "$cmd"
            return $?
            ;;
    esac
}

# --- Main run command ---
# Handles --provider, --profile, --dry-run, -- "extra args"
cmd_run() {
    local force_provider=""
    local dry_run=false
    local profile=""
    local extra_args=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider|-p)
                [[ -z "${2:-}" ]] && { echo "Error: --provider requires an argument." >&2; exit 1; }
                force_provider="$2"
                shift 2
                ;;
            --profile)
                [[ -z "${2:-}" ]] && { echo "Error: --profile requires an argument." >&2; exit 1; }
                profile="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --)
                shift
                extra_args="$*"
                break
                ;;
            -*)
                echo "Error: Unknown flag '$1'." >&2
                echo "Run 'multiplexor --help' for usage." >&2
                exit 1
                ;;
            *)
                extra_args="$*"
                break
                ;;
        esac
    done

    # Profile warning (not implemented yet)
    if [[ -n "$profile" ]] && [[ "$profile" != "balanced" ]]; then
        echo "⚠ Profile '$profile' is not implemented yet. Using default selection." >&2
    fi

    # Handle --provider (single, no fallback)
    if [[ -n "$force_provider" ]]; then
        local found=false
        for p in $CFG_ORDER; do
            [[ "$p" == "$force_provider" ]] && found=true && break
        done
        if [[ "$found" == false ]]; then
            echo "Error: Unknown provider '$force_provider'." >&2
            echo "Known providers: $CFG_ORDER" >&2
            exit 1
        fi
        if ! get_enabled "$force_provider"; then
            echo "Error: Provider '$force_provider' is disabled." >&2
            exit 1
        fi
        if ! _detect "$force_provider"; then
            echo "Error: Provider '$force_provider' is not installed." >&2
            exit 1
        fi
        local sc
        sc=$(get_score "$force_provider")
        if [[ "$sc" -eq 0 ]]; then
            # Ollama-specific: show model hint
            if [[ "$force_provider" == "ollama" ]]; then
                echo "Error: Ollama is installed but not configured." >&2
                echo "Add 'default_model' to your config:" >&2
                echo "" >&2
                echo "  providers:" >&2
                echo "    ollama:" >&2
                echo "      enabled: true" >&2
                echo "      default_model: \"llama3.2:3b\"" >&2
            else
                echo "Error: Provider '$force_provider' is not available." >&2
            fi
            exit 1
        fi

        local cmd
        cmd=$(_build_cmd "$force_provider")
        if [[ "$dry_run" == true ]]; then
            echo "Would launch:"
            echo "  $cmd"
            return
        fi
        echo "→ $force_provider (score: $sc)"
        echo "→ $cmd"
        _try_launch "$cmd"
        return
    fi

    # Build sorted candidate list
    _build_candidates

    if [[ -z "$_cands" ]]; then
        echo "Error: No AI provider available." >&2
        echo "Run 'multiplexor doctor' to see what is installed." >&2
        # Hint about ollama if it's installed but not configured
        if _detect "ollama" 2>/dev/null; then
            echo "" >&2
            echo "Ollama is installed. Configure it with:" >&2
            echo "  default_model: \"llama3.2:3b\"" >&2
        fi
        exit 1
    fi

    # Try each candidate in order
    local tried=0
    local failures=""

    for provider in $_cands; do
        [[ -z "$provider" ]] && continue
        tried=$((tried + 1))

        # Re-check availability at runtime
        if ! is_available "$provider"; then
            local reason
            reason=$(get_unavail_reason "$provider")
            echo "Skipping $provider: $reason" >&2
            failures="$failures$provider ($reason)
"
            continue
        fi

        local cmd
        cmd=$(_build_cmd "$provider")
        [[ -n "$extra_args" ]] && cmd="$cmd $extra_args"

        if [[ "$dry_run" == true ]]; then
            echo "Would launch:"
            echo "  $cmd"
            return
        fi

        # Try launching
        echo "Trying $provider..." >&2
        if _try_launch "$cmd" 2>/dev/null; then
            echo "→ $provider launched successfully."
            return
        else
            local reason
            reason=$(get_unavail_reason "$provider")
            echo "$provider failed: $reason" >&2
            failures="$failures$provider ($reason)
"
        fi
    done

    # All candidates failed
    echo "" >&2
    echo "Error: No provider could be launched." >&2
    echo "" >&2
    echo "Attempted $tried provider(s):" >&2
    echo "$failures" | grep -v '^$' | while IFS= read -r line; do
        echo "  - $line" >&2
    done
    echo "" >&2
    echo "Run 'multiplexor doctor' to diagnose." >&2
    exit 1
}
