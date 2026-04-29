# === multiplexor lib config ===
# Configuration loading: paths, defaults, YAML parsing, runtime config.

# --- Constants ---
VERSION="0.2.0"

# --- Default providers table ---
# Format: name|command|env_vars|check_type|check_url|priority
_DEFAULT_PROVIDERS=(
    "claude|claude|ANTHROPIC_API_KEY|cli_status||90"
    "codex|codex|OPENAI_API_KEY|env||85"
    "gemini|gemini|GOOGLE_API_KEY,GEMINI_API_KEY|env||75"
    "ollama|ollama||http|http://localhost:11434/api/tags|70"
    "openrouter|openrouter|OPENROUTER_API_KEY|env||80"
    "hermes|hermes chat||installed||60"
    "opencode|opencode||installed||55"
)

# --- Provider metadata lookup ---
# Fields: command, env_vars, check_type, check_url, priority
provider_meta() {
    local target="$1" field="$2"
    local def
    for def in "${_DEFAULT_PROVIDERS[@]}"; do
        IFS='|' read -r name cmd envs ctype curl prio <<< "$def"
        if [[ "$name" == "$target" ]]; then
            case "$field" in
                command)    echo "$cmd" ;;
                env_vars)   echo "$envs" ;;
                check_type) echo "$ctype" ;;
                check_url)  echo "$curl" ;;
                priority)   echo "$prio" ;;
            esac
            return 0
        fi
    done
    case "$field" in
        command)    echo "$target" ;;
        env_vars)   ;;
        check_type) echo "installed" ;;
        check_url)  ;;
        priority)   echo "50" ;;
    esac
}

# --- Config path resolution ---
_resolve_config_path() {
    local os
    os="$(uname -s 2>/dev/null || echo "Unknown")"
    case "$os" in
        MINGW*|MSYS*|CYGWIN*)
            echo "${USERPROFILE:-$HOME}/.multiplexor/config.yaml"
            ;;
        *)
            echo "${XDG_CONFIG_HOME:-$HOME/.config}/multiplexor/config.yaml"
            ;;
    esac
}

CONFIG_PATH="$(_resolve_config_path)"

# --- Runtime config variables ---
# CFG_ORDER, CFG_ENABLED_<NAME>, CFG_COMMAND_<NAME>, etc.

_load_defaults() {
    CFG_ORDER=""
    for def in "${_DEFAULT_PROVIDERS[@]}"; do
        IFS='|' read -r name cmd envs ctype curl prio <<< "$def"
        CFG_ORDER="$CFG_ORDER $name"
        local up
        up="$(echo "$name" | tr '[:lower:]' '[:upper:]')"
        eval "CFG_ENABLED_$up=true"
        eval "CFG_COMMAND_$up=\"\$cmd\""
        eval "CFG_PRIORITY_$up=\"\$prio\""
        eval "CFG_ENVS_$up=\"\$envs\""
        eval "CFG_CTYPE_$up=\"\$ctype\""
        eval "CFG_CURL_$up=\"\$curl\""
        eval "CFG_FALLBACK_$up=false"
        eval "CFG_CREDITS_$up=unknown"
    done
}

