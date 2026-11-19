"""Tests for aosp_build.versions (src/aosp_build/versions/)."""
from __future__ import annotations

import re
import unittest

from aosp_build import ConfigError
from aosp_build.versions import (ARCHS, FORM_FACTORS, PLATFORMS, REPO_REV,
                                 VERSIONS, resolve)
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
        self.assertEqual(r["aosp_make"], {"tool": "m", "parallel": False,
                                          "targets": ["droid", "hosttar"]})
        self.assertEqual(r["kernel_build"], "none")
        self.assertEqual(r["artifacts"], "cuttlefish")
        self.assertEqual(r["build_env"],
                         {"ARCH": "x86_64", "ALLOW_NINJA_ENV": "1"})
        self.assertEqual(r["aosp_branch"], "android-14.0.0_r74")

    def test_python2(self):
        self.assertTrue(resolve("10", False, "x86_64")["python2_as_python"])
        self.assertFalse(resolve("10", True, None)["python2_as_python"])
        self.assertFalse(resolve("11", False, "x86_64")["python2_as_python"])


class TestPlatformAndFormFactor(unittest.TestCase):
    """--platform / --form-factor (form-factor-and-run-targets/01)."""

    LUNCH = {
        ("cuttlefish", "phone"): "aosp_cf_x86_64_phone-trunk_staging-eng",
        ("cuttlefish", "tv"): "aosp_cf_x86_64_tv-trunk_staging-eng",
        ("cuttlefish", "auto"): "aosp_cf_x86_64_auto-trunk_staging-eng",
        ("emulator", "phone"): "sdk_phone64_x86_64-trunk_staging-eng",
        ("emulator", "tv"): "sdk_atv_x86-trunk_staging-eng",
        ("emulator", "auto"): "sdk_car_x86_64-trunk_staging-eng",
    }

    def test_14_non_rpi_default(self):
        r = resolve("14", False, None)
        self.assertEqual(r["lunch_choice"],
                         "aosp_cf_x86_64_tv-trunk_staging-eng")
        self.assertEqual((r["platform"], r["form_factor"], r["arch"]),
                         ("cuttlefish", "tv", "x86_64"))
        self.assertEqual(r["outdir_name"], "android-14-x86_64")

    def test_14_non_rpi_table(self):
        for (platform, ff), lunch in self.LUNCH.items():
            with self.subTest(platform=platform, form_factor=ff):
                r = resolve("14", False, None, platform, ff)
                self.assertEqual(r["lunch_choice"], lunch)
                self.assertTrue(r["lunch_choice"].endswith("-eng"))
                self.assertEqual(r["arch"], "x86_64")
                self.assertEqual(r["artifacts"], platform)

    def test_14_emulator_tv_kernel(self):
        """Only the 32-bit emulator TV uses the 6.1 kernel
        (emulator-tv-boot-loop)."""
        r = resolve("14", False, None, "emulator", "tv")
        self.assertEqual(r["build_env"]["TARGET_KERNEL_USE"], "6.1")
        self.assertEqual(r["build_env"],
                         {"ARCH": "x86_64", "ALLOW_NINJA_ENV": "1",
                          "TARGET_KERNEL_USE": "6.1"})
        others = [("14", False, "emulator", "phone"),
                  ("14", False, "emulator", "auto"),
                  ("14", False, "cuttlefish", "tv"),
                  ("14", True, "rpi4", "tv")]
        others += [(v, rpi, None, None) for v in ("10", "11", "12")
                   for rpi in (True, False)]
        for version, rpi, platform, ff in others:
            with self.subTest(version=version, rpi=rpi, platform=platform,
                              form_factor=ff):
                r = resolve(version, rpi, None, platform, ff)
                self.assertNotIn("TARGET_KERNEL_USE", r["build_env"])

    def test_14_make_targets(self):
        self.assertEqual(
            resolve("14", False, None, "emulator")["aosp_make"]["targets"],
            ["droid", "emu_img_zip"])
        self.assertEqual(
            resolve("14", False, None, "cuttlefish")["aosp_make"]["targets"],
            ["droid", "hosttar"])

    def test_14_non_rpi_arch(self):
        self.assertEqual(resolve("14", False, "x86_64")["arch"], "x86_64")
        for arch in ("arm", "arm64"):
            with self.assertRaisesRegex(ConfigError,
                                        "for cuttlefish supports only x86_64"):
                resolve("14", False, arch)
        with self.assertRaisesRegex(ConfigError,
                                    "for emulator supports only x86_64"):
            resolve("14", False, "arm64", "emulator")

    def test_14_rpi(self):
        for ff in (None, "tv"):
            r = resolve("14", True, None, None, ff)
            self.assertEqual(r["lunch_choice"], "rpi4_tv-userdebug")
            self.assertEqual(r["platform"], "rpi4")
            self.assertEqual(r["outdir_name"], "android-14-arm64")
        self.assertEqual(resolve("14", True, None, "rpi4")["lunch_choice"],
                         "rpi4_tv-userdebug")

    def test_14_rpi_phone_and_auto(self):
        for ff in ("phone", "auto"):
            with self.assertRaisesRegex(
                    ConfigError, "RPi supports only form factor: tv.*"
                    "cuttlefish or emulator for %s.*another --workdir" % ff):
                resolve("14", True, None, None, ff)

    def test_inconsistent_rpi_and_platform(self):
        with self.assertRaisesRegex(ConfigError, "inconsistent"):
            resolve("14", True, None, "cuttlefish")
        with self.assertRaisesRegex(ConfigError, "inconsistent"):
            resolve("14", False, None, "rpi4")

    def test_unknown_values(self):
        with self.assertRaisesRegex(ConfigError, "unsupported platform: pc"):
            resolve("14", False, None, "pc")
        with self.assertRaisesRegex(ConfigError,
                                    "unsupported form factor: wear"):
            resolve("14", False, None, None, "wear")
        # The form factor is checked before the platform specific table.
        with self.assertRaisesRegex(ConfigError,
                                    "unsupported form factor: wear"):
            resolve("14", True, None, None, "wear")

    def test_10_to_12(self):
        for v in ("10", "11", "12"):
            with self.subTest(version=v):
                r = resolve(v, False, "x86_64")
                self.assertEqual((r["platform"], r["form_factor"]),
                                 ("emulator", "phone"))
                self.assertEqual(r["lunch_choice"], "aosp_x86_64-eng")
                self.assertEqual(r["artifacts"], "none")
                self.assertEqual(r["aosp_make"]["targets"], [])
                self.assertEqual(r["outdir_name"], "android-%s-x86_64" % v)
                r = resolve(v, False, "x86_64", "emulator", "phone")
                self.assertEqual(r["lunch_choice"], "aosp_x86_64-eng")
                r = resolve(v, True, None, "rpi4", "tv")
                self.assertEqual(r["lunch_choice"], "rpi4-eng")

    def test_10_to_12_other_values(self):
        cases = [(False, "cuttlefish", None, "emulator/phone"),
                 (False, None, "tv", "emulator/phone"),
                 (False, None, "auto", "emulator/phone"),
                 (True, None, "phone", "rpi4/tv")]
        for v in ("10", "11", "12"):
            for rpi, platform, ff, supported in cases:
                with self.subTest(version=v, platform=platform, ff=ff):
                    with self.assertRaisesRegex(
                            ConfigError, "Android %s supports only %s"
                            % (v, supported)):
                        resolve(v, rpi, None if rpi else "x86_64",
                                platform, ff)

    def test_outdir_name(self):
        cases = [
            (("14", True, None, None, None), "android-14-arm64"),
            (("14", False, None, None, None), "android-14-x86_64"),
            (("14", False, None, "cuttlefish", "tv"), "android-14-x86_64"),
            (("14", False, None, None, "auto"), "android-14-x86_64-auto"),
            (("14", False, None, "emulator", None),
             "android-14-x86_64-emulator"),
            (("14", False, None, "emulator", "auto"),
             "android-14-x86_64-emulator-auto"),
            (("12", False, "x86_64", None, None), "android-12-x86_64"),
        ]
        for args, name in cases:
            with self.subTest(args=args):
                self.assertEqual(resolve(*args)["outdir_name"], name)


