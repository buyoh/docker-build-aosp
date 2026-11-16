"""resolve() must give the same results as src/config/android-*.sh.

The shell configs are still sourced in the container. Remove this test when
they are removed (stage 3a of yaml-config-python-migration).
"""
from __future__ import annotations

import subprocess
import tempfile
import unittest

from aosp_build import ConfigError
from aosp_build.versions import VERSIONS, resolve
from helpers import REPODIR

VARS = ("ANDROID_VERSION", "BRANCH_AOSP_PLATFORM", "BRANCH_ANDROID_RPI",
        "BRANCH_KERNEL_RPI", "KERNEL_DIST_DIR", "ARCH", "CROSS_COMPILE",
        "ALLOW_NINJA_ENV", "LUNCH_CHOICE", "ARG_PLATFORM", "ARG_FORM_FACTOR")
UNSET = "<unset>"

SCRIPT = r'''
set -eu
ARG_RPI=$1
ARG_ARCH=$2
ARG_PLATFORM=$4
ARG_FORM_FACTOR=$5
# android-10.sh modifies /usr/bin/python for non-RPi.
ln() { L_LN="LN: $*"; }
source "$3" > /dev/null
for L_VAR in %s; do
  echo "$L_VAR=${!L_VAR-%s}"
done
if [[ -n "${L_LN-}" ]]; then echo "$L_LN"; fi
''' % (" ".join(VARS), UNSET)


# OUTDIR of src/preprocess.sh, which sources the config.
PREPROCESS = r'''
set -eu
export ARG_ANDROID_VERSION=$1 ARG_RPI=$2 ARG_ARCH=$3 ARG_PLATFORM=$4
export ARG_FORM_FACTOR=$5 ARG_NO_GEN=true CONTAINER_SRCDIR=$6
export TEST_MNT_OUT=$7
git() { :; }
ln() { :; }
source "$8/preprocess.sh" > /dev/null
echo "$OUTDIR"
'''


def run_preprocess(version, rpi, arch, platform, form_factor):
    with tempfile.TemporaryDirectory() as tmp:
        r = subprocess.run(
            ["env", "-i", "PATH=/usr/bin:/bin", "bash", "-c", PREPROCESS,
             "bash", version, rpi, arch, platform, form_factor, tmp,
             tmp + "/out", REPODIR + "/src"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True)
        return r.returncode, r.stdout.strip(), r.stderr, tmp + "/out"


def run_shell(version: str, rpi: str, arch: str, platform: str = "",
              form_factor: str = ""):
    r = subprocess.run(
        ["env", "-i", "PATH=/usr/bin:/bin", "bash", "-c", SCRIPT, "bash",
         rpi, arch, "%s/src/config/android-%s.sh" % (REPODIR, version),
         platform, form_factor],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True)
    return r.returncode, r.stdout, r.stderr


def expected_vars(r: dict) -> dict:
    def opt(v):
        return UNSET if v is None else v
    env = r["build_env"]
    return {
        "ANDROID_VERSION": r["android_version"],
        "BRANCH_AOSP_PLATFORM": r["aosp_branch"],
        "BRANCH_ANDROID_RPI": r["android_rpi_branch"],
        "BRANCH_KERNEL_RPI": opt(r["kernel_rpi_branch"]),
        "KERNEL_DIST_DIR": opt(r["kernel_dist_dir"]),
        "ARCH": r["arch"],
        "CROSS_COMPILE": env.get("CROSS_COMPILE", UNSET),
        "ALLOW_NINJA_ENV": env.get("ALLOW_NINJA_ENV", UNSET),
        "LUNCH_CHOICE": r["lunch_choice"],
        "ARG_PLATFORM": r["platform"],
        "ARG_FORM_FACTOR": r["form_factor"],
    }


class TestParity(unittest.TestCase):
    def test_all_combinations(self):
        for version in VERSIONS:
            for rpi in ("rpi4", ""):
                for arch in ("", "arm", "arm64", "x86_64", "aarch64"):
                    with self.subTest(version=version, rpi=rpi, arch=arch):
                        self.check(version, rpi, arch)

    def test_platform_and_form_factor(self):
        for version in VERSIONS:
            for rpi in ("rpi4", ""):
                for arch in ("", "arm64", "x86_64"):
                    for platform in ("", "rpi4", "cuttlefish", "emulator",
                                     "pc"):
                        for ff in ("", "phone", "tv", "auto", "wear"):
                            with self.subTest(version=version, rpi=rpi,
                                              arch=arch, platform=platform,
                                              form_factor=ff):
                                self.check(version, rpi, arch, platform, ff)

    def test_outdir(self):
        """OUTDIR of preprocess.sh == outdir_name() of resolve()."""
        for version in VERSIONS:
            for rpi in ("rpi4", ""):
                for platform in ("", "rpi4", "cuttlefish", "emulator"):
                    for ff in ("", "phone", "tv", "auto"):
                        try:
                            r = resolve(version, bool(rpi), None,
                                        platform or None, ff or None)
                        except ConfigError:
                            continue
                        with self.subTest(version=version, rpi=rpi,
                                          platform=platform,
                                          form_factor=ff):
                            rc, out, err, root = run_preprocess(
                                version, rpi, "", platform, ff)
                            self.assertEqual(rc, 0, err)
                            self.assertEqual(
                                out, root + "/" + r["outdir_name"])

    def check(self, version, rpi, arch, platform="", form_factor=""):
        rc, out, err = run_shell(version, rpi, arch, platform, form_factor)
        try:
            r = resolve(version, bool(rpi), arch or None, platform or None,
                        form_factor or None)
        except ConfigError as e:
            self.assertEqual(rc, 2, "the shell config succeeded: " + out)
            self.assertEqual(err.strip(), "error: %s" % e)
            return
        self.assertEqual(rc, 0, "the shell config failed: " + err)
        lines = out.splitlines()
        actual = dict(line.split("=", 1) for line in lines
                      if not line.startswith("LN: "))
        self.assertEqual(actual, expected_vars(r))
        ln = [line for line in lines if line.startswith("LN: ")]
        if r["python2_as_python"]:
            self.assertEqual(ln, ["LN: -sf /usr/bin/python2 /usr/bin/python"])
        else:
            self.assertEqual(ln, [])


if __name__ == "__main__":
    unittest.main()
