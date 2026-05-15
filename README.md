# multiplexor

> **The routing policy for free-tier AI CLIs.** Pairs with [endy][endy] when
> you also need a runtime, tmux orchestration, and cross-agent handoff.

You have a primary agent doing the heavy work. You also have Gemini CLI, OpenCode, and maybe a local Ollama model sitting idle. `multiplexor` connects them. It lets your main agent delegate tasks to any installed AI CLI -- automatically picking the best one, falling back when quotas run dry, and keeping everything local.

No proxies. No daemon. No MCP layer. Just a small Python command that knows which CLIs you have installed, scores them, picks one, runs it, and moves on.

[endy]: https://github.com/trentisiete/endy

---

## The problem this solves

Free-tier AI CLIs are powerful but limited. Gemini CLI gives you access to Gemini models at no cost. OpenCode includes its own quota. But once one provider gets exhausted, you are stuck waiting or switching manually.

`multiplexor` fixes the switching part. It treats your installed CLIs as a pool of subagents and routes work through them in order of priority and availability. When one runs dry, you mark it exhausted with `multiplexor next` and it immediately tries the next best option. When all free providers are gone, Ollama runs locally as a last resort.

This is not about bypassing limits. It is about making sure you never sit idle when another provider is available and ready.

---

## How it works

1. You install `multiplexor` and run `multiplexor init` to create your config.
2. The config declares which CLIs you have, their tier (`free`, `included`, `local`, `paid`), and a priority score.
3. When your primary agent calls `multiplexor delegate "task"`, the router computes `score = priority + tier_bonus`, filters out exhausted or missing providers, and picks the highest-ranked one.
4. The task runs headless. Output is captured. If it fails or times out, the next provider tries automatically.
5. When a provider hits its limit, `multiplexor next` marks it temporarily exhausted (24h cooldown by default) and launches the next eligible provider.

```
primary agent
     |
     v
multiplexor delegate "review this PR"
     |
     v
  router scores providers:
     gemini    score 130  (priority 100 + free bonus 30)  <-- picked
     opencode  score 115  (priority 90  + included bonus 25)
     ollama    score  15  (priority 10  + local bonus 5)   (fallback only)
```

---

## Pairing with endy

`multiplexor` decides *which* CLI should pick up next. [endy][endy] is the
runtime that runs each CLI in a detached tmux window, captures its output to
`.logs/`, and provides `endy handoff` — a one-command transfer of an
in-flight coding task from one agent to another with full context.

Wire them together by setting endy's resolver hook to the dedicated
binary multiplexor installs for this purpose:

```bash
export ENDY_HANDOFF_RESOLVER=multiplexor-next-provider
endy handoff <task-id>                  # --to becomes optional
```

When you call `endy handoff` without `--to`, endy invokes
`multiplexor-next-provider <prev-agent> <task-id> <cwd>` and uses the
agent name it prints to stdout. Under the hood that wrapper just calls
`multiplexor next-provider`, which:

1. Marks `<prev-agent>` as exhausted (so it does not get re-selected).
2. Computes the highest-scored eligible provider with the regular
   `priority + tier_bonus` rules (same logic as `multiplexor status`).
3. Prints the chosen name to stdout. Exits non-zero (silently, stderr
   only) when nothing is eligible, so endy falls back to requiring an
   explicit `--to`.

A standalone test, no endy required:

```console
$ multiplexor-next-provider gemini task-123 /tmp/proj
opencode
$ multiplexor status | head -5
1. opencode
   tier: included
   ...
```

