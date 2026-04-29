# === multiplexor lib list ===
# List subcommand: tabular view of all providers.

cmd_list() {
    printf "%-15s %-10s %-10s %-8s %-10s %-8s\n" "PROVEEDOR" "ENABLED" "DETECTADO" "SCORE" "CREDITS" "FALLBACK"
    printf "%-15s %-10s %-10s %-8s %-10s %-8s\n" "---------" "-------" "---------" "-----" "-------" "--------"

    for provider in $CFG_ORDER; do
        local enabled="no"
        get_enabled "$provider" && enabled="yes"

        local detected="no"
        [[ "$enabled" == "yes" ]] && _detect "$provider" && detected="yes"

        local score credits fallback
        score=$(get_score "$provider")
        credits=$(get_credits "$provider")
        fallback="no"
        get_fallback "$provider" && fallback="yes"

        printf "%-15s %-10s %-10s %-8s %-10s %-8s\n" "$provider" "$enabled" "$detected" "$score" "$credits" "$fallback"
    done
}
