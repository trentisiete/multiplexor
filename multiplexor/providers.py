from __future__ import annotations

import shutil
from dataclasses import dataclass


@dataclass(frozen=True)
class Provider:
    name: str
    enabled: bool
    tier: str
    priority: int
    command: str
    interactive_command: list[str] | None
    ask_command: list[str] | None
    ask_stdin: bool = False
    fallback_only: bool = False
    default_model: str | None = None

    @classmethod
    def from_config(cls, name: str, raw: dict) -> "Provider":
        interactive = _list_or_none(raw.get("interactive_command"))
        ask = _list_or_none(raw.get("ask_command"))
        command = str(raw.get("command") or _first_arg(interactive) or _first_arg(ask) or name)
        return cls(
            name=name,
            enabled=bool(raw.get("enabled", True)),
            tier=str(raw.get("tier", "paid")),
            priority=int(raw.get("priority", 0)),
            command=command,
            interactive_command=interactive,
            ask_command=ask,
            ask_stdin=bool(raw.get("ask_stdin", False)),
            fallback_only=bool(raw.get("fallback_only", False)),
            default_model=raw.get("default_model"),
        )

    def template_for(self, mode: str) -> list[str] | None:
        return self.ask_command if mode == "ask" else self.interactive_command

    def supports(self, mode: str) -> bool:
        return bool(self.template_for(mode))

    def command_for(self, mode: str, prompt: str | None = None) -> list[str]:
        template = self.template_for(mode) or []
        return [part.replace("{prompt}", prompt or "") for part in template]

    def installed(self) -> bool:
        return bool(self.command and shutil.which(self.command))

    def score(self, tiers: dict) -> int:
        tier = tiers.get(self.tier, {}) if isinstance(tiers, dict) else {}
        return self.priority + int(tier.get("bonus", 0))


def providers_from_config(config: dict) -> list[Provider]:
    items = []
    for name, raw in (config.get("providers") or {}).items():
        if not isinstance(raw, dict):
            continue
        items.append(Provider.from_config(name, raw))
    return items


def get_provider(config: dict, name: str) -> Provider | None:
    return next((p for p in providers_from_config(config) if p.name == name), None)


def command_exists(provider: Provider) -> bool:
    return provider.installed()


def _list_or_none(value) -> list[str] | None:
    if value is None:
        return None
    if isinstance(value, list):
        return [str(part) for part in value]
    return [str(value)]


def _first_arg(value: list[str] | None) -> str | None:
    return value[0] if value else None
