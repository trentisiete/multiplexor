# tests

These tests cover config loading, scoring, provider selection, local state, delegate/ask dry-run behavior and command execution safety.

Run them with:

```bash
python3 -m unittest discover -s tests
```

The tests use fake commands and mocks. They do not require Gemini, OpenCode, Hermes, Ollama or credentials.
