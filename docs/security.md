# Security

`multiplexor` is intentionally local and small.

It does not:

- store API keys, tokens, cookies or passwords,
- scrape or bypass quota systems,
- modify Gemini/OpenCode/Ollama internal config,
- run a proxy, daemon, web server or MCP server,
- use `shell=True`.

The default Gemini/OpenCode delegate commands use official allow-all permission flags:

- Gemini: `--skip-trust --approval-mode=yolo`
- OpenCode: `--dangerously-skip-permissions`

That is deliberate for subagent delegation. It means delegated CLIs may edit files and run commands according to their own permission model. Use this only in repositories where that is acceptable.

Prompts for Gemini and OpenCode are sent through stdin by default via `ask_stdin: true`, so task text is not exposed as a process argument.

First-time login, trust setup and provider authentication still belong to each CLI.
