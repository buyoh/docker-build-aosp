"""The table of the android versions.

Ported from src/config/android-*.sh and the version dependent branches of
src/build.sh. Until the tasks in the container are ported to python, the
shell configs are still used in the container, and
tests/py/test_versions_parity.py checks that both give the same results.
"""
from __future__ import annotations

from typing import Optional

from aosp_build import ConfigError

# The version of the repo tool itself (src/fetch.sh).
REPO_REV = "v2.55.1"

ARCHS = ("arm", "arm64", "x86_64")
PLATFORMS = ("rpi4", "cuttlefish", "emulator")
FORM_FACTORS = ("phone", "tv", "auto")

# The lunch targets of Android 14 by (platform, form factor).
# The non-RPi tree is r74, so the release config is required. All non-RPi
# variants are eng to avoid relinking (docs-ai/info/form-factor-build/05).
LUNCH_14 = {
    ("rpi4", "tv"): "rpi4_tv-userdebug",
    ("cuttlefish", "phone"): "aosp_cf_x86_64_phone-trunk_staging-eng",
    ("cuttlefish", "tv"): "aosp_cf_x86_64_tv-trunk_staging-eng",
    ("cuttlefish", "auto"): "aosp_cf_x86_64_auto-trunk_staging-eng",
    ("emulator", "phone"): "sdk_phone64_x86_64-trunk_staging-eng",
    # r74 has no x86_64 TV product for the emulator.
    ("emulator", "tv"): "sdk_atv_x86-trunk_staging-eng",
    ("emulator", "auto"): "sdk_car_x86_64-trunk_staging-eng",
}

# The make targets of the non-RPi Android 14 build by platform. Keep them the
# same as src/build.sh (tests/test-build.sh checks the shell side).
GENERIC_14_TARGETS = {
    "cuttlefish": ["droid", "hosttar"],
    "emulator": ["droid", "emu_img_zip"],
}
# The kernel of the emulator TV (TARGET_KERNEL_USE). sdk_atv_x86 is 32-bit,
# and NetBpfLoad (tethering APEX) rejects 32-bit userspace on 6.2+ kernels,
# so the default 6.6 of goldfish reboots in a loop
# (docs-ai/done-task/emulator-tv-boot-loop). Keep it the same as
# src/config/android-14.sh.
EMULATOR_TV_KERNEL = "6.1"
CROSS_COMPILE = {"arm": "arm-linux-gnueabihf-", "arm64": "aarch64-linux-gnu-"}

_RPI_TARGETS = ("ramdisk", "systemimage", "vendorimage")

VERSIONS = {
    "10": dict(
        aosp_branch={"rpi": "android-10.0.0_r41",
                     "generic": "android-10.0.0_r41"},
        android_rpi_branch="arpi-10",
        kernel_rpi_branch=None,
        kernel_dist_dir=None,
        default_arch="arm",
        rpi_archs=("arm", "arm64"),
        rpi_archs_error="Android 10 for RPi supports only arm and arm64.",
        lunch={"rpi": "rpi4-eng", "generic": "aosp_x86_64-eng"},
        env={},
        python2_as_python=True,
    ),
    "11": dict(
        aosp_branch={"rpi": "android-11.0.0_r37",
                     "generic": "android-11.0.0_r37"},
        android_rpi_branch="arpi-11",
        kernel_rpi_branch=None,
        kernel_dist_dir=None,
        default_arch="arm64",
        rpi_archs=("arm", "arm64"),
        rpi_archs_error="Android 11 for RPi supports only arm and arm64.",
        lunch={"rpi": "rpi4-eng", "generic": "aosp_x86_64-eng"},
        env={},
        python2_as_python=False,
    ),
    "12": dict(
        aosp_branch={"rpi": "android-12.1.0_r21",
                     "generic": "android-12.1.0_r21"},
        android_rpi_branch="arpi-12",
        kernel_rpi_branch="arpi-5.10",
        # out/<BRANCH>/dist of the kernel. BRANCH is defined in build.config.
        kernel_dist_dir="arpi-5.10",
        default_arch="arm64",
        # The kernel and lunch target decide the actual arch since Android 12.
        rpi_archs=("arm64",),
        rpi_archs_error="Android 12 for RPi supports only arm64.",
        lunch={"rpi": "rpi4-eng", "generic": "aosp_x86_64-eng"},
        env={"ALLOW_NINJA_ENV": "1"},
        python2_as_python=False,
    ),
    "14": dict(
        # https://github.com/android-rpi/local_manifests/tree/arpi14-pi4
        aosp_branch={"rpi": "android-14.0.0_r17",
                     "generic": "android-14.0.0_r74"},
        android_rpi_branch="arpi14-pi4",
        kernel_rpi_branch="arpi14-6.1.62",
        kernel_dist_dir="arpi14-6.1",
        default_arch="arm64",
        rpi_archs=("arm64",),
        rpi_archs_error="Android 14 for RPi supports only arm64.",
        # The lunch targets of 14 are in LUNCH_14.
        env={"ALLOW_NINJA_ENV": "1"},
        python2_as_python=False,
    ),
}


