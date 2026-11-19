"""The entry point of run-aosp.sh. See aosp_build/run.py."""
from __future__ import annotations

import sys

# Do not leave __pycache__ in src/ (it may be root-owned under sudo).
sys.dont_write_bytecode = True

from aosp_build.run import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
