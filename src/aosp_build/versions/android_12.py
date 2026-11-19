"""Android 12."""
from __future__ import annotations

from aosp_build.versions.constants import ARCHS
from aosp_build.versions.types import Kind, Make, Variant, VersionSpec

_COMMON_ENV = {"ALLOW_NINJA_ENV": "1"}

RPI = Kind(
    aosp_branch="android-12.1.0_r21",
    default_platform="rpi4",
    default_form_factor="tv",
    # The kernel and lunch target decide the actual arch since Android 12.
    archs=("arm64",),
    default_arch="arm64",
    arch_error="Android 12 for RPi supports only arm64.",
    python2_as_python=False,
    env=_COMMON_ENV,
    combination_error=(
        "Android 12 supports only {default_platform}/{default_form_factor}"),
    variants={
        ("rpi4", "tv"): Variant(
            lunch="rpi4-eng",
            make=Make("make", parallel=True,
                      targets=("ramdisk", "systemimage", "vendorimage")),
            kernel_build="build.sh",
            artifacts="rpi-kernel-dist",
        ),
    },
)

GENERIC = Kind(
    aosp_branch="android-12.1.0_r21",
    # aosp_x86_64 of Android 10-12 is goldfish (the Android Emulator).
    default_platform="emulator",
    default_form_factor="phone",
    # Not checked. The default is not x86_64 although the lunch target is.
    archs=ARCHS,
    default_arch="arm64",
    arch_error=None,
    python2_as_python=False,
    env=_COMMON_ENV,
    combination_error=(
        "Android 12 supports only {default_platform}/{default_form_factor}"),
    variants={
        ("emulator", "phone"): Variant(
            lunch="aosp_x86_64-eng",
            make=Make("m", parallel=False, targets=()),
        ),
    },
)

SPEC = VersionSpec(
    android="12",
    android_rpi_branch="arpi-12",
    kernel_rpi_branch="arpi-5.10",
    kernel_dist_dir="arpi-5.10",
    kinds={"rpi": RPI, "generic": GENERIC},
)
