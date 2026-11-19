"""The types of the version tables (src/aosp_build/versions/android_*.py).

The values are written in the version files as literals. resolve() in
__init__.py looks them up without branching by the version or by the
combination (docs-ai/done-task/build-config-single-source/04).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Optional, Tuple, Union

# A value that is the same for every arch, or a value for each arch.
PerArch = Union[str, Dict[str, str]]


@dataclass(frozen=True)
class Make:
    """How src/build.sh builds AOSP."""
    tool: str  # "m" or "make"
    parallel: bool  # run with -j $(nproc)
    targets: Tuple[str, ...]


@dataclass(frozen=True)
class Variant:
    """One combination of (platform, form factor)."""
    lunch: str
    make: Make
    # The kernel build of src/build.sh: "none", "build.sh" or "make-<arch>".
    kernel_build: PerArch = "none"
    # The artifacts that src/build.sh copies to the output directory.
    artifacts: PerArch = "none"
    # Pass ARCH / CROSS_COMPILE to the kernel build (kernel_env).
    kernel_env_toolchain: bool = False
    # The environment variables only for this combination.
    env: Dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class Kind:
    """RPi ("rpi") or the others ("generic") of a version."""
    aosp_branch: str
    default_platform: str
    default_form_factor: str
    archs: Tuple[str, ...]
    default_arch: str
    # str.format() with platform, form_factor, default_platform and
    # default_form_factor. None if every arch in ARCHS is allowed.
    arch_error: Optional[str]
    python2_as_python: bool
    # (platform, form factor) -> Variant
    variants: Dict[Tuple[str, str], Variant]
    # The same format arguments as arch_error. None if variants has every
    # combination that matches the kind.
    combination_error: Optional[str]
    # The environment variables of every combination of this kind.
    env: Dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class VersionSpec:
    android: str
    # For RPi, but resolve() returns them for the others too.
    android_rpi_branch: str
    kernel_rpi_branch: Optional[str]
    # out/<BRANCH>/dist of the kernel. BRANCH is defined in build.config.
    kernel_dist_dir: Optional[str]
    kinds: Dict[str, Kind]  # "rpi" / "generic" -> Kind
