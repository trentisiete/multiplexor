from __future__ import annotations

import copy
import platform
import sys

from . import __version__
from .config import init_config, load_config
from .providers import providers_from_config
from .router import candidates, ranked_statuses, select_provider
from .runner import run_ask, run_interactive
from .state import load_state, mark_exhausted, reset_exhausted, state_path


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    opts, args = _extract_options(argv)
    command = args[0] if args else "run"
    rest = args[1:]
    if command in {"--help", "-h", "help"}:
        return _help()
    if command in {"--version", "-v"}:
        print(f"multiplexor {__version__}")
        return 0
    if command == "init":
        return _init()
    if command == "doctor":
        return _doctor()
    if command == "status":
        return _status()
    if command in {"ask", "delegate"}:
        return _ask(rest, opts)
    if command == "next":
        return _next(opts)
    if command == "reset":
        return _reset()
    if command != "run":
        print(f"Unknown command: {command}", file=sys.stderr)
        return 2
    return _run(opts)


def _extract_options(argv: list[str]) -> tuple[dict, list[str]]:
    opts = {"dry_run": False, "provider": None}
    args: list[str] = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--dry-run":
            opts["dry_run"] = True
            i += 1
        elif arg in {"--provider", "-p"}:
            if i + 1 >= len(argv):
                raise SystemExit("--provider requires a provider name")
            opts["provider"] = argv[i + 1]
            i += 2
        else:
            args.append(arg)
            i += 1
    return opts, args


def _init() -> int:
    path, created = init_config()
    print(f"Created config: {path}" if created else f"Config already exists: {path}")
    return 0


def _doctor() -> int:
    config, cfg_path, cfg_exists = load_config()
    data, st_path = load_state()
    print(f"multiplexor {__version__} doctor")
    print(f"OS: {platform.platform()}")
    print(f"Config: {cfg_path} ({'found' if cfg_exists else 'missing; defaults in use'})")
    print(f"State: {st_path} ({'found' if st_path.exists() else 'missing'})")
    print("\nProviders:")
    for provider in providers_from_config(config):
        row = ranked_statuses(config, data, "interactive", check_installed=True)
        info = next(r for r in row if r["name"] == provider.name)
        print(f"- {provider.name}: enabled={provider.enabled} command={provider.command}")
        print(f"  installed={_yes(info['installed'])} exhausted={_yes(info['exhausted'])} delegate_command={_yes(info['has_ask'])}")
        if info["reason"]:
            print(f"  reason={info['reason']}")
    selected = select_provider(config, data, "interactive")
    print(f"\nSelected: {selected.name if selected else 'none'}")
    print(
        "Note: multiplexor runs the configured provider command exactly as listed. "
        "The default Gemini/OpenCode delegate commands use official allow-all permission flags; first-time auth or setup still belongs to each CLI."
    )
    return 0


def _status() -> int:
    config, _, _ = load_config()
    data, _ = load_state()
    for index, row in enumerate(ranked_statuses(config, data), start=1):
        score = "-" if row["score"] is None else row["score"]
        print(f"{index}. {row['name']}")
        print(f"   tier: {row['tier']}")
        print(f"   installed: {_yes(row['installed'])}")
        print(f"   exhausted: {_yes(row['exhausted'])}")
        if row["fallback_only"]:
            print("   fallback_only: yes")
        print(f"   score: {score}")
        print(f"   eligible: {_yes(row['eligible'])}")
        if row["reason"]:
            print(f"   reason: {row['reason']}")
        print("")
    return 0


def _run(opts: dict) -> int:
    config, _, _ = load_config()
    data, st_path = load_state()
    provider = select_provider(
        config, data, "interactive", opts["provider"], check_installed=not opts["dry_run"]
    )
    if not provider:
        print("No available providers found. Run `multiplexor doctor` to inspect your setup.", file=sys.stderr)
        return 1
    return run_interactive(provider, data, st_path, opts["dry_run"])


def _ask(rest: list[str], opts: dict) -> int:
    prompt = " ".join(rest).strip()
    if not prompt and not sys.stdin.isatty():
        prompt = sys.stdin.read().strip()
    if not prompt:
        print('Usage: multiplexor delegate "TASK"', file=sys.stderr)
        return 2
    config, _, _ = load_config()
    data, st_path = load_state()
    timeout = int(config.get("routing", {}).get("ask_timeout_seconds", 120))
    items = candidates(config, data, "ask", opts["provider"], check_installed=not opts["dry_run"])
    if not items:
        print("No available providers found. Run `multiplexor doctor` to inspect your setup.", file=sys.stderr)
        return 1
    return run_ask(items, prompt, data, st_path, timeout, opts["dry_run"])


def _next(opts: dict) -> int:
    config, _, _ = load_config()
    data, st_path = load_state()
    last = data.get("last_provider")
    if not last:
        print("No last provider found. Launch `multiplexor` first or use `--provider NAME`.", file=sys.stderr)
        return 1
    hours = int(config.get("routing", {}).get("exhausted_cooldown_hours", 24))
    if opts["dry_run"]:
        data = copy.deepcopy(data)
        data.setdefault("providers", {}).setdefault(last, {})
        data["providers"][last]["status"] = "exhausted"
        data["providers"][last]["exhausted_until"] = "9999-12-31T00:00:00"
        print(f"Would mark {last} as exhausted for {hours} hours.")
    else:
        data = mark_exhausted(last, hours, st_path)
        print(f"Marked {last} as exhausted for {hours} hours.")
    provider = select_provider(config, data, "interactive", check_installed=not opts["dry_run"])
    if not provider:
        print("No available providers found. Run `multiplexor reset` to clear exhausted providers.", file=sys.stderr)
        return 1
    return run_interactive(provider, data, st_path, opts["dry_run"])


def _reset() -> int:
    reset_exhausted(state_path())
    print("Cleared exhausted provider marks.")
    return 0


def _help() -> int:
    print(
        "Usage: multiplexor [--dry-run] [--provider NAME] [command]\n"
        "Commands: init, doctor, status, delegate TASK, ask PROMPT, next, reset\n"
        "Default command opens the best interactive provider."
    )
    return 0


def _yes(value: bool) -> str:
    return "yes" if value else "no"


if __name__ == "__main__":
    raise SystemExit(main())
