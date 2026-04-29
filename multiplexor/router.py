from __future__ import annotations

from .providers import Provider, command_exists, providers_from_config
from .state import is_exhausted


def score(provider: Provider, config: dict) -> int:
    return provider.score(config.get("tiers", {}))


def provider_status(
    provider: Provider,
    config: dict,
    state: dict,
    mode: str = "interactive",
    detector=command_exists,
    check_installed: bool = True,
) -> dict:
    installed = detector(provider) if check_installed else True
    exhausted = is_exhausted(state, provider.name)
    reason = ""
    eligible = True
    if not provider.enabled:
        eligible, reason = False, "disabled"
    elif not provider.supports(mode):
        eligible, reason = False, f"{mode}_command missing"
    elif provider.name == "ollama" and not provider.default_model:
        eligible, reason = False, "Ollama selected but no default model is configured."
    elif not installed:
        eligible, reason = False, f"command `{provider.command}` was not found in PATH"
    elif exhausted:
        eligible, reason = False, "temporarily exhausted"
    return {
        "name": provider.name,
        "tier": provider.tier,
        "installed": installed,
        "exhausted": exhausted,
        "fallback_only": provider.fallback_only,
        "score": score(provider, config) if provider.enabled else None,
        "eligible": eligible,
        "reason": reason,
        "has_ask": bool(provider.ask_command),
        "provider": provider,
    }


def ranked_statuses(config: dict, state: dict, mode: str = "interactive", **kwargs) -> list[dict]:
    rows = [provider_status(p, config, state, mode, **kwargs) for p in providers_from_config(config)]
    return sorted(rows, key=lambda r: (not r["eligible"], r["fallback_only"], -(r["score"] or -1), r["name"]))


def candidates(config: dict, state: dict, mode: str, forced: str | None = None, **kwargs) -> list[Provider]:
    if forced:
        rows = [r for r in ranked_statuses(config, state, mode, **kwargs) if r["name"] == forced]
        return [rows[0]["provider"]] if rows and rows[0]["eligible"] else []
    rows = [r for r in ranked_statuses(config, state, mode, **kwargs) if r["eligible"]]
    normal = [r["provider"] for r in rows if not r["fallback_only"]]
    fallback = [r["provider"] for r in rows if r["fallback_only"]]
    return normal or fallback


def select_provider(config: dict, state: dict, mode: str, forced: str | None = None, **kwargs) -> Provider | None:
    items = candidates(config, state, mode, forced, **kwargs)
    return items[0] if items else None
