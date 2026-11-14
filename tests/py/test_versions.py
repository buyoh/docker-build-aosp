"""Tests for aosp_build.versions (ported from tests/test-config.sh)."""
from __future__ import annotations

import re
import unittest

from aosp_build import ConfigError
from aosp_build.versions import REPO_REV, VERSIONS, resolve
from helpers import REPODIR


class TestConfig(unittest.TestCase):
    def test_kernel_branch_and_dist(self):
        r = resolve("14", True, None)
        self.assertEqual(r["kernel_rpi_branch"], "arpi14-6.1.62")
        self.assertEqual(r["kernel_dist_dir"], "arpi14-6.1")
        r = resolve("12", True, None)
        self.assertEqual(r["kernel_rpi_branch"], "arpi-5.10")
        self.assertEqual(r["kernel_dist_dir"], "arpi-5.10")

    def test_lunch(self):
        self.assertEqual(resolve("14", True, None)["lunch_choice"],
                         "rpi4_tv-userdebug")
        self.assertEqual(resolve("14", False, "x86_64")["lunch_choice"],
                         "aosp_cf_x86_64_tv-trunk_staging-eng")
        for v in ("10", "11", "12"):
            self.assertEqual(resolve(v, True, None)["lunch_choice"],
                             "rpi4-eng")
            self.assertEqual(resolve(v, False, "x86_64")["lunch_choice"],
                             "aosp_x86_64-eng")

    def test_arch(self):
        self.assertEqual(resolve("14", True, None)["arch"], "arm64")
        self.assertEqual(resolve("10", True, None)["arch"], "arm")
        self.assertEqual(resolve("10", True, "arm")["arch"], "arm")
        self.assertEqual(resolve("11", True, "arm")["arch"], "arm")
        self.assertEqual(resolve("10", False, "x86_64")["arch"], "x86_64")

    def test_invalid_arch(self):
        for v in ("10", "11", "12", "14"):
            with self.assertRaisesRegex(ConfigError, "unsupported arch"):
                resolve(v, True, "aarch64")
        cases = [("12", "arm"), ("14", "arm"), ("10", "x86_64"),
                 ("11", "x86_64"), ("14", "x86_64")]
        for v, arch in cases:
            with self.assertRaises(ConfigError):
                resolve(v, True, arch)

    def test_unsupported_version(self):
        with self.assertRaisesRegex(ConfigError, "'13' is not supported"):
            resolve("13", True, None)

    def test_outdir_name(self):
        self.assertEqual(resolve("14", True, None)["outdir_name"],
                         "android-14-arm64")


class TestBuildKinds(unittest.TestCase):
    """The version dependent branches of src/build.sh."""

    def test_rpi_14(self):
        r = resolve("14", True, None)
        self.assertEqual(r["aosp_make"], {
            "tool": "m", "parallel": True,
            "targets": ["ramdisk", "systemimage", "vendorimage"]})
        self.assertEqual(r["kernel_build"], "build.sh")
        self.assertEqual(r["artifacts"], "rpi-kernel-dist")
        self.assertEqual(r["kernel_env"], {})
        self.assertEqual(r["build_env"], {
            "ARCH": "arm64", "CROSS_COMPILE": "aarch64-linux-gnu-",
            "ALLOW_NINJA_ENV": "1", "SKIP_ABI_CHECKS": "true"})

    def test_rpi_12(self):
        r = resolve("12", True, None)
        self.assertEqual(r["aosp_make"]["tool"], "make")
        self.assertEqual(r["kernel_build"], "build.sh")
        self.assertNotIn("SKIP_ABI_CHECKS", r["build_env"])

    def test_rpi_11(self):
        for arch in ("arm", "arm64"):
            r = resolve("11", True, arch)
            self.assertEqual(r["aosp_make"]["tool"], "make")
            self.assertEqual(r["kernel_build"], "make-" + arch)
            self.assertEqual(r["artifacts"], "rpi-kernel-" + arch)
            self.assertEqual(r["kernel_env"]["ARCH"], arch)
            self.assertIn("CROSS_COMPILE", r["kernel_env"])
            self.assertNotIn("ALLOW_NINJA_ENV", r["build_env"])

    def test_generic(self):
        r = resolve("14", False, "x86_64")
        self.assertEqual(r["aosp_make"],
                         {"tool": "m", "parallel": False, "targets": []})
        self.assertEqual(r["kernel_build"], "none")
        self.assertEqual(r["artifacts"], "none")
        self.assertEqual(r["build_env"],
                         {"ARCH": "x86_64", "ALLOW_NINJA_ENV": "1"})
        self.assertEqual(r["aosp_branch"], "android-14.0.0_r74")

    def test_python2(self):
        self.assertTrue(resolve("10", False, "x86_64")["python2_as_python"])
        self.assertFalse(resolve("10", True, None)["python2_as_python"])
        self.assertFalse(resolve("11", False, "x86_64")["python2_as_python"])


class TestStatic(unittest.TestCase):
    def test_repo_rev_matches_fetch_sh(self):
        with open(REPODIR + "/src/fetch.sh") as f:
            m = re.search(r"^REPO_REV=(\S+)$", f.read(), re.M)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(1), REPO_REV)

    def test_kernel_branches_are_defined_for_12_and_later(self):
        for v, d in VERSIONS.items():
            if int(v) >= 12:
                self.assertTrue(d["kernel_rpi_branch"])
                self.assertTrue(d["kernel_dist_dir"])


if __name__ == "__main__":
    unittest.main()
