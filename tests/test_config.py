import tempfile
import unittest
from pathlib import Path

from multiplexor.config import load_config
from multiplexor.providers import get_provider


class ConfigTests(unittest.TestCase):
    def test_load_default_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg, _, exists = load_config(Path(tmp) / "missing.yaml")
        self.assertFalse(exists)
        self.assertIn("gemini", cfg["providers"])
        self.assertFalse(cfg["providers"]["codex"]["enabled"])

    def test_user_config_overrides_provider(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.yaml"
            path.write_text("providers:\n  gemini:\n    enabled: false\n")
            cfg, _, _ = load_config(path)
        self.assertFalse(get_provider(cfg, "gemini").enabled)

    def test_custom_provider_from_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.yaml"
            path.write_text(
                "providers:\n"
                "  localfake:\n"
                "    enabled: true\n"
                "    tier: local\n"
                "    priority: 7\n"
                "    command: python3\n"
                "    ask_command:\n"
                "      - python3\n"
                "      - -c\n"
                "      - print('ok')\n"
            )
            cfg, _, _ = load_config(path)
        provider = get_provider(cfg, "localfake")
        self.assertEqual(provider.command_for("ask"), ["python3", "-c", "print('ok')"])


if __name__ == "__main__":
    unittest.main()
