import tempfile
import unittest
from pathlib import Path

from multiplexor.config import _parse_simple_yaml, _scalar, load_config
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

    def test_inline_flow_dict_parsed_as_dict(self):
        # Without PyYAML, the fallback parser used to treat `{ bonus: 30 }`
        # as a literal string, which crashed in the router. Now we parse it.
        cfg = _parse_simple_yaml("tiers:\n  free: { bonus: 30 }\n")
        self.assertEqual(cfg, {"tiers": {"free": {"bonus": 30}}})

    def test_inline_flow_dict_multiple_keys(self):
        self.assertEqual(_scalar("{ a: 1, b: 2, c: 'three' }"), {"a": 1, "b": 2, "c": "three"})

    def test_inline_flow_dict_empty(self):
        self.assertEqual(_scalar("{}"), {})

    def test_inline_flow_dict_in_provider_enabled_false(self):
        # The shape endy's smoke test emits when disabling defaults in bulk.
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.yaml"
            path.write_text(
                "providers:\n"
                "  gemini: { enabled: false }\n"
                "  opencode: { enabled: false }\n"
                "  bash:\n"
                "    enabled: true\n"
                "    tier: free\n"
                "    priority: 100\n"
                "    command: bash\n"
                "    interactive_command:\n"
                "      - bash\n"
            )
            cfg, _, _ = load_config(path)
        self.assertFalse(get_provider(cfg, "gemini").enabled)
        self.assertFalse(get_provider(cfg, "opencode").enabled)
        bash = get_provider(cfg, "bash")
        self.assertTrue(bash.enabled)
        self.assertEqual(bash.command_for("interactive"), ["bash"])

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
