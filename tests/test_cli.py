import os
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

from multiplexor.cli import main


class CliTests(unittest.TestCase):
    def test_delegate_alias_dry_run(self):
        env = os.environ.copy()
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["MULTIPLEXOR_CONFIG"] = "tests/fake_config.yaml"
            os.environ["MULTIPLEXOR_STATE"] = str(Path(tmp) / "state.json")
            out = StringIO()
            try:
                with redirect_stdout(out):
                    rc = main(["delegate", "--dry-run", "hola"])
            finally:
                os.environ.clear()
                os.environ.update(env)
        self.assertEqual(rc, 0)
        self.assertIn("Would run provider: gemini", out.getvalue())


if __name__ == "__main__":
    unittest.main()
