import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timedelta
from io import StringIO
from pathlib import Path

from multiplexor.cli import main


def _run(args, state_path=None):
    """Run main() with the fake config. Optionally redirect state to `state_path`."""
    env = os.environ.copy()
    tmp_path = state_path
    cleanup = False
    if tmp_path is None:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        tmp_path = tmp.name
        cleanup = True
        # Start with empty state.
        Path(tmp_path).unlink()
    try:
        os.environ["MULTIPLEXOR_CONFIG"] = "tests/fake_config.yaml"
        os.environ["MULTIPLEXOR_STATE"] = str(tmp_path)
        out, err = StringIO(), StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = main(args)
        return rc, out.getvalue(), err.getvalue()
    finally:
        os.environ.clear()
        os.environ.update(env)
        if cleanup and Path(tmp_path).exists():
            Path(tmp_path).unlink()


class StatusJsonTests(unittest.TestCase):
    def test_full_list_returns_envelope(self):
        rc, out, _ = _run(["status", "--json"])
        self.assertEqual(rc, 0)
        data = json.loads(out)
        self.assertIn("providers", data)
        self.assertIn("selected", data)
        names = {p["name"] for p in data["providers"]}
        # fake_config has gemini + opencode enabled, qwen disabled.
        self.assertIn("gemini", names)
        self.assertIn("opencode", names)
        # selected should be gemini (highest score in fake_config).
        self.assertEqual(data["selected"], "gemini")

    def test_single_name_returns_bare_dict(self):
        rc, out, _ = _run(["status", "--json", "gemini"])
        self.assertEqual(rc, 0)
        data = json.loads(out)
        # Bare object, NOT wrapped in {providers: ...}.
        self.assertEqual(data["name"], "gemini")
        self.assertEqual(data["tier"], "free")
        self.assertEqual(data["score"], 130)
        self.assertTrue(data["eligible"])
        # New fields the endy state contract relies on:
        self.assertIn("exhausted_until", data)
        self.assertIn("exhausted_seconds_remaining", data)

    def test_multiple_names_returns_envelope(self):
        rc, out, _ = _run(["status", "--json", "gemini", "opencode"])
        self.assertEqual(rc, 0)
        data = json.loads(out)
        # >1 name => envelope (so the caller always gets the same shape when
        # they pass anything other than exactly one name).
        self.assertIn("providers", data)
        self.assertEqual(len(data["providers"]), 2)

    def test_unknown_name_exits_1(self):
        rc, _, err = _run(["status", "--json", "nope"])
        self.assertEqual(rc, 1)
        self.assertIn("unknown provider", err)

    def test_exhausted_seconds_remaining_is_set(self):
        # Manually write state with gemini exhausted.
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as f:
            until = (datetime.now() + timedelta(hours=2)).isoformat(timespec="seconds")
            f.write(json.dumps({
                "last_provider": "gemini",
                "providers": {"gemini": {"status": "exhausted", "exhausted_until": until}},
            }).encode())
            state_path = f.name
        try:
            rc, out, _ = _run(["status", "--json", "gemini"], state_path=state_path)
            self.assertEqual(rc, 0)
            data = json.loads(out)
            self.assertTrue(data["exhausted"])
            self.assertEqual(data["exhausted_until"], until)
            # Should be approximately 2 * 3600 = 7200 seconds. Allow for clock drift.
            self.assertIsNotNone(data["exhausted_seconds_remaining"])
            self.assertGreater(data["exhausted_seconds_remaining"], 7000)
            self.assertLess(data["exhausted_seconds_remaining"], 7300)
            self.assertFalse(data["eligible"])
            self.assertIn("exhausted", data["reason"])
        finally:
            Path(state_path).unlink(missing_ok=True)

    def test_selected_reflects_exhaustion(self):
        # When gemini is exhausted, selected should be opencode.
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as f:
            until = (datetime.now() + timedelta(hours=1)).isoformat(timespec="seconds")
            f.write(json.dumps({
                "last_provider": "gemini",
                "providers": {"gemini": {"status": "exhausted", "exhausted_until": until}},
            }).encode())
            state_path = f.name
        try:
            rc, out, _ = _run(["status", "--json"], state_path=state_path)
            self.assertEqual(rc, 0)
            data = json.loads(out)
            self.assertEqual(data["selected"], "opencode")
        finally:
            Path(state_path).unlink(missing_ok=True)

    def test_human_status_unchanged_without_json(self):
        # Backward-compat: no --json keeps the original text shape.
        rc, out, _ = _run(["status"])
        self.assertEqual(rc, 0)
        # Old format starts each provider with "1. gemini" etc.
        self.assertRegex(out, r"^\d+\. ")

    def test_status_filter_by_single_name_human(self):
        rc, out, _ = _run(["status", "gemini"])
        self.assertEqual(rc, 0)
        self.assertIn("gemini", out)
        self.assertNotIn("opencode", out)


if __name__ == "__main__":
    unittest.main()
