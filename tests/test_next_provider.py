import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

from multiplexor.cli import main


def _run(args):
    """Run main() with isolated config + state, returning (rc, stdout, stderr).

    Forces --dry-run on every call so command_exists() does not consult the
    host PATH (the fake config points commands at python3, which is fine for
    dry-run but would actually execute on a real call).
    """
    env = os.environ.copy()
    with tempfile.TemporaryDirectory() as tmp:
        os.environ["MULTIPLEXOR_CONFIG"] = "tests/fake_config.yaml"
        os.environ["MULTIPLEXOR_STATE"] = str(Path(tmp) / "state.json")
        out, err = StringIO(), StringIO()
        try:
            with redirect_stdout(out), redirect_stderr(err):
                rc = main(["next-provider", "--dry-run", *args])
        finally:
            os.environ.clear()
            os.environ.update(env)
        return rc, out.getvalue(), err.getvalue(), Path(os.environ.get("MULTIPLEXOR_STATE", "")) if False else None


def _run_real_state(args, state_path):
    """Variant that lets us inspect the state file after the call."""
    env = os.environ.copy()
    os.environ["MULTIPLEXOR_CONFIG"] = "tests/fake_config.yaml"
    os.environ["MULTIPLEXOR_STATE"] = str(state_path)
    out, err = StringIO(), StringIO()
    try:
        with redirect_stdout(out), redirect_stderr(err):
            rc = main(["next-provider", *args])
    finally:
        os.environ.clear()
        os.environ.update(env)
    return rc, out.getvalue(), err.getvalue()


class NextProviderTests(unittest.TestCase):
    def test_no_prev_returns_best_eligible(self):
        rc, out, _, _ = _run([])
        self.assertEqual(rc, 0)
        # gemini scores 130 in fake_config (free tier + priority 100)
        self.assertEqual(out.strip(), "gemini")

    def test_with_prev_returns_next_after_exhaustion(self):
        rc, out, _, _ = _run(["gemini"])
        self.assertEqual(rc, 0)
        # gemini marked exhausted → opencode (included, priority 90) wins
        self.assertEqual(out.strip(), "opencode")

    def test_ignores_extra_positional_args(self):
        # endy passes (prev, task-id, cwd). We must not choke on task-id/cwd.
        rc, out, _, _ = _run(["gemini", "20260515-abc", "/tmp/project"])
        self.assertEqual(rc, 0)
        self.assertEqual(out.strip(), "opencode")

    def test_unknown_prev_is_silently_skipped(self):
        # endy's `bash` stub is not a multiplexor provider. It must not error.
        rc, out, _, _ = _run(["bash"])
        self.assertEqual(rc, 0)
        # No real provider was marked exhausted, so gemini still wins.
        self.assertEqual(out.strip(), "gemini")

    def test_no_mark_does_not_mutate_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            state_path = Path(tmp) / "state.json"
            rc, out, _ = _run_real_state(["gemini", "--no-mark", "--dry-run"], state_path)
            self.assertEqual(rc, 0)
            # gemini chosen because --no-mark skipped exhausting it.
            self.assertEqual(out.strip(), "gemini")
            self.assertFalse(state_path.exists(), "state file written despite --no-mark")

    def test_mark_persists_to_state_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            state_path = Path(tmp) / "state.json"
            rc, out, _ = _run_real_state(["gemini"], state_path)
            self.assertEqual(rc, 0)
            self.assertEqual(out.strip(), "opencode")
            self.assertTrue(state_path.exists(), "state file not created")
            data = json.loads(state_path.read_text())
            self.assertEqual(data["last_provider"], "gemini")
            self.assertEqual(data["providers"]["gemini"]["status"], "exhausted")

    def test_exit_1_when_no_eligible(self):
        # Exhaust both real providers; ollama isn't in fake_config so the
        # candidate list goes empty.
        rc, _, err, _ = _run(["gemini"])
        self.assertEqual(rc, 0)
        # Second call: opencode is now last and we exhaust it too.
        with tempfile.TemporaryDirectory() as tmp:
            state_path = Path(tmp) / "state.json"
            _run_real_state(["gemini"], state_path)
            rc2, out2, err2 = _run_real_state(["opencode"], state_path)
            self.assertEqual(rc2, 1)
            self.assertEqual(out2.strip(), "")
            self.assertIn("no eligible provider", err2)

    def test_verbose_emits_score_to_stderr(self):
        rc, out, err, _ = _run(["--verbose"])
        self.assertEqual(rc, 0)
        self.assertEqual(out.strip(), "gemini")
        # Verbose lines go to stderr so the resolver's stdout stays clean.
        self.assertIn("score=130", err)
        self.assertIn("tier=free", err)

    def test_mode_ask_filters_by_template(self):
        # Both fake providers have ask_command, so result is the same as
        # interactive mode. This test pins down the API surface — if a
        # future provider lacks ask_command it should be filtered.
        rc, out, _, _ = _run(["--mode", "ask"])
        self.assertEqual(rc, 0)
        self.assertEqual(out.strip(), "gemini")

    def test_bad_mode_rejected(self):
        rc, _, err, _ = _run(["--mode", "bogus"])
        self.assertEqual(rc, 2)
        self.assertIn("must be 'interactive' or 'ask'", err)


if __name__ == "__main__":
    unittest.main()