`endy state` (the per-spawn environment snapshot) reads multiplexor's
view of the world via `multiplexor status --json [agent]`, which returns
a machine-parseable shape including `exhausted_seconds_remaining` for
each provider — see [docs/usage.md](docs/usage.md#status-with-json-for-endy-state).

Useful flags on `multiplexor next-provider` (or its `-next-provider`
shim) for tuning the integration:

| Flag | What it does |
|---|---|
| `--no-mark` | Pure query, do not touch state (good for dry-runs / health checks). |
| `--mode interactive|ask` | Filter by which command template the provider must have. Default `interactive`. |
| `--verbose` | Emit score + tier + alternatives to stderr (stdout stays a single name, safe for the resolver). |
| `--for endy` | Skip providers endy cannot drive headlessly (e.g. `ollama`). |

You can also use either tool alone:

- **multiplexor without endy** — `multiplexor delegate "task"` runs a single
  task on the best-scored CLI. No tmux, no logs directory, no handoff chain.
- **endy without multiplexor** — `endy handoff <id> --to <agent>` is a
  one-shot manual handoff. You pick the next agent yourself.

Together you get continuity: when one tier runs out, the routing policy
decides who is next and the runtime carries the task across without you
re-typing the prompt.

---

## Install

```bash
pip install -e .
```

Requires Python 3.11+ and at least one supported CLI in your `PATH`.

---

## Quickstart

```bash
multiplexor init          # create user config
multiplexor doctor        # verify everything is detected
multiplexor status        # see current ranking
multiplexor delegate "review this repository and list concrete risks"
```

When the current provider gets exhausted:

```bash
multiplexor next          # mark last provider exhausted, launch next
```

Other commands you will use:

```bash
multiplexor                    # launch best interactive provider
multiplexor reset              # clear all exhaustion marks
multiplexor next               # skip to next provider
multiplexor delegate "task"    # headless subagent run
multiplexor ask "prompt"       # alias for delegate
multiplexor --dry-run          # show what would run
multiplexor --provider gemini  # force a specific provider
```

Piping works too:

```bash
git diff | multiplexor delegate "review these changes"
```

---

## Providers

The default config ships with these providers:

| Provider   | Tier     | Priority | Default State | Notes                          |
|------------|----------|----------|---------------|--------------------------------|
| Gemini CLI | free     | 100      | enabled       | Main subagent, headless capable |
| OpenCode   | included | 90       | enabled       | Good secondary option           |
| Ollama     | local    | 10       | enabled       | Fallback only, runs locally     |
| Qwen       | paid     | 95       | disabled      | Optional                        |
| Hermes     | paid     | 80       | disabled      | Optional                        |
| Codex      | paid     | 40       | disabled      | Optional                        |
| Claude     | paid     | 30       | disabled      | Optional                        |

Paid providers are disabled by default because the v1 focus is free-tier delegation. Enable them in your config if you want them in the routing pool.

Scoring formula:

```
score = priority + tier_bonus
```

Tier bonuses: `free=30`, `included=25`, `local=5`, `paid=0`. Gemini CLI with its base priority of 100 and free bonus of 30 scores 130, always winning unless exhausted.

---

## Configuration

Run `multiplexor init` to create your config at:

- Linux/macOS: `~/.config/multiplexor/config.yaml`
- Windows: `%USERPROFILE%\.multiplexor\config.yaml`

A provider entry needs only a few fields:

```yaml
providers:
  gemini:
    enabled: true
    tier: free
    priority: 100
    command: "gemini"
    interactive_command: ["gemini", "--skip-trust", "--approval-mode=yolo"]
    ask_command: ["gemini", "--skip-trust", "--approval-mode=yolo", "-p", ""]
    ask_stdin: true
```

The `Provider` class handles everything else: detection from `PATH`, command construction, scoring, and prompt substitution. Adding a new provider means adding a config block. No code changes required.

Key fields:
- `enabled`: include or skip this provider
- `tier`: determines the bonus added to priority
- `priority`: base ranking score
- `command`: executable name for PATH detection
- `interactive_command` / `ask_command`: command templates for each mode
- `ask_stdin`: send task through stdin instead of argv
- `fallback_only`: only use when no normal provider is eligible
- `default_model`: required for Ollama

---

## State and exhaustion

State is stored locally as `state.json` next to your config. It tracks only two things:

- The last provider that ran
- Temporary exhaustion marks (with an expiration timestamp)

It does not store credentials, API keys, prompts, or anything sensitive. The exhaustion cooldown defaults to 24 hours and is configurable.

```bash
multiplexor next    # marks last_provider as exhausted
multiplexor reset   # clears all exhaustion marks
```

---

## Security model

`multiplexor` runs commands with `shell=False`. No shell injection surface. Prompts go through stdin by default so they never appear in process arguments visible to `ps`.

The default delegate commands use each CLI's official allow-all permission mode:

- Gemini: `--skip-trust --approval-mode=yolo`
- OpenCode: `--dangerously-skip-permissions`

This is intentional. A delegated CLI can edit files and run commands. Only use this in repositories where you are comfortable with that behavior. First-time authentication and setup still belong to each CLI. `multiplexor` does not store or inject any credentials.

It does not:
- bypass rate limits or quotas
- scrape provider credit balances
- modify any provider's internal configuration
- run a proxy, daemon, web server, or MCP server

---

## Limitations

v1 operates on what it can detect: installed commands and explicit exhaustion state. It cannot read your exact Gemini quota or predict when a provider will fail. If a CLI hangs waiting for interactive setup, the configured timeout (default 120s) kills it and tries the next provider.

Provider-specific setup hints and per-provider timeout overrides are planned.

---

## Testing

```bash
python3 -m unittest discover -s tests
```

Tests use mocked commands. No real CLIs or credentials needed.

---

## Roadmap

- Clearer per-provider setup hints when a CLI fails to run
- Optional per-provider timeout overrides in config
- Examples for adding custom local providers

---

## Docs

- [Usage](docs/usage.md) - command examples and patterns
- [Configuration](docs/configuration.md) - provider config, scoring, and state
- [Security](docs/security.md) - threat model and operational notes

## Related

- [endy](https://github.com/trentisiete/endy) - the runtime. tmux + `.logs/`
  + cross-agent `handoff` command. Use multiplexor as its routing policy.
