# multiplexor

Detecta, puntúa y abre el mejor CLI de IA disponible en tu terminal.

## Instalación

```bash
chmod +x multiplexor
sudo cp multiplexor /usr/local/bin/multiplexor
```

## Uso

```bash
multiplexor           # Abre el mejor CLI disponible
multiplexor doctor    # Diagnóstico de proveedores
multiplexor list      # Tabla de puntuaciones
multiplexor --help    # Ayuda
```

## Configuración

Por defecto funciona sin configuración. Para personalizar, crea un archivo YAML en:

- **Linux/macOS:** `~/.config/multiplexor/config.yaml`
- **Windows:** `%USERPROFILE%\.multiplexor\config.yaml`

```bash
cp config.example.yaml ~/.config/multiplexor/config.yaml
```

### Ejemplo de configuración

```yaml
providers:
  claude:
    enabled: true
    command: "claude"
    priority: 95

  gemini:
    enabled: false        # Se ignora completamente

  ollama:
    enabled: true
    command: "ollama run llama3"
    priority: 70

routing:
  default_profile: "balanced"

profiles:
  balanced:
    prefer_available: true
```

## Proveedores por defecto

| Proveedor   | Prioridad | Check             |
|-------------|-----------|-------------------|
| claude      | 90        | ANTHROPIC_API_KEY o `claude status` |
| codex       | 85        | OPENAI_API_KEY    |
| openrouter  | 80        | OPENROUTER_API_KEY|
| gemini      | 75        | GOOGLE_API_KEY o GEMINI_API_KEY |
| ollama      | 70        | HTTP localhost:11434 |
| hermes      | 60        | Instalado         |
| opencode    | 55        | Instalado         |

## Puntuación

- **+10** si está instalado
- **+20** si está disponible (auth/API key/server)
- **+N** prioridad base (configurable)

Gana el proveedor con mayor puntuación.

## Requisitos

- Bash 3.2+
- python3 (para leer YAML)
- Opcional: PyYAML (`pip install pyyaml`)