# --- YAML parser (python3) ---
_parse_yaml() {
    MPX_YAML_FILE="$1" python3 << 'PYEOF' 2>&1
import sys, os

try:
    yaml_file = os.environ.get("MPX_YAML_FILE", "")
    try:
        import yaml
        with open(yaml_file) as f:
            data = yaml.safe_load(f)
    except ImportError:
        data = {}
        current_section = None
        current_provider = None
        with open(yaml_file) as f:
            for line in f:
                stripped = line.rstrip()
                if not stripped or stripped.lstrip().startswith("#"):
                    continue
                indent = len(line) - len(line.lstrip())
                key_val = stripped.strip()
                if key_val.endswith(":"):
                    section = key_val[:-1].strip()
                    if indent == 0:
                        current_section = section
                        current_provider = None
                        data[section] = {}
                    elif indent == 2 and current_section:
                        current_provider = section
                        data[current_section][section] = {}
                elif ":" in key_val and current_section:
                    k, v = key_val.split(":", 1)
                    k = k.strip()
                    v = v.strip()
                    v = v.replace('"', '').replace("'", "")
                    if v.lower() == "true": v = True
                    elif v.lower() == "false": v = False
                    elif v.isdigit(): v = int(v)
                    if indent == 4 and current_provider:
                        if current_section not in data:
                            data[current_section] = {}
                        if current_provider not in data[current_section]:
                            data[current_section][current_provider] = {}
                        data[current_section][current_provider][k] = v

    providers = data.get("providers", {}) or {}
    routing = data.get("routing", {}) or {}

    for name in providers:
        p = providers[name] or {}
        enabled = str(p.get("enabled", True)).lower()
        command = p.get("command", name)
        priority = str(p.get("priority", 50))
        fallback = str(p.get("fallback_only", False)).lower()
        credits = str(p.get("credits_hint", "unknown")).lower()
        check_url = p.get("check_url", "")
        print("provider|" + name + "|enabled=" + enabled + "|command=" + str(command) + "|priority=" + priority + "|fallback=" + fallback + "|credits=" + credits + "|check_url=" + str(check_url))

    if routing:
        profile = routing.get("default_profile", "")
        print("routing|default_profile=" + str(profile))

except Exception as e:
    print("ERROR|" + str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
}

_load_yaml_config() {
    local yaml_file="$1"
    local output
    output=$(_parse_yaml "$yaml_file") || true

    if echo "$output" | grep -q "^ERROR|"; then
        _log_warn "Error al leer $yaml_file:"
        echo "$output" | sed 's/^ERROR|//' >&2
        _log_info "Usando valores por defecto."
        return
    fi

    local yaml_providers=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" == provider\|* ]]; then
            IFS='|' read -r _tag name rest <<< "$line"

            local enabled=true command="" priority="" fallback="" credits="" check_url=""
            IFS='|' read -ra PARTS <<< "$rest"
            for part in "${PARTS[@]}"; do
                local k="${part%%=*}"
                local v="${part#*=}"
                case "$k" in
                    enabled)    enabled="$v" ;;
                    command)    command="$v" ;;
                    priority)   priority="$v" ;;
                    fallback)   fallback="$v" ;;
                    credits)    credits="$v" ;;
                    check_url)  check_url="$v" ;;
                esac
            done

            local up
            up="$(echo "$name" | tr '[:lower:]' '[:upper:]')"

            eval "local was_enabled=\${CFG_ENABLED_$up:-}"
            if [[ -z "$was_enabled" ]]; then
                CFG_ORDER="$CFG_ORDER $name"
            fi

            eval "CFG_ENABLED_$up=\"$enabled\""
            [[ -n "$command" ]] && eval "CFG_COMMAND_$up=\"$command\""
            [[ -n "$priority" ]] && eval "CFG_PRIORITY_$up=\"$priority\""
            [[ -n "$fallback" ]] && eval "CFG_FALLBACK_$up=\"$fallback\""
            [[ -n "$credits" ]] && eval "CFG_CREDITS_$up=\"$credits\""
            [[ -n "$check_url" ]] && eval "CFG_CURL_$up=\"$check_url\""

            yaml_providers="$yaml_providers $name"
        fi
    done <<< "$output"

    # Add providers from defaults that were NOT in the YAML
    for def in "${_DEFAULT_PROVIDERS[@]}"; do
        IFS='|' read -r name _cmd _envs _ctype _curl _prio <<< "$def"
        local found=false
        for yp in $yaml_providers; do
            [[ "$yp" == "$name" ]] && found=true && break
        done
        if [[ "$found" == false ]]; then
            local up
            up="$(echo "$name" | tr '[:lower:]' '[:upper:]')"
            local was_var="CFG_ENABLED_${up}"
            local was="${!was_var:-}"
            if [[ -z "$was" ]]; then
                CFG_ORDER="$CFG_ORDER $name"
                eval "CFG_ENABLED_${up}=true"
                eval "CFG_CURL_${up}=\"${_curl}\""
            fi
        fi
    done
}

# --- Load config ---
_load_defaults

if [[ -f "$CONFIG_PATH" ]]; then
    _load_yaml_config "$CONFIG_PATH"
fi
