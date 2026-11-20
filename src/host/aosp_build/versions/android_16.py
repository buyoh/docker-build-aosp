"""Android 16.

Only the generic kind (cuttlefish and the emulator). RPi is not supported:
android-rpi has no branch for 15 or later
(docs-ai/survey/android-16-support/06).
The release config is bp4a, the release of r4 (QPR2). trunk_staging would
make a preview build (codename Baklava).
All variants are eng to avoid relinking (docs-ai/info/form-factor-build/05).
"""
from __future__ import annotations

from aosp_build.versions.types import Kind, Make, Variant, VersionSpec

# hosttar: cvd-host_package.tar.gz is not built by default.
_CUTTLEFISH_MAKE = Make("m", parallel=False, targets=("droid", "hosttar"))
_EMULATOR_MAKE = Make("m", parallel=False, targets=("droid", "emu_img_zip"))

GENERIC = Kind(
    aosp_branch="android-16.0.0_r4",
    default_platform="cuttlefish",
    default_form_factor="tv",
    # The lunch targets are always x86. Do not build x86_64 in gen/out.arm64.
    archs=("x86_64",),
    default_arch="x86_64",
    arch_error="Android 16 for {platform} supports only x86_64.",
    python2_as_python=False,
    # The same as 14. Not known whether 16 needs it.
    env={"ALLOW_NINJA_ENV": "1"},
    combination_error=None,  # variants has every (platform, form factor)
    variants={
        ("cuttlefish", "phone"): Variant(
            lunch="aosp_cf_x86_64_phone-bp4a-eng",
            make=_CUTTLEFISH_MAKE, artifacts="cuttlefish"),
        ("cuttlefish", "tv"): Variant(
            lunch="aosp_cf_x86_64_tv-bp4a-eng",
            make=_CUTTLEFISH_MAKE, artifacts="cuttlefish"),
        ("cuttlefish", "auto"): Variant(
            lunch="aosp_cf_x86_64_auto-bp4a-eng",
            make=_CUTTLEFISH_MAKE, artifacts="cuttlefish"),
        ("emulator", "phone"): Variant(
            lunch="sdk_phone64_x86_64-bp4a-eng",
            make=_EMULATOR_MAKE, artifacts="emulator"),
        # r4 has no x86_64 TV product for the emulator. sdk_atv_x86 is
        # 32-bit: r3 and later pin the 6.1 kernel by themselves
        # (device/google/atv/emulator_x86/x86_64.mk), so no TARGET_KERNEL_USE
        # (docs-ai/done-task/emulator-tv-boot-loop).
        ("emulator", "tv"): Variant(
            lunch="sdk_atv_x86-bp4a-eng",
            make=_EMULATOR_MAKE, artifacts="emulator"),
        ("emulator", "auto"): Variant(
            lunch="sdk_car_x86_64-bp4a-eng",
            make=_EMULATOR_MAKE, artifacts="emulator"),
    },
)

SPEC = VersionSpec(
    android="16",
    android_rpi_branch=None,
    kernel_rpi_branch=None,
    kernel_dist_dir=None,
    kinds={"generic": GENERIC},
)