class TestStatic(unittest.TestCase):
    def test_fetch_sh_uses_repo_rev_of_the_config(self):
        # REPO_REV comes from the resolved config (src/config_env.py).
        with open(REPODIR + "/src/fetch.sh") as f:
            text = f.read()
        self.assertNotRegex(text, r"(?m)^\s*REPO_REV=")
        self.assertIn("--repo-rev=$REPO_REV", text)
        self.assertRegex(REPO_REV, r"^v\d+\.\d+")

    def test_tables_are_consistent(self):
        """The tables in src/aosp_build/versions/android_*.py."""
        for v, spec in VERSIONS.items():
            self.assertEqual(spec.android, v)
            self.assertEqual(sorted(spec.kinds), ["generic", "rpi"])
            for name, kind in spec.kinds.items():
                with self.subTest(version=v, kind=name):
                    rpi = name == "rpi"
                    self.assertIn(kind.default_arch, kind.archs)
                    self.assertTrue(set(kind.archs) <= set(ARCHS))
                    self.assertEqual(kind.arch_error is None,
                                     set(kind.archs) == set(ARCHS))
                    self.assertIn((kind.default_platform,
                                   kind.default_form_factor), kind.variants)
                    # The combinations that pass the rpi/platform check.
                    allowed = {(p, f) for p in PLATFORMS
                               for f in FORM_FACTORS
                               if (p == "rpi4") == rpi}
                    self.assertTrue(set(kind.variants) <= allowed)
                    if kind.combination_error is None:
                        self.assertEqual(set(kind.variants), allowed)
                    for key, variant in kind.variants.items():
                        for value in (variant.kernel_build,
                                      variant.artifacts):
                            if isinstance(value, dict):
                                self.assertEqual(set(value),
                                                 set(kind.archs), key)
                        self.assertFalse(set(kind.env) & set(variant.env),
                                         key)
                        self.assertFalse(
                            {"ARCH", "CROSS_COMPILE"}
                            & (set(kind.env) | set(variant.env)), key)
                        self.assertIsInstance(variant.make.targets, tuple)

    def test_result_does_not_share_the_tables(self):
        r = resolve("14", False, None, "emulator", "tv")
        r["build_env"]["X"] = "1"
        r["aosp_make"]["targets"].append("x")
        r2 = resolve("14", False, None, "emulator", "tv")
        self.assertNotIn("X", r2["build_env"])
        self.assertEqual(r2["aosp_make"]["targets"], ["droid", "emu_img_zip"])
        r = resolve("10", True, "arm")
        r["kernel_env"]["X"] = "1"
        self.assertNotIn("X", resolve("10", True, "arm")["kernel_env"])

    def test_combination_is_checked_after_arch(self):
        # 04: the same order for every version.
        with self.assertRaisesRegex(ConfigError, "supports only arm and"):
            resolve("10", True, "x86_64", None, "phone")
        with self.assertRaisesRegex(ConfigError, "supports only rpi4/tv"):
            resolve("10", True, "arm", None, "phone")
        with self.assertRaisesRegex(ConfigError,
                                    "supports only emulator/phone"):
            resolve("12", False, "x86_64", None, "tv")

    def test_kernel_branches_are_defined_for_12_and_later(self):
        for v, spec in VERSIONS.items():
            if int(v) >= 12:
                self.assertTrue(spec.kernel_rpi_branch)
                self.assertTrue(spec.kernel_dist_dir)


if __name__ == "__main__":
    unittest.main()
