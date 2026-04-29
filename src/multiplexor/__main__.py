"""multiplexor — Launch the best available AI agent CLI.

This Python package wraps the multiplexor Bash script.
It locates the script within the installed package and executes it,
passing through all arguments and exit codes.
"""

import importlib.resources
import os
import shutil
import subprocess
import sys
import tempfile


def _find_script() -> str:
    """Locate the multiplexor bash script within the installed package."""
    # Try modern importlib.resources (Python 3.9+)
    try:
        files = importlib.resources.files("multiplexor.data")
        script = files / "multiplexor"
        path = str(script)
        if os.path.isfile(path):
            return path
    except (ImportError, ModuleNotFoundError):
        pass

    # Fallback: look relative to this module's file
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(here, "data", "multiplexor"),
        os.path.join(here, "..", "..", "multiplexor"),
        os.path.join(here, "..", "multiplexor"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return os.path.abspath(path)

    return ""


def main() -> None:
    """Entry point: execute the multiplexor bash script."""
    script = _find_script()

    if not script or not os.path.isfile(script):
        print(
            "Error: multiplexor bash script not found.\n"
            "This usually means the package was not installed correctly.\n"
            "Try: pip install --force-reinstall multiplexor",
            file=sys.stderr,
        )
        sys.exit(1)

    # Ensure the script is executable
    if not os.access(script, os.X_OK):
        os.chmod(script, 0o755)

    # Execute, passing through stdin/stdout/stderr
    proc = subprocess.run(
        ["bash", script] + sys.argv[1:],
        stdin=sys.stdin,
        stdout=sys.stdout,
        stderr=sys.stderr,
    )
    sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
