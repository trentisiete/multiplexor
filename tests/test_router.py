import unittest
from datetime import datetime, timedelta

from multiplexor.config import parse_yaml_text
from multiplexor.providers import get_provider
from multiplexor.router import provider_status, score, select_provider


CONFIG = parse_yaml_text(open("config.example.yaml").read())


def detector(installed):
    return lambda provider: provider.name in installed


class RouterTests(unittest.TestCase):
    def test_disabled_provider_is_ignored(self):
        codex = get_provider(CONFIG, "codex")
        status = provider_status(codex, CONFIG, {}, detector=detector({"codex"}))
        self.assertFalse(status["eligible"])
        self.assertEqual(status["reason"], "disabled")

    def test_score_uses_priority_plus_tier_bonus(self):
        gemini = get_provider(CONFIG, "gemini")
        self.assertEqual(score(gemini, CONFIG), 130)

    def test_gemini_before_opencode(self):
        provider = select_provider(CONFIG, {}, "ask", detector=detector({"gemini", "opencode"}))
        self.assertEqual(provider.name, "gemini")

    def test_opencode_when_gemini_exhausted(self):
        state = {"providers": {"gemini": {"status": "exhausted", "exhausted_until": future()}}}
        provider = select_provider(CONFIG, state, "ask", detector=detector({"gemini", "qwen", "opencode"}))
        self.assertEqual(provider.name, "opencode")

    def test_ollama_when_normals_unavailable(self):
        provider = select_provider(CONFIG, {}, "ask", detector=detector({"ollama"}))
        self.assertEqual(provider.name, "ollama")

    def test_ollama_not_chosen_when_normal_available(self):
        provider = select_provider(CONFIG, {}, "ask", detector=detector({"gemini", "ollama"}))
        self.assertEqual(provider.name, "gemini")


def future():
    return (datetime.now() + timedelta(hours=1)).isoformat(timespec="seconds")


if __name__ == "__main__":
    unittest.main()
