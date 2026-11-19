"""The values that do not depend on the android version.

The version files import this module, not aosp_build.versions (__init__.py),
to avoid a circular import.
"""
from __future__ import annotations

# The version of the repo tool itself (src/fetch.sh).
REPO_REV = "v2.55.1"

ARCHS = ("arm", "arm64", "x86_64")
PLATFORMS = ("rpi4", "cuttlefish", "emulator")
FORM_FACTORS = ("phone", "tv", "auto")

# The toolchain prefix by arch (CROSS_COMPILE). x86_64 has none.
CROSS_COMPILE = {"arm": "arm-linux-gnueabihf-", "arm64": "aarch64-linux-gnu-"}
