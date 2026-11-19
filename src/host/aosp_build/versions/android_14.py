"""Android 14.

RPi: https://github.com/android-rpi/local_manifests/tree/arpi14-pi4
The non-RPi tree is r74, so the release config (trunk_staging) is required.
All non-RPi variants are eng to avoid relinking
(docs-ai/info/form-factor-build/05).
"""
from __future__ import annotations

from aosp_build.versions.types import Kind, Make, Variant, VersionSpec

_COMMON_ENV = {"ALLOW_NINJA_ENV": "1"}

RPI = Kind(
    aosp_branch="android-14.0.0_r17",
    default_platform="rpi4",
    default_form_factor="tv",
    archs=("arm64",),
    default_arch="arm64",
    arch_error="Android 14 for RPi supports only arm64.",
    python2_as_python=False,
    env={**_COMMON_ENV,
         # The prebuilt ABI reference dump of libcrypto mismatches the build.
         "SKIP_ABI_CHECKS": "true"},
    combination_error=(
        "Android 14 for RPi supports only form factor: tv. Use --platform "
        "cuttlefish or emulator for {form_factor} with another --workdir "
        "(the AOSP tag differs from RPi)."),
    variants={
        ("rpi4", "tv"): Variant(
            lunch="rpi4_tv-userdebug",
            make=Make("m", parallel=True,
                      targets=("ramdisk", "systemimage", "vendorimage")),
            kernel_build="build.sh",
            artifacts="rpi-kernel-dist",
        ),
    },
)

# hosttar: cvd-host_package.tar.gz is not built by default.
_CUTTLEFISH_MAKE = Make("m", parallel=False, targets=("droid", "hosttar"))
_EMULATOR_MAKE = Make("m", parallel=False, targets=("droid", "emu_img_zip"))

GENERIC = Kind(
    aosp_branch="android-14.0.0_r74",
    default_platform="cuttlefish",
    default_form_factor="tv",
    # The lunch targets are always x86. Do not build x86_64 in gen/out.arm64.
    archs=("x86_64",),
    default_arch="x86_64",
    arch_error="Android 14 for {platform} supports only x86_64.",
    python2_as_python=False,
    env=_COMMON_ENV,
    combination_error=None,  # variants has every (platform, form factor)
    variants={
        ("cuttlefish", "phone"): Variant(
            lunch="aosp_cf_x86_64_phone-trunk_staging-eng",
            make=_CUTTLEFISH_MAKE, artifacts="cuttlefish"),
        ("cuttlefish", "tv"): Variant(
            lunch="aosp_cf_x86_64_tv-trunk_staging-eng",
            make=_CUTTLEFISH_MAKE, artifacts="cuttlefish"),
        ("cuttlefish", "auto"): Variant(
            lunch="aosp_cf_x86_64_auto-trunk_staging-eng",
            make=_CUTTLEFISH_MAKE, artifacts="cuttlefish"),
        ("emulator", "phone"): Variant(
            lunch="sdk_phone64_x86_64-trunk_staging-eng",
            make=_EMULATOR_MAKE, artifacts="emulator"),
        # r74 has no x86_64 TV product for the emulator.
        ("emulator", "tv"): Variant(
            lunch="sdk_atv_x86-trunk_staging-eng",
            make=_EMULATOR_MAKE, artifacts="emulator",
            # sdk_atv_x86 is 32-bit. NetBpfLoad (tethering APEX) rejects
            # 32-bit userspace on 6.2+ kernels, so the default 6.6 of
            # goldfish reboots in a loop
            # (docs-ai/done-task/emulator-tv-boot-loop).
            env={"TARGET_KERNEL_USE": "6.1"}),
        ("emulator", "auto"): Variant(
            lunch="sdk_car_x86_64-trunk_staging-eng",
            make=_EMULATOR_MAKE, artifacts="emulator"),
    },
)

SPEC = VersionSpec(
    android="14",
    android_rpi_branch="arpi14-pi4",
    kernel_rpi_branch="arpi14-6.1.62",
    kernel_dist_dir="arpi14-6.1",
    kinds={"rpi": RPI, "generic": GENERIC},
)
