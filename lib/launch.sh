# Mock launch: capture command to file
_try_launch() {
    echo "$1" > /tmp/mpx_launch_cmd.txt
    return 0
}

cmd_run() {
    local force_provider=""
    local dry_run=false
    local profile=""
    local extra_args=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider|-p)
                [[ -z "${2:-}" ]] && { echo "Error: --provider requires an argument." >&2; exit 1; }
                force_provider="$2"; shift 2 ;;
            --profile)
                [[ -z "${2:-}" ]] && { echo "Error: --profile requires an argument." >&2; exit 1; }
                profile="$2"; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            --) shift; extra_args="$*"; break ;;
            -*) echo "Error: Unknown flag '$1'." >&2; exit 1 ;;
            *) extra_args="$*"; break ;;
        esac
    done

    if [[ -n "$profile" ]] && [[ "$profile" != "balanced" ]]; then
        echo "⚠ Profile '$profile' is not implemented yet. Using default selection." >&2
    fi

    if [[ -n "$force_provider" ]]; then
        local found=false
        for p in $CFG_ORDER; do [[ "$p" == "$force_provider" ]] && found=true && break; done
        [[ "$found" == false ]] && { echo "Error: Unknown provider '$force_provider'." >&2; echo "Known: $CFG_ORDER" >&2; exit 1; }
        get_enabled "$force_provider" || { echo "Error: Provider '$force_provider' is disabled." >&2; exit 1; }
        _detect "$force_provider" || { echo "Error: Provider '$force_provider' is not installed." >&2; exit 1; }
        local sc; sc=$(get_score "$force_provider")
        [[ "$sc" -eq 0 ]] && { echo "Error: Provider '$force_provider' is not available." >&2; exit 1; }

        local cmd; cmd=$(get_cmd "$force_provider")
        if [[ "$dry_run" == true ]]; then
            echo "Would launch:"; echo "  $cmd"; return
        fi
        echo "→ $force_provider (score: $sc)"
        echo "→ $cmd"
        _try_launch "$cmd"
        return
    fi

    _build_candidates
    [[ -z "$_cands" ]] && { echo "Error: No AI provider available." >&2; exit 1; }

    local tried=0 failures=""
    for provider in $_cands; do
        [[ -z "$provider" ]] && continue
        tried=$((tried + 1))

        if ! is_available "$provider"; then
            local reason; reason=$(get_unavail_reason "$provider")
            echo "Skipping $provider: $reason" >&2
            failures="$failures$provider ($reason)
"
            continue
        fi

        local cmd; cmd=$(get_cmd "$provider")
        [[ -n "$extra_args" ]] && cmd="$cmd $extra_args"

        if [[ "$dry_run" == true ]]; then
            echo "Would launch:"; echo "  $cmd"; return
        fi

        echo "Trying $provider..." >&2
        if _try_launch "$cmd"; then
            echo "→ $provider launched successfully."
            return
        else
            local reason; reason=$(get_unavail_reason "$provider")
            echo "$provider failed: $reason" >&2
            failures="$failures$provider ($reason)
"
        fi
    done

    echo "" >&2
    echo "Error: No provider could be launched." >&2
    echo "Attempted $tried provider(s):" >&2
    echo "$failures" | grep -v '^$' | while IFS= read -r line; do echo "  - $line" >&2; done
    echo "Run 'multiplexor doctor' to diagnose." >&2
    exit 1
}
