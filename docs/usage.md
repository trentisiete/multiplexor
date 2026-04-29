# Usage

`multiplexor` is meant to be called by a primary agent from a shell.

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
multiplexor status
multiplexor delegate --dry-run "task"
multiplexor delegate --provider gemini "task"
multiplexor delegate --provider opencode "task"
multiplexor next
multiplexor reset
```

Default behavior:

1. Use Gemini CLI if available.
2. Use OpenCode if Gemini is unavailable or marked exhausted.
3. Use Ollama only as local fallback.

`next` marks the last provider as temporarily exhausted and launches the next eligible provider.
