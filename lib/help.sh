# === multiplexor lib help ===
# Help subcommand: usage, config paths, and example.

cmd_help() {
    cat <<EOF
multiplexor — Elige y abre el mejor CLI de IA disponible.

Uso:
  multiplexor               Detecta y abre el mejor proveedor
  multiplexor --dry-run     Muestra qué lanzaría sin ejecutar
  multiplexor --provider X  Fuerza el proveedor X
  multiplexor --profile X   Usa el perfil X (balanceado por defecto)
  multiplexor -- "texto"    Pasa argumentos al CLI elegido
  multiplexor doctor        Diagnóstico de proveedores
  multiplexor list          Tabla de puntuaciones
  multiplexor --explain     Explica la decisión de selección
  multiplexor --version     Muestra versión
  multiplexor --help        Esta ayuda

Configuración:
  Crea un archivo YAML en:
    Linux/macOS: $CONFIG_PATH
    Windows:     %USERPROFILE%\\.multiplexor\\config.yaml

  Copia config.example.yaml como punto de partida.

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
