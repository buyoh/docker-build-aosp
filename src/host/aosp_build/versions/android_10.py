"""Android 10."""
from __future__ import annotations

from aosp_build.versions.constants import ARCHS
from aosp_build.versions.types import Kind, Make, Variant, VersionSpec

RPI = Kind(
    aosp_branch="android-10.0.0_r41",
    default_platform="rpi4",
    default_form_factor="tv",
    archs=("arm", "arm64"),
    default_arch="arm",
    arch_error="Android 10 for RPi supports only arm and arm64.",
    python2_as_python=False,
    combination_error=(
        "Android 10 supports only {default_platform}/{default_form_factor}"),
    variants={
        ("rpi4", "tv"): Variant(
            lunch="rpi4-eng",
            make=Make("make", parallel=True,
                      targets=("ramdisk", "systemimage", "vendorimage")),
            kernel_build={"arm": "make-arm", "arm64": "make-arm64"},
            artifacts={"arm": "rpi-kernel-arm", "arm64": "rpi-kernel-arm64"},
            kernel_env_toolchain=True,
        ),
    },
)

GENERIC = Kind(
    aosp_branch="android-10.0.0_r41",
    # aosp_x86_64 of Android 10-12 is goldfish (the Android Emulator).
    default_platform="emulator",
    default_form_factor="phone",
    # Not checked. The default is not x86_64 although the lunch target is.
    archs=ARCHS,
    default_arch="arm",
    arch_error=None,
    # TODO: Retest this (src/container/preprocess.sh links python to python2).
    python2_as_python=True,
    combination_error=(
        "Android 10 supports only {default_platform}/{default_form_factor}"),
    variants={
        ("emulator", "phone"): Variant(
            lunch="aosp_x86_64-eng",
            make=Make("m", parallel=False, targets=()),
        ),
    },
)

SPEC = VersionSpec(
    android="10",
    android_rpi_branch="arpi-10",
    kernel_rpi_branch=None,
    kernel_dist_dir=None,
    kinds={"rpi": RPI, "generic": GENERIC},
)
