# lib/ — Multiplexor modules

Each file is a focused module. Sourced in order by `multiplexor` entry point.

| File | Purpose |
|---|---|
| `utils.sh` | Colors, platform detection, command existence, availability checks (env, CLI status, ollama, HTTP) |
| `config.sh` | Default providers table, YAML parser (python3), runtime config loading, `provider_meta()` lookup |
| `providers.sh` | Provider interface: `get_cmd`, `get_model`, `get_enabled`, `_detect`, `is_available`, `get_score`, `get_credits`, `get_priority`, `get_fallback`, `get_unavail_reason`, `_build_cmd`, `_build_candidates`, `_find_best` |
| `launch.sh` | Launch logic: `_try_launch` (cross-platform terminal), `cmd_run` (arg parsing, fallback retry, error summary) |
| `doctor.sh` | `cmd_doctor` — diagnostics: config status, provider health, model info |
| `list.sh` | `cmd_list` — tabular view with MODEL column |
| `explain.sh` | `cmd_explain` — explains selection decision with score breakdown |
| `help.sh` | `cmd_help` — usage, config paths, YAML example |

## Sourcing order (dependency chain)

```
utils.sh → config.sh → providers.sh → launch.sh → doctor.sh → list.sh → explain.sh → help.sh
```

- `utils.sh` — no deps (colors, platform, check helpers)
- `config.sh` — depends on `utils.sh` (`_log_warn`)
- `providers.sh` — depends on `utils.sh` + `config.sh`
- `launch.sh` — depends on `providers.sh`
- `doctor.sh`, `list.sh`, `explain.sh`, `help.sh` — depend on `providers.sh` + `utils.sh` + `config.sh`

## Check types

| Type | Behavior |
|---|---|
| `env` | Requires at least one env var from `env_vars` field |
| `cli_status` | Runs `<cmd> status`, checks for "authenticated/ready/credits" (3s timeout) |
| `ollama` | Runs `ollama list` to verify server responds (3s timeout) |
| `http` | Curl to `check_url` endpoint |
| `installed` | Only checks binary exists |

## Adding a new provider

1. Add a line to `_DEFAULT_PROVIDERS` in `config.sh`:
   ```
   "name|command|env_vars|check_type|check_url|priority"
   ```
2. Optionally configure in YAML:
   ```yaml
   providers:
     name:
       enabled: true
       priority: 75
       credits_hint: high
       default_model: "model-name"  # for ollama-like providers
   ```

## Ollama configuration

```yaml
providers:
  ollama:
    enabled: true
    command: "ollama"
    priority: 30
    fallback_only: true
    default_model: "llama3.2:3b"
```

- `default_model` is required — without it, ollama gets score 0
- Launch command: `ollama run <default_model>`
- Detection: checks `ollama` binary exists + `ollama list` responds

## Hard caps

Each file stays under 400 LOC (soft) / 700 LOC (hard).
