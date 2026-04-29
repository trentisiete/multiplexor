from __future__ import annotations

import copy
import os
from pathlib import Path


def config_path() -> Path:
    override = os.environ.get("MULTIPLEXOR_CONFIG") or os.environ.get("CONFIG_PATH")
    if override:
        return Path(override).expanduser()
    if os.name == "nt":
        return Path(os.environ.get("USERPROFILE", "~")).expanduser() / ".multiplexor" / "config.yaml"
    base = Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser()
    return base / "multiplexor" / "config.yaml"


def example_config_text() -> str:
    paths = (Path(__file__).with_name("config.example.yaml"), Path(__file__).resolve().parents[1] / "config.example.yaml")
    for path in paths:
        if path.exists():
            return path.read_text()
    return """routing:
  exhausted_cooldown_hours: 24
  ask_timeout_seconds: 120
tiers:
  free:
    bonus: 30
  included:
    bonus: 25
  local:
    bonus: 5
  paid:
    bonus: 0
providers:
  gemini:
    enabled: true
    tier: free
    priority: 100
    command: "gemini"
    interactive_command: ["gemini"]
    ask_command: ["gemini", "-p", ""]
    ask_stdin: true
"""


def load_config(path: str | Path | None = None) -> tuple[dict, Path, bool]:
    cfg = parse_yaml_text(example_config_text())
    cfg = cfg if isinstance(cfg, dict) else {}
    resolved = Path(path).expanduser() if path else config_path()
    exists = resolved.exists()
    if exists:
        user_cfg = parse_yaml_text(resolved.read_text())
        if isinstance(user_cfg, dict):
            _deep_merge(cfg, user_cfg)
    return cfg, resolved, exists


def init_config(path: str | Path | None = None) -> tuple[Path, bool]:
    resolved = Path(path).expanduser() if path else config_path()
    if resolved.exists():
        return resolved, False
    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text(example_config_text())
    return resolved, True


def parse_yaml_text(text: str) -> dict:
    try:
        import yaml  # type: ignore

        return yaml.safe_load(text) or {}
    except ImportError:
        return _parse_simple_yaml(text)


def _parse_simple_yaml(text: str) -> dict:
    data: dict = {}
    stack: list[tuple[int, object]] = [(-1, data)]
    list_keys = {"interactive_command", "ask_command"}
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        item = line.strip()
        while stack and stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1]
        if item.startswith("- "):
            if isinstance(parent, list):
                parent.append(_scalar(item[2:].strip()))
            continue
        if ":" not in item or not isinstance(parent, dict):
            continue
        key, raw_value = item.split(":", 1)
        key, raw_value = key.strip(), raw_value.strip()
        if raw_value == "":
            node: object = [] if key in list_keys else {}
            parent[key] = node
            stack.append((indent, node))
        else:
            parent[key] = _scalar(raw_value)
    return data


def _scalar(value: str):
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        return [] if not inner else [_scalar(part.strip()) for part in inner.split(",")]
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    if value.lower() in {"true", "false"}:
        return value.lower() == "true"
    try:
        return int(value)
    except ValueError:
        return value


def _deep_merge(base: dict, override: dict) -> dict:
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            _deep_merge(base[key], value)
        else:
            base[key] = copy.deepcopy(value)
    return base