def _platform_and_form_factor(android: str, rpi: bool,
                              platform: Optional[str],
                              form_factor: Optional[str]) -> tuple:
    """Return (platform, form factor, platform default, form factor default).

    The same checks in the same order as src/config/android-*.sh.
    """
    version = int(android)
    if rpi:
        platform_default = "rpi4"
    elif version >= 14:
        platform_default = "cuttlefish"
    else:
        # aosp_x86_64 of Android 10-12 is goldfish (the Android Emulator).
        platform_default = "emulator"
    form_factor_default = "tv" if rpi or version >= 14 else "phone"
    platform = platform or platform_default
    form_factor = form_factor or form_factor_default
    if platform not in PLATFORMS:
        raise ConfigError("unsupported platform: %s" % platform)
    if form_factor not in FORM_FACTORS:
        raise ConfigError("unsupported form factor: %s" % form_factor)
    if rpi != (platform == "rpi4"):
        raise ConfigError("ARG_RPI and ARG_PLATFORM are inconsistent")
    if version < 14 and (platform != platform_default
                         or form_factor != form_factor_default):
        raise ConfigError("Android %s supports only %s/%s"
                          % (android, platform_default, form_factor_default))
    return platform, form_factor, platform_default, form_factor_default


def resolve(android: str, rpi: bool, arch: Optional[str],
            platform: Optional[str] = None,
            form_factor: Optional[str] = None) -> dict:
    """Resolve the version dependent values.

    platform and form_factor: None (or "") means the default.
    Raises ConfigError with the same message as src/config/android-*.sh.
    """
    if android not in VERSIONS:
        raise ConfigError(
            "The android version '%s' is not supported." % android)
    v = VERSIONS[android]
    kind = "rpi" if rpi else "generic"
    version = int(android)

    platform, form_factor, platform_default, form_factor_default = \
        _platform_and_form_factor(android, rpi, platform, form_factor)

    generic_14 = not rpi and version >= 14
    if not arch:
        arch = "x86_64" if generic_14 else v["default_arch"]
    if arch not in ARCHS:
        raise ConfigError("unsupported arch: %s" % arch)
    if rpi and arch not in v["rpi_archs"]:
        raise ConfigError(v["rpi_archs_error"])
    if generic_14 and arch != "x86_64":
        # The lunch targets are always x86. Do not build x86_64 in
        # gen/out.arm64.
        raise ConfigError("Android %s for %s supports only x86_64."
                          % (android, platform))

    if version >= 14:
        lunch_choice = LUNCH_14.get((platform, form_factor))
        if lunch_choice is None:
            # Only rpi4/phone and rpi4/auto reach here.
            raise ConfigError(
                "Android %s for RPi supports only form factor: tv. Use "
                "--platform cuttlefish or emulator for %s with another "
                "--workdir (the AOSP tag differs from RPi)."
                % (android, form_factor))
    else:
        lunch_choice = v["lunch"][kind]

    toolchain = {"ARCH": arch}
    if arch in CROSS_COMPILE:
        toolchain["CROSS_COMPILE"] = CROSS_COMPILE[arch]

    if rpi and version <= 11:
        kernel_build = "make-" + arch
        artifacts = "rpi-kernel-" + arch
        kernel_env = dict(toolchain)
    elif rpi:
        kernel_build = "build.sh"
        artifacts = "rpi-kernel-dist"
        kernel_env = {}
    else:
        kernel_build = "none"
        # The artifacts of cuttlefish or emulator (src/build.sh). Android
        # 10-12 copy nothing.
        artifacts = platform if generic_14 else "none"
        kernel_env = {}

    if rpi:
        aosp_make = {"tool": "m" if version >= 14 else "make",
                     "parallel": True, "targets": list(_RPI_TARGETS)}
    elif generic_14:
        aosp_make = {"tool": "m", "parallel": False,
                     "targets": list(GENERIC_14_TARGETS[platform])}
    else:
        aosp_make = {"tool": "m", "parallel": False, "targets": []}

    # The environment variables exported for the AOSP build so far.
    build_env = dict(toolchain)
    build_env.update(v["env"])
    if rpi and version == 14:
        # The prebuilt ABI reference dump of libcrypto mismatches the build.
        build_env["SKIP_ABI_CHECKS"] = "true"
    if version == 14 and (platform, form_factor) == ("emulator", "tv"):
        build_env["TARGET_KERNEL_USE"] = EMULATOR_TV_KERNEL

    return dict(
        android_version=android,
        rpi=rpi,
        arch=arch,
        aosp_branch=v["aosp_branch"][kind],
        repo_rev=REPO_REV,
        android_rpi_branch=v["android_rpi_branch"],
        kernel_rpi_branch=v["kernel_rpi_branch"],
        kernel_dist_dir=v["kernel_dist_dir"],
        platform=platform,
        form_factor=form_factor,
        lunch_choice=lunch_choice,
        aosp_make=aosp_make,
        kernel_build=kernel_build,
        artifacts=artifacts,
        kernel_env=kernel_env,
        build_env=build_env,
        python2_as_python=v["python2_as_python"] and not rpi,
        outdir_name=outdir_name(android, arch, platform, form_factor,
                                platform_default, form_factor_default),
    )


def outdir_name(android: str, arch: str, platform: str, form_factor: str,
                platform_default: str, form_factor_default: str) -> str:
    """The subdirectory of outdir. The same as OUTDIR of src/preprocess.sh
    (tests/py/test_versions_parity.py).

    The default combination keeps the current name. Each axis that differs
    from the default adds a suffix.
    """
    name = "android-%s-%s" % (android, arch)
    if platform != platform_default:
        name += "-" + platform
    if form_factor != form_factor_default:
        name += "-" + form_factor
    return name
