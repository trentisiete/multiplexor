# multiplexor

A Bash CLI that detects, scores, and launches the best available AI agent CLI on your machine.

If you use multiple AI CLIs (Claude, Codex, Gemini, OpenRouter, Ollama...), multiplexor picks the best one and opens it automatically.

## Why?

Different tasks work better with different models, but manually switching between CLIs is annoying. Multiplexor checks what you have installed, scores each provider by priority and availability, and launches the best one. If your top choice has no credits or auth, it falls back to the next best option.

## Install

### Recommended: pipx

```bash
pipx install .
```

pipx installs in an isolated virtual environment and adds the command to your PATH.

### Development: editable install

```bash
pip install -e .
```

Changes to the source files take effect immediately without reinstalling.

### Manual: direct script usage

If you don't want to use pip, you can run the script directly:

```bash
git clone https://github.com/your-org/multiplexor.git
cd multiplexor
./multiplexor doctor
```

**Requirements:** Bash 3.2+ (macOS default), python3 (for YAML parsing).

## Quick start

```bash
# 1. Create default config (optional)
multiplexor init

# 2. See what multiplexor detects
multiplexor doctor

# 3. Launch the best available AI CLI
multiplexor

# 4. Show what it would launch without executing
multiplexor --dry-run

# 5. Force a specific provider
multiplexor --provider ollama
```

## How it works

1. **Detect** — checks which AI CLIs are installed on your system
2. **Score** — calculates a score per provider:

   ```
   score = priority + credits_bonus
   ```

   | Credits hint | Bonus |
   |---|---|
   | `high` | +20 |
   | `medium` | +10 |
   | `low` | -10 |
   | `none` | ineligible (score 0) |
   | `unknown` | +0 |

3. **Select** — picks the highest score. Falls back to `fallback_only: true` providers only if nothing else is available.
4. **Launch** — opens the CLI in your terminal. If it fails, tries the next provider.

## Configuration

Works with no config. To customize, create `~/.config/multiplexor/config.yaml`:

```bash
multiplexor init
# then edit ~/.config/multiplexor/config.yaml
```

Or write it from scratch:

```yaml
providers:
  claude:
    enabled: true
    command: "claude"
    priority: 90
    credits_hint: high

  hermes:
    enabled: true
    command: "hermes chat"
    priority: 60

  ollama:
    enabled: true
    priority: 30
    fallback_only: true
    default_model: "llama3.2:3b"
```

| Field | Required | Description |
|---|---|---|
| `enabled` | no | Enable/disable provider (default: true) |
| `command` | no | Command to run (default: provider name) |
| `priority` | no | Base score (default: 50) |
| `fallback_only` | no | Only use if no other provider available (default: false) |
| `credits_hint` | no | `high`, `medium`, `low`, `none`, `unknown` |
| `default_model` | no | Default model for providers like ollama |
| `check_type` | no | `env`, `cli_status`, `ollama`, `http`, `installed` |
| `check_url` | no | URL for `http` check type |

## Providers

| Provider | Default priority | Check |
|---|---|---|
| claude | 90 | CLI status or ANTHROPIC_API_KEY |
| codex | 85 | OPENAI_API_KEY |
| openrouter | 80 | OPENROUTER_API_KEY |
| gemini | 75 | GOOGLE_API_KEY or GEMINI_API_KEY |
| hermes | 60 | Installed |
| opencode | 55 | Installed |
| ollama | 30 | `ollama list` responds + default_model set |

To add a custom provider, add it to `_DEFAULT_PROVIDERS` in `lib/config.sh` or configure it in YAML.

## Commands

| Command | Description |
|---|---|
| `multiplexor` | Detect and launch the best provider |
| `multiplexor init` | Create default config file |
| `multiplexor --dry-run` | Show what would launch without executing |
| `multiplexor --provider X` | Force provider X |
| `multiplexor -- "text"` | Pass arguments to the selected CLI |
| `multiplexor doctor` | Diagnose all providers |
| `multiplexor list` | Table of providers with scores |
| `multiplexor --explain` | Explain selection decision |
| `multiplexor --help` | Show help |
| `multiplexor --version` | Show version |

## Security

- This tool does **not** store API keys, passwords, or tokens.
- It does **not** send any data to external services.
- It relies on each CLI's existing authentication (env vars, CLI status).
- Your config.yaml contains no secrets — only provider names, priorities, and model names.
- Do not commit config.yaml if you add custom paths that expose sensitive information.

## Requirements

- Bash 3.2+ (macOS default)
- python3 3.9+ (for YAML parsing and package installation)
- Optional: PyYAML (`pip install pyyaml`) for faster YAML loading

## Testing

```bash
bash test_launch.sh
```

10 tests covering: default config loading, disabled providers, not-installed detection, score calculation with credits bonus, candidate ordering, fallback selection, and subcommand stability. No real providers, credentials, or network access required.

## Project structure

```
multiplexor/
  pyproject.toml              # Python package definition
  LICENSE                     # MIT license
  README.md                   # This file
  config.example.yaml         # Full config template
  test_launch.sh              # Test suite
  src/multiplexor/
    __init__.py               # Version constant
    __main__.py               # Python entry point (calls bash script)
    data/
      multiplexor             # Bash entry point script
      lib/
        utils.sh              # Helpers, colors, checks
        config.sh             # Defaults, YAML parser, config loading
        providers.sh          # Provider interface, scoring, selection
        launch.sh             # Terminal launch, fallback retry
        doctor.sh             # Diagnostics command
        list.sh               # Tabular view command
        explain.sh            # Selection explanation command
        help.sh               # Help and init commands
        README.md             # Module documentation
```

## Roadmap

These are planned but **not implemented yet**:

- Interactive provider selector (TUI)
- Automatic credit detection from CLI APIs
- Profile-based routing (`balanced`, `coding`, `cheap`)
- More providers
- MCP mode
