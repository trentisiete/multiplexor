import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import Mock, patch

from multiplexor.providers import Provider
from multiplexor.runner import expand_args, run_ask


class RunnerTests(unittest.TestCase):
    def provider(self):
        return Provider("fake", True, "free", 1, "python3", ["python3"], ["python3", "-c", "{prompt}"])

    def stdin_provider(self):
        return Provider("fake", True, "free", 1, "python3", ["python3"], ["python3", "-c", "print(input())"], True)

    def test_ask_dry_run_does_not_execute(self):
        with patch("multiplexor.runner.subprocess.run") as run:
            with redirect_stdout(StringIO()):
                rc = run_ask([self.provider()], "print('x')", {}, Path("/tmp/no-state.json"), 1, dry_run=True)
        self.assertEqual(rc, 0)
        run.assert_not_called()

    def test_prompt_placeholder_substitution(self):
        self.assertEqual(expand_args(["cmd", "{prompt}"], "hello"), ["cmd", "hello"])

    def test_subprocess_uses_shell_false(self):
        proc = Mock(returncode=0, stdout="ok\n", stderr="")
        with tempfile.TemporaryDirectory() as tmp:
            with patch("multiplexor.runner.subprocess.run", return_value=proc) as run:
                with redirect_stdout(StringIO()):
                    rc = run_ask([self.provider()], "print('ok')", {}, Path(tmp) / "state.json", 1)
        self.assertEqual(rc, 0)
        self.assertIs(run.call_args.kwargs["shell"], False)

    def test_stdin_provider_sends_prompt_as_input(self):
        proc = Mock(returncode=0, stdout="ok\n", stderr="")
        with tempfile.TemporaryDirectory() as tmp:
            with patch("multiplexor.runner.subprocess.run", return_value=proc) as run:
                with redirect_stdout(StringIO()):
                    rc = run_ask([self.stdin_provider()], "secret prompt", {}, Path(tmp) / "state.json", 1)
        self.assertEqual(rc, 0)
        self.assertEqual(run.call_args.kwargs["input"], "secret prompt")
        self.assertNotIn("secret prompt", run.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
