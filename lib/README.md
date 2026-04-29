# lib/ — Multiplexor modules

Each file is a focused module. Sourced in order by `multiplexor` entry point.

| File | LOC | Purpose |
|---|---|---|
| `utils.sh` | ~60 | Colors, platform detection, command existence, availability checks (env, CLI status, HTTP) |
| `config.sh` | ~150 | Default providers table, YAML parser (python3), runtime config loading, `provider_meta()` lookup |
| `providers.sh` | ~140 | Provider interface: `get_cmd`, `get_enabled`, `_detect`, `is_available`, `get_score`, `get_credits`, `get_priority`, `get_fallback`, `get_unavail_reason`, `_build_candidates`, `_find_best` |
| `launch.sh` | ~120 | Launch logic: `_try_launch` (cross-platform terminal), `cmd_run` (arg parsing, fallback retry, error summary) |
| `doctor.sh` | ~70 | `cmd_doctor` — diagnostics: config status, provider health, recommended provider |
| `list.sh` | ~20 | `cmd_list` — tabular view of all providers with scores |
| `explain.sh` | ~80 | `cmd_explain` — explains selection decision with score breakdown |
| `help.sh` | ~30 | `cmd_help` — usage, config paths, YAML example |

## Sourcing order (dependency chain)

```
utils.sh → config.sh → providers.sh → launch.sh → doctor.sh → list.sh → explain.sh → help.sh
```

- `utils.sh` — no deps (colors, platform, check helpers)
- `config.sh` — depends on `utils.sh` (`_log_warn`)
- `providers.sh` — depends on `utils.sh` (`_cmd_exists`, `_check_env_vars`, etc.) + `config.sh` (`_DEFAULT_PROVIDERS`, `CFG_*`)
- `launch.sh` — depends on `providers.sh` (`get_cmd`, `get_enabled`, etc.)
- `doctor.sh`, `list.sh`, `explain.sh`, `help.sh` — depend on `providers.sh` + `utils.sh` + `config.sh`

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
   ```
No other code changes needed.

## Hard caps

Each file stays under 400 LOC (soft) / 700 LOC (hard). Current max is ~150 LOC.
