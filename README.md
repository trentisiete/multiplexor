# multiplexor

`multiplexor` is a small local command for a primary agent such as Codex or Claude to delegate work to other AI CLIs as subagents. It detects installed commands, ranks providers, runs non-interactive delegation commands, captures output, and lets you mark the last provider as temporarily exhausted with `multiplexor next`.

The v1 focus is Gemini CLI and OpenCode as the main subagent targets because their CLIs work well in headless mode. Ollama is only a local fallback. Qwen Code, Hermes, Claude and Codex are present only as optional disabled providers, because they are not the free-tier focus for this tool.

## Install

```bash
pip install -e .
```

Requirements:

- Python 3.11+
- At least one supported CLI in `PATH`
- Recommended for v1: Gemini CLI and OpenCode

## Quickstart

```bash
multiplexor init
multiplexor doctor
multiplexor status
multiplexor --dry-run
multiplexor delegate "review this repo and list risks"
multiplexor ask --dry-run "hola"
multiplexor ask "hola"
multiplexor next
multiplexor reset
```

Force a provider:

```bash
multiplexor --provider gemini --dry-run
multiplexor ask --provider opencode --dry-run "hola"
```

For primary agents, the main command is:

```bash
multiplexor delegate "analyze this repository and return concrete risks"
```

## Providers

Default priority:

1. Gemini CLI
2. OpenCode
3. Ollama as local fallback

Optional disabled providers:

- Qwen Code
- Hermes
- Claude
- Codex

Verified locally during v1 development with:

- Gemini CLI `0.40.0`
- OpenCode `1.14.29`

## Config

User config is created at:

- Linux/macOS: `~/.config/multiplexor/config.yaml`
- Windows: `%USERPROFILE%\.multiplexor\config.yaml`

See `config.example.yaml`. Commands are lists of arguments, not shell strings. If `ask_stdin: true`, the task is sent through stdin. Otherwise only the literal `{prompt}` placeholder is replaced in `ask_command`.

Adding a provider should usually mean adding one config entry with `command`, `interactive_command`, `ask_command`, `tier` and `priority`. The `Provider` class handles the shared behavior: detection, mode support, scoring and safe prompt substitution.

For subagent use, `delegate` and `ask` are the important commands. They are aliases:

```bash
multiplexor delegate "inspect the current project and summarize the tests"
echo "inspect the current project" | multiplexor delegate
```

Scoring is:

```text
score = priority + tier_bonus
```

Fallback-only providers such as Ollama are used only when no normal provider is eligible. Ollama must specify a model in its commands and `default_model`.

## State

Local state lives next to the config as `state.json`. It stores only:

- `last_provider`
- temporary `exhausted_until` marks

It does not store API keys, tokens, cookies, credentials or prompts.

## What It Does Not Do

- It does not bypass free-tier limits.
- It does not scrape exact credits.
- It does not modify provider configs.
- It does not run a proxy, daemon, server, MCP layer or dashboard.
- It does not use `shell=True`.

The default Gemini/OpenCode delegate commands use each CLI's official "allow everything" mode so a primary agent can delegate without approval loops: Gemini uses `--approval-mode=yolo`, and OpenCode uses `--dangerously-skip-permissions`. Prompts are sent via stdin by default so they do not appear in process arguments. This is intentionally powerful and should only be used in repos where you are comfortable letting the delegated CLI edit files and run commands. First-time auth/setup still belongs to each CLI. `multiplexor` does not store credentials or inject secrets.

More detail:

- [Usage](docs/usage.md)
- [Configuration](docs/configuration.md)
- [Security](docs/security.md)

## Commands

- `multiplexor init`: create user config if missing.
- `multiplexor doctor`: inspect config, state and provider detection.
- `multiplexor status`: show ranking and eligibility.
- `multiplexor`: launch the best interactive provider.
- `multiplexor delegate "TASK"`: run the best headless provider as a subagent with fallback.
- `multiplexor ask "PROMPT"`: alias for `delegate`.
- `multiplexor next`: mark the last provider exhausted and launch the next.
- `multiplexor reset`: clear exhausted marks.
- `--dry-run`: show the command without executing it.
- `--provider NAME`: force one provider.

## Testing

```bash
python3 -m unittest discover -s tests
```

Tests use fake commands and mocks. No real CLIs or credentials are required.

## Limitations

This v1 only detects installed commands and explicit temporary exhaustion state. It cannot know exact provider quota. If a CLI blocks waiting for setup in `ask` mode, the configured timeout stops the run and tries the next provider.

## Minimal Roadmap

- Add clearer provider-specific setup hints.
- Add optional per-provider timeout overrides.
- Add small examples for custom local providers.
