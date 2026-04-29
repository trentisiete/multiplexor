from __future__ import annotations

import shlex
import subprocess
import sys

from .providers import Provider
from .state import set_last_provider


def expand_args(args: list[str], prompt: str | None = None) -> list[str]:
    return [arg.replace("{prompt}", prompt or "") for arg in args]


def display_command(args: list[str]) -> str:
    return shlex.join(args)


def run_interactive(provider: Provider, state: dict, state_path, dry_run: bool = False) -> int:
    if not provider.supports("interactive"):
        print(f"Provider {provider.name} has no interactive_command.", file=sys.stderr)
        return 1
    command = provider.command_for("interactive")
    if dry_run:
        print(f"Would run provider: {provider.name}")
        print(f"Command: {display_command(command)}")
        return 0
    set_last_provider(state, provider.name, state_path)
    return subprocess.run(command, shell=False).returncode


def run_ask(
    providers: list[Provider],
    prompt: str,
    state: dict,
    state_path,
    timeout: int,
    dry_run: bool = False,
) -> int:
    for provider in providers:
        if not provider.supports("ask"):
            continue
        command = provider.command_for("ask", None if provider.ask_stdin else prompt)
        if dry_run:
            print(f"Would run provider: {provider.name}")
            print(f"Command: {display_command(command)}")
            if provider.ask_stdin:
                print("Prompt: <stdin>")
            return 0
        set_last_provider(state, provider.name, state_path)
        try:
            proc = subprocess.run(
                command,
                capture_output=True,
                input=prompt if provider.ask_stdin else None,
                text=True,
                timeout=timeout,
                shell=False,
            )
        except subprocess.TimeoutExpired:
            print(f"Provider {provider.name} timed out after {timeout} seconds. Trying next provider...", file=sys.stderr)
            continue
        if proc.returncode == 0:
            if proc.stdout:
                print(proc.stdout, end="")
            return 0
        if proc.stderr:
            print(proc.stderr, end="", file=sys.stderr)
        print(f"Provider {provider.name} failed with exit code {proc.returncode}. Trying next provider...", file=sys.stderr)
    print("No available providers found. Run `multiplexor doctor` to inspect your setup.", file=sys.stderr)
    return 1
