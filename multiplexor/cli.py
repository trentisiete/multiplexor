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
    if command == "next-provider":
        return _next_provider(rest, opts)
    if command == "reset":
        return _reset()
    if command != "run":
        print(f"Unknown command: {command}", file=sys.stderr)
        return 2
    return _run(opts)


def next_provider_entry() -> int:
    """Console-script entry point: `multiplexor-next-provider <prev> <task> <cwd>`.

    Endy's ENDY_HANDOFF_RESOLVER invocation quotes the value as a single
    word, so a subcommand string like "multiplexor next-provider" cannot
    be exec'd directly. This wrapper is a single binary that just calls
    the regular `next-provider` command with the same argv, so users can
    set:

        export ENDY_HANDOFF_RESOLVER=multiplexor-next-provider
    """
    return main(["next-provider", *sys.argv[1:]])


def _extract_options(argv: list[str]) -> tuple[dict, list[str]]:
    opts = {
        "dry_run": False,
        "provider": None,
        "no_mark": False,
        "mode": None,
        "verbose": False,
        "for_endy": False,
    }
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
        elif arg == "--no-mark":
            opts["no_mark"] = True
            i += 1
        elif arg == "--mode":
            if i + 1 >= len(argv):
                raise SystemExit("--mode requires a value (interactive or ask)")
            opts["mode"] = argv[i + 1]
            i += 2
        elif arg in {"--verbose", "-V"}:
            opts["verbose"] = True
            i += 1
        elif arg == "--for":
            if i + 1 >= len(argv):
                raise SystemExit("--for requires a target name (endy)")
            target = argv[i + 1]
            if target not in {"endy"}:
                raise SystemExit(f"--for {target}: unknown target (expected: endy)")
            opts["for_endy"] = True
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


# Providers multiplexor knows about that endy cannot drive headlessly today.
# Used by --for endy to filter the resolver output to actionable agents only.
_ENDY_UNSUPPORTED = {"ollama"}


def _next_provider(rest: list[str], opts: dict) -> int:
    """Print the next eligible provider name to stdout. Pure query, no launch.

    Signature matches endy's ENDY_HANDOFF_RESOLVER contract:
        multiplexor-next-provider <prev-agent> [<task-id>] [<cwd>]
    `task-id` and `cwd` are accepted and ignored — they exist so the
    command can be a drop-in for the resolver hook without endy needing
    to know what multiplexor wants.
    """
    prev = rest[0] if rest else None
    # rest[1:] (task-id, cwd, anything else) is intentionally ignored.

    config, _, _ = load_config()
    data, st_path = load_state()
    mode = opts["mode"] or "interactive"
    if mode not in {"interactive", "ask"}:
        print(f"--mode {mode}: must be 'interactive' or 'ask'", file=sys.stderr)
        return 2

    # Mark the previous provider as exhausted (so it does not get re-selected),
    # unless the caller opted out. Mirrors what `multiplexor next` does, minus
    # the auto-launch.
    hours = int(config.get("routing", {}).get("exhausted_cooldown_hours", 24))
    if prev and not opts["no_mark"]:
        from .providers import get_provider

        if get_provider(config, prev):
            if opts["dry_run"]:
                data = copy.deepcopy(data)
                data.setdefault("providers", {}).setdefault(prev, {})
                data["providers"][prev]["status"] = "exhausted"
                data["providers"][prev]["exhausted_until"] = "9999-12-31T00:00:00"
            else:
                data = mark_exhausted(prev, hours, st_path)
        # Silently skip if `prev` is not a multiplexor provider (e.g. endy's
        # `bash` stub agent). The resolver still computes the best alternative.

    # Compute the ranked candidates. Reuses the same logic `status` / `doctor`
    # surface, so what the resolver returns matches what the user sees.
    rows = ranked_statuses(config, data, mode, check_installed=not opts["dry_run"])
    eligible = [r for r in rows if r["eligible"]]
    if opts["for_endy"]:
        eligible = [r for r in eligible if r["name"] not in _ENDY_UNSUPPORTED]

    if not eligible:
        # Nothing endy can run with. Print the diagnostics to stderr so the
        # caller can show them; stdout stays empty so the resolver hook fails
        # cleanly and endy falls back to demanding an explicit --to.
        msg_target = "multiplexor" if not opts["for_endy"] else "multiplexor (for endy)"
        print(f"{msg_target}: no eligible provider", file=sys.stderr)
        if opts["verbose"]:
            for r in rows:
                reason = r["reason"] or "ok"
                print(f"  {r['name']}: eligible={_yes(r['eligible'])} reason={reason}", file=sys.stderr)
        return 1

    chosen = eligible[0]
    print(chosen["name"])
    if opts["verbose"]:
        # Stderr stays out of the resolver's stdout (which only carries the
        # name). Useful when running the command manually for debugging.
        print(f"# score={chosen['score']} tier={chosen['tier']} mode={mode}", file=sys.stderr)
        if len(eligible) > 1:
            alt = ", ".join(f"{r['name']}({r['score']})" for r in eligible[1:5])
            print(f"# alternatives: {alt}", file=sys.stderr)
    return 0


def _help() -> int:
    print(
        "Usage: multiplexor [--dry-run] [--provider NAME] [command]\n"
        "Commands:\n"
        "  init                 Create a default config\n"
        "  doctor               Show detected providers and state\n"
        "  status               List providers ranked by score\n"
        "  delegate TASK        Run TASK on the best eligible provider (headless)\n"
        "  ask PROMPT           Alias for delegate\n"
        "  next                 Mark last provider exhausted, launch the next one\n"
        "  next-provider [PREV [TASK CWD]]\n"
        "                       Pure query: print the next eligible provider name to\n"
        "                       stdout and exit. Marks PREV exhausted unless --no-mark.\n"
        "                       Designed as endy's ENDY_HANDOFF_RESOLVER target.\n"
        "                       Options: --no-mark, --mode interactive|ask, --verbose,\n"
        "                                --for endy (filter to providers endy can drive)\n"
        "  reset                Clear all exhaustion marks\n"
        "Default command opens the best interactive provider.\n"
        "\n"
        "For the endy integration:\n"
        "  export ENDY_HANDOFF_RESOLVER=multiplexor-next-provider\n"
        "  endy handoff <task-id>     # multiplexor picks the next agent automatically"
    )
    return 0


def _yes(value: bool) -> str:
    return "yes" if value else "no"


if __name__ == "__main__":
    raise SystemExit(main())
