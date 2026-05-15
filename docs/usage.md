# Usage

`multiplexor` is meant to be called by a primary agent from a shell.

(Install with `pipx install endy-multiplexor` — the PyPI distribution
name. The CLI itself is still `multiplexor`.)

Main command:

```bash
multiplexor delegate "review this repository and list concrete issues"
```

`ask` is kept as an alias:

```bash
multiplexor ask "summarize the current project"
```

You can also pipe a task through stdin:

```bash
printf "inspect the tests and report gaps" | multiplexor delegate
```

Useful commands:

```bash
multiplexor doctor
multiplexor status [NAME ...] [--json]   # ranked status; --json for endy state
multiplexor delegate --dry-run "task"
multiplexor delegate --provider gemini "task"
multiplexor delegate --provider opencode "task"
multiplexor next
multiplexor next-provider [PREV]    # pure query, prints next agent name
multiplexor reset
```

Default behavior:

1. Use Gemini CLI if available.
2. Use OpenCode if Gemini is unavailable or marked exhausted.
3. Use Ollama only as local fallback.

`next` marks the last provider as temporarily exhausted and launches the next eligible provider.

## next-provider (the endy resolver)

`multiplexor next-provider` is the pure-query sibling of `next`. It does
not launch anything — it just prints the name of the next eligible
provider to stdout and exits.

```bash
$ multiplexor next-provider
gemini

$ multiplexor next-provider gemini
opencode

$ multiplexor next-provider --verbose
gemini
# score=130 tier=free mode=interactive
# alternatives: opencode(115), ollama(15)
```

Argument shape matches endy's `ENDY_HANDOFF_RESOLVER` contract:

```
multiplexor-next-provider <prev-agent> [<task-id>] [<cwd>]
```

`task-id` and `cwd` are accepted and silently ignored — they exist so
the command can be a drop-in for endy's resolver hook. The companion
binary `multiplexor-next-provider` is a thin wrapper installed by the
package; use it as the resolver value because endy's hook executes the
variable as a single binary name (no shell word-splitting):

```bash
export ENDY_HANDOFF_RESOLVER=multiplexor-next-provider
```

### Options

- `--no-mark` — pure query, leave state untouched.
- `--mode interactive|ask` — filter by which command template the
  provider must have (default `interactive`).
- `--verbose` — emit score, tier, mode, and a short alternatives list
  to stderr. Stdout still carries just the chosen name.
- `--for endy` — exclude providers endy cannot drive headlessly
  (currently just `ollama`).

### Exit codes

- `0` — chosen provider name printed to stdout.
- `1` — no eligible provider; stdout empty; stderr explains.
- `2` — bad arguments (unknown `--mode`, unknown `--for` target).

### Behavior when prev is unknown

If `<prev-agent>` is not a multiplexor provider (for example endy's
`bash` stub), the command silently skips the exhaustion mark and still
returns the best eligible alternative.

## status (with JSON for `endy state`)

`multiplexor status` is the read-only inspection counterpart. With
`--json` it emits a machine-parseable shape — the contract `endy state`
consumes when it shows tier headroom inside a spawned agent's
environment block.

```bash
multiplexor status                       # human, every provider
multiplexor status gemini                # human, one provider
multiplexor status --json                # JSON, every provider
multiplexor status --json gemini         # JSON, single bare object
multiplexor status --json gemini codex   # JSON, envelope with both
```

### JSON shape

When you pass exactly one provider name, you get a bare object:

```json
{
  "name": "gemini",
  "tier": "free",
  "priority": 100,
  "score": 130,
  "enabled": true,
  "installed": true,
  "exhausted": false,
  "exhausted_until": null,
  "exhausted_seconds_remaining": null,
  "fallback_only": false,
  "eligible": true,
  "reason": ""
}
```

When you pass no name or multiple names, you get an envelope so the
caller always knows which provider multiplexor would route to right now:

```json
{
  "providers": [ { ...gemini... }, { ...opencode... } ],
  "selected": "gemini"
}
```

When a provider is exhausted, the relevant fields are populated:

```json
{
  "name": "gemini",
  ...
  "exhausted": true,
  "exhausted_until": "2026-05-16T14:49:56",
  "exhausted_seconds_remaining": 7421,
  "eligible": false,
  "reason": "temporarily exhausted"
}
```

`exhausted_seconds_remaining` is computed at call time (clamped at 0)
so consumers don't have to parse the timestamp themselves to render
"resets in 2h 03m".

### Exit codes

- `0` — successful query.
- `1` — one or more requested names are not in the config. stderr lists
  the unknown names; stdout stays empty.

### Why this shape

`endy state` builds an "environment" block prepended to every spawned
task's prompt. It needs to tell the agent: who am I, what's the handoff
chain, and what tier headroom remains for each provider. Multiplexor is
the source of truth for the third part. The JSON contract above is
designed to be parsed in one `jq` call without further computation:

```bash
multiplexor status --json gemini \
  | jq -r '"gemini: " + (if .eligible then "ready" else .reason end)'
# → gemini: ready
# or
# → gemini: temporarily exhausted (resets in 2h 03m)
```
