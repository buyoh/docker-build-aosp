"""The settings of each android version.

The values are in android_<version>.py, one file per version, as tables by
(platform, form factor). resolve() looks them up and checks the input. It
does not branch by the version nor by the combination
(docs-ai/done-task/build-config-single-source/04).

The container uses the result through the resolved config
(build-config-*.json, src/container/config_env.py). Add a value here, not in
the container. build_env is exported for the AOSP build as it is.
"""
from __future__ import annotations

from typing import Dict, Optional

from aosp_build import ConfigError
from aosp_build.versions import android_10, android_11, android_12, android_14
from aosp_build.versions.constants import (ARCHS, CROSS_COMPILE, FORM_FACTORS,
                                           PLATFORMS, REPO_REV)
from aosp_build.versions.types import PerArch, VersionSpec

__all__ = ["ARCHS", "FORM_FACTORS", "PLATFORMS", "REPO_REV", "VERSIONS",
           "resolve", "outdir_name"]

VERSIONS: Dict[str, VersionSpec] = {
    spec.android: spec
    for spec in (android_10.SPEC, android_11.SPEC, android_12.SPEC,
                 android_14.SPEC)
}


def _toolchain(arch: str) -> Dict[str, str]:
    env = {"ARCH": arch}
    if arch in CROSS_COMPILE:
        env["CROSS_COMPILE"] = CROSS_COMPILE[arch]
    return env


def _per_arch(value: PerArch, arch: str) -> str:
    return value[arch] if isinstance(value, dict) else value


def resolve(android: str, rpi: bool, arch: Optional[str],
            platform: Optional[str] = None,
            form_factor: Optional[str] = None) -> dict:
    """Resolve the version dependent values.

    platform and form_factor: None (or "") means the default.
    Raises ConfigError with a message for the user.
    """
    spec = VERSIONS.get(android)
    if spec is None:
        raise ConfigError(
            "The android version '%s' is not supported." % android)
    kind = spec.kinds["rpi" if rpi else "generic"]

    platform = platform or kind.default_platform
    form_factor = form_factor or kind.default_form_factor
    if platform not in PLATFORMS:
        raise ConfigError("unsupported platform: %s" % platform)
    if form_factor not in FORM_FACTORS:
        raise ConfigError("unsupported form factor: %s" % form_factor)
    if rpi != (platform == "rpi4"):
        # Not reachable from build-aosp.sh: --platform rpi4 implies --rpi.
        raise ConfigError("rpi and platform are inconsistent")
    message_args = dict(platform=platform, form_factor=form_factor,
                        default_platform=kind.default_platform,
                        default_form_factor=kind.default_form_factor)

    arch = arch or kind.default_arch
    if arch not in ARCHS:
        raise ConfigError("unsupported arch: %s" % arch)
    if arch not in kind.archs:
        assert kind.arch_error is not None, "no arch_error: %s" % android
        raise ConfigError(kind.arch_error.format(**message_args))

    variant = kind.variants.get((platform, form_factor))
    if variant is None:
        assert kind.combination_error is not None, \
            "no variant: %s %s/%s" % (android, platform, form_factor)
        raise ConfigError(kind.combination_error.format(**message_args))

    make = variant.make
    return dict(
        android_version=android,
        rpi=rpi,
        arch=arch,
        aosp_branch=kind.aosp_branch,
        repo_rev=REPO_REV,
        android_rpi_branch=spec.android_rpi_branch,
        kernel_rpi_branch=spec.kernel_rpi_branch,
        kernel_dist_dir=spec.kernel_dist_dir,
        platform=platform,
        form_factor=form_factor,
        lunch_choice=variant.lunch,
        aosp_make={"tool": make.tool, "parallel": make.parallel,
                   "targets": list(make.targets)},
        kernel_build=_per_arch(variant.kernel_build, arch),
        artifacts=_per_arch(variant.artifacts, arch),
        kernel_env=(_toolchain(arch) if variant.kernel_env_toolchain
                    else {}),
        # The environment variables exported for the AOSP build.
        build_env={**_toolchain(arch), **kind.env, **variant.env},
        python2_as_python=kind.python2_as_python,
        outdir_name=outdir_name(android, arch, platform, form_factor,
                                kind.default_platform,
                                kind.default_form_factor),
    )


def outdir_name(android: str, arch: str, platform: str, form_factor: str,
                platform_default: str, form_factor_default: str) -> str:
    """The subdirectory of outdir (OUTDIR of src/container/preprocess.sh).

    The default combination keeps the current name. Each axis that differs
    from the default adds a suffix.
    """
    name = "android-%s-%s" % (android, arch)
    if platform != platform_default:
        name += "-" + platform
    if form_factor != form_factor_default:
        name += "-" + form_factor
    return name
