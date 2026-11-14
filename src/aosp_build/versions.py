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
        lunch={"rpi": "rpi4_tv-userdebug",
               "generic": "aosp_cf_x86_64_tv-trunk_staging-eng"},
        env={"ALLOW_NINJA_ENV": "1"},
        python2_as_python=False,
    ),
}


def resolve(android: str, rpi: bool, arch: Optional[str]) -> dict:
    """Resolve the version dependent values.

    Raises ConfigError with the same message as src/config/android-*.sh.
    """
    if android not in VERSIONS:
        raise ConfigError(
            "The android version '%s' is not supported." % android)
    v = VERSIONS[android]
    kind = "rpi" if rpi else "generic"
    version = int(android)

    if not arch:
        arch = v["default_arch"]
    if arch not in ARCHS:
        raise ConfigError("unsupported arch: %s" % arch)
    if rpi and arch not in v["rpi_archs"]:
        raise ConfigError(v["rpi_archs_error"])

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
        artifacts = "none"
        kernel_env = {}

    if rpi:
        aosp_make = {"tool": "m" if version >= 14 else "make",
                     "parallel": True, "targets": list(_RPI_TARGETS)}
    else:
        aosp_make = {"tool": "m", "parallel": False, "targets": []}

    # The environment variables exported for the AOSP build so far.
    build_env = dict(toolchain)
    build_env.update(v["env"])
    if rpi and version == 14:
        # The prebuilt ABI reference dump of libcrypto mismatches the build.
        build_env["SKIP_ABI_CHECKS"] = "true"

    return dict(
        android_version=android,
        rpi=rpi,
        arch=arch,
        aosp_branch=v["aosp_branch"][kind],
        repo_rev=REPO_REV,
        android_rpi_branch=v["android_rpi_branch"],
        kernel_rpi_branch=v["kernel_rpi_branch"],
        kernel_dist_dir=v["kernel_dist_dir"],
        lunch_choice=v["lunch"][kind],
        aosp_make=aosp_make,
        kernel_build=kernel_build,
        artifacts=artifacts,
        kernel_env=kernel_env,
        build_env=build_env,
        python2_as_python=v["python2_as_python"] and not rpi,
        outdir_name="android-%s-%s" % (android, arch),
    )
