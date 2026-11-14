"""Helpers for the python tests."""
from __future__ import annotations

import os

REPODIR = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))


def has_yaml() -> bool:
    try:
        import yaml  # noqa: F401
    except ImportError:
        return False
    return True
