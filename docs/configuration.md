# Configuration

Create the user config:

```bash
multiplexor init
```

Paths:

- Linux/macOS: `~/.config/multiplexor/config.yaml`
- Windows: `%USERPROFILE%\.multiplexor\config.yaml`

The example config lives in `config.example.yaml`.

Provider fields:

- `enabled`: include or disable the provider.
- `tier`: `free`, `included`, `local` or `paid`.
- `priority`: base routing score.
- `command`: executable to detect in `PATH`.
- `interactive_command`: command for human/interactive launch.
- `ask_command`: command for `delegate`/`ask`.
- `ask_stdin`: send the task through stdin instead of argv.
- `fallback_only`: use only when no normal provider is eligible.
- `default_model`: required documentation/config signal for Ollama.

Scoring:

```text
score = priority + tier_bonus
```

Providers are excluded when disabled, not installed, temporarily exhausted, or missing the command needed for the selected mode.

State:

- Linux/macOS: `~/.config/multiplexor/state.json`
- Windows: `%USERPROFILE%\.multiplexor\state.json`

State stores only `last_provider` and temporary exhaustion marks. It does not store prompts or credentials.
