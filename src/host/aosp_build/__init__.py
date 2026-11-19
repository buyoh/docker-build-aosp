"""The package of the host tools (build-aosp.sh and run-aosp.sh).

It runs only on the host and is not passed to the container. Keep it
compatible with Python 3.8 and the standard library.
"""
from __future__ import annotations


class ConfigError(Exception):
    """An invalid parameter. The message is shown to the user as it is."""
