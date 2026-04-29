# === multiplexor lib help ===
# Help and init subcommands.

cmd_help() {
    cat <<EOF
multiplexor — Elige y abre el mejor CLI de IA disponible.

Uso:
  multiplexor               Detecta y abre el mejor proveedor
  multiplexor init          Crea la configuración por defecto
  multiplexor doctor        Diagnóstico de proveedores
  multiplexor list          Tabla de puntuaciones
  multiplexor --dry-run     Muestra qué lanzaría sin ejecutar
  multiplexor --provider X  Fuerza el proveedor X
  multiplexor --profile X   Usa el perfil X (balanceado por defecto)
  multiplexor -- "texto"    Pasa argumentos al CLI elegido
  multiplexor --explain     Explica la decisión de selección
  multiplexor --version     Muestra versión
  multiplexor --help        Esta ayuda

Configuración:
  multiplexor init          Crea ~/.config/multiplexor/config.yaml
  o edita el archivo manualmente:
    Linux/macOS: $CONFIG_PATH
    Windows:     %USERPROFILE%\\.multiplexor\\config.yaml

Ejemplo:
  providers:
    claude:
      enabled: true
      command: "claude"
      priority: 90
    gemini:
      enabled: false
EOF
}

cmd_init() {
    local config_dir
    config_dir="$(dirname "$CONFIG_PATH")"

    if [[ -f "$CONFIG_PATH" ]]; then
        echo "Config already exists at: $CONFIG_PATH"
        echo "Edit it directly or delete it first."
        return
    fi

    mkdir -p "$config_dir"

    # Find the example config (search relative to script and installed locations)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local example=""
    for candidate in \
        "$script_dir/../config.example.yaml" \
        "$script_dir/config.example.yaml" \
        "$script_dir/../../config.example.yaml" \
        "$script_dir/../data/config.example.yaml" \
        "$script_dir/data/config.example.yaml"; do
        [[ -f "$candidate" ]] && example="$candidate" && break
    done

    if [[ -z "$example" ]]; then
        echo "Error: config.example.yaml not found." >&2
        echo "Create $CONFIG_PATH manually." >&2
        return 1
    fi

    cp "$example" "$CONFIG_PATH"
    echo "Created: $CONFIG_PATH"
    echo "Edit it to customize providers."
}
