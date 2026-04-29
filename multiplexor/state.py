from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path


def state_path() -> Path:
    override = os.environ.get("MULTIPLEXOR_STATE") or os.environ.get("STATE_PATH")
    if override:
        return Path(override).expanduser()
    if os.name == "nt":
        return Path(os.environ.get("USERPROFILE", "~")).expanduser() / ".multiplexor" / "state.json"
    base = Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser()
    return base / "multiplexor" / "state.json"


def empty_state() -> dict:
    return {"last_provider": None, "providers": {}}


def load_state(path: str | Path | None = None) -> tuple[dict, Path]:
    resolved = Path(path).expanduser() if path else state_path()
    if not resolved.exists():
        return empty_state(), resolved
    try:
        data = json.loads(resolved.read_text())
        if not isinstance(data, dict):
            raise ValueError("state root is not an object")
        data.setdefault("providers", {})
        data.setdefault("last_provider", None)
        return data, resolved
    except Exception as exc:
        print(f"Warning: could not read state file {resolved}: {exc}. Using empty state.", file=sys.stderr)
        return empty_state(), resolved


def save_state(data: dict, path: str | Path | None = None) -> None:
    resolved = Path(path).expanduser() if path else state_path()
    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text(json.dumps(data, indent=2, sort_keys=True))


def set_last_provider(data: dict, provider: str, path: str | Path | None = None) -> None:
    data["last_provider"] = provider
    data.setdefault("providers", {})
    save_state(data, path)


def mark_exhausted(provider: str, hours: int, path: str | Path | None = None) -> dict:
    data, resolved = load_state(path)
    until = datetime.now() + timedelta(hours=hours)
    providers = data.setdefault("providers", {})
    providers.setdefault(provider, {})
    providers[provider]["status"] = "exhausted"
    providers[provider]["exhausted_until"] = until.isoformat(timespec="seconds")
    data["last_provider"] = provider
    save_state(data, resolved)
    return data


def reset_exhausted(path: str | Path | None = None) -> dict:
    data, resolved = load_state(path)
    for value in data.get("providers", {}).values():
        if isinstance(value, dict):
            value.pop("status", None)
            value.pop("exhausted_until", None)
    save_state(data, resolved)
    return data


def is_exhausted(data: dict, provider: str, now: datetime | None = None) -> bool:
    info = data.get("providers", {}).get(provider, {})
    until = info.get("exhausted_until") if isinstance(info, dict) else None
    if info.get("status") != "exhausted" or not until:
        return False
    try:
        return datetime.fromisoformat(until) > (now or datetime.now())
    except ValueError:
        return False
