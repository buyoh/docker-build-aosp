"""Shared code for build-aosp.sh (host) and the tasks in the container.

Keep this package compatible with Python 3.8 (the python of the docker image).
"""
from __future__ import annotations


class ConfigError(Exception):
    """An invalid parameter. The message is shown to the user as it is."""
