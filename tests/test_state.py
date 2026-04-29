import tempfile
import unittest
from pathlib import Path

from multiplexor.state import is_exhausted, load_state, mark_exhausted, reset_exhausted, set_last_provider


class StateTests(unittest.TestCase):
    def test_next_marks_last_provider_exhausted(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "state.json"
            data, _ = load_state(path)
            set_last_provider(data, "gemini", path)
            marked = mark_exhausted("gemini", 24, path)
        self.assertTrue(is_exhausted(marked, "gemini"))
        self.assertEqual(marked["last_provider"], "gemini")

    def test_reset_clears_exhausted(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "state.json"
            mark_exhausted("gemini", 24, path)
            reset = reset_exhausted(path)
        self.assertFalse(is_exhausted(reset, "gemini"))


if __name__ == "__main__":
    unittest.main()
