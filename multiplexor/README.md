# multiplexor package

`cli.py` parses commands and connects the modules. `delegate` and `ask` are aliases for subagent calls.
`config.py` loads YAML config and creates the user config.
`state.py` reads and writes local provider exhaustion state.
`providers.py` defines the `Provider` class. New providers are just config entries unless they need truly special behavior; the class handles detection, mode commands, prompt expansion and scoring.
`router.py` scores, filters and selects providers.
`runner.py` executes commands with `subprocess` and `shell=False`.
