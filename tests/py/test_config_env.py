"""Tests for src/config_env.py (the resolved config in the container).

config_env.py runs with sys.executable, which is the python of the docker
image (3.8) with TEST_IN_IMAGE=1 bash tests/test-python.sh.
"""
from __future__ import annotations

import dataclasses
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

from aosp_build import ConfigError
from aosp_build.schema import SCHEMA, ResolvedConfig
from aosp_build.versions import (ARCHS, FORM_FACTORS, PLATFORMS, VERSIONS,
                                 resolve)
from helpers import REPODIR

SCRIPT = os.path.join(REPODIR, "src", "config_env.py")


def load_module():
    """config_env.py as a module, without aosp_build."""
    spec = importlib.util.spec_from_file_location("config_env", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def config(*args, **overrides) -> dict:
    data = dataclasses.asdict(ResolvedConfig(
        schema=SCHEMA, use_gen=True, container_srcdir="/mnt/aosp",
        record={"created": "x"}, **resolve(*args)))
    data.update(overrides)
    return data


class ConfigEnvTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def run_script(self, data):
        path = os.path.join(self.tmp.name, "config.json")
        with open(path, "w") as f:
            if isinstance(data, str):
                f.write(data)
            else:
                json.dump(data, f)
        r = subprocess.run([sys.executable, "-I", SCRIPT, path],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        return r.returncode, r.stdout, r.stderr

    def evaluated(self, data):
        """The variables after eval in bash: {name: (exported, value)}."""
        rc, out, err = self.run_script(data)
        self.assertEqual(rc, 0, err)
        script = ('set -eu\neval "$1"\n'
                  'for n in $(compgen -v); do\n'
                  '  if [[ -v $n ]]; then\n'
                  '    printf "%s\\0%s\\0%s\\0" "$n" '
                  '"$(declare -p $n | cut -d" " -f2)" "${!n}"\n'
                  '  fi\n'
                  'done\n')
        r = subprocess.run(["env", "-i", "PATH=/usr/bin:/bin", "bash", "-c",
                            script, "bash", out],
                           stdout=subprocess.PIPE, universal_newlines=True,
                           check=True)
        fields = r.stdout.split("\0")[:-1]
        return {fields[i]: ("x" in fields[i + 1], fields[i + 2])
                for i in range(0, len(fields), 3)}


class TestAssignments(ConfigEnvTestCase):
    def test_emulator_tv(self):
        v = self.evaluated(config("14", False, None, "emulator", "tv"))
        self.assertEqual(v["ANDROID_VERSION"], (True, "14"))
        self.assertEqual(v["ARG_ANDROID_VERSION"], (True, "14"))
        self.assertEqual(v["ARG_RPI"], (True, ""))
        self.assertEqual(v["ARG_ARCH"], (True, "x86_64"))
        self.assertEqual(v["ARG_PLATFORM"], (True, "emulator"))
        self.assertEqual(v["ARG_FORM_FACTOR"], (True, "tv"))
        self.assertEqual(v["ARG_NO_GEN"], (True, "false"))
        self.assertEqual(v["CONTAINER_SRCDIR"], (True, "/mnt/aosp"))
        self.assertEqual(v["BRANCH_AOSP_PLATFORM"],
                         (True, "android-14.0.0_r74"))
        self.assertEqual(v["BRANCH_ANDROID_RPI"], (True, "arpi14-pi4"))
        self.assertEqual(v["BRANCH_KERNEL_RPI"], (True, "arpi14-6.1.62"))
        self.assertEqual(v["KERNEL_DIST_DIR"], (False, "arpi14-6.1"))
        self.assertEqual(v["REPO_REV"][0], False)
        self.assertEqual(v["LUNCH_CHOICE"],
                         (False, "sdk_atv_x86-trunk_staging-eng"))
        self.assertEqual(v["OUTDIR_NAME"],
                         (False, "android-14-x86_64-emulator"))
        self.assertEqual(v["PYTHON2_AS_PYTHON"], (False, ""))
        # build_env
        self.assertEqual(v["ARCH"], (True, "x86_64"))
        self.assertEqual(v["ALLOW_NINJA_ENV"], (True, "1"))
        self.assertEqual(v["TARGET_KERNEL_USE"], (True, "6.1"))
        self.assertNotIn("CROSS_COMPILE", v)
        self.assertNotIn("SKIP_ABI_CHECKS", v)

    def test_rpi_14(self):
        v = self.evaluated(config("14", True, None))
        self.assertEqual(v["ARG_RPI"], (True, "rpi4"))
        self.assertEqual(v["CROSS_COMPILE"], (True, "aarch64-linux-gnu-"))
        self.assertEqual(v["SKIP_ABI_CHECKS"], (True, "true"))
        self.assertNotIn("TARGET_KERNEL_USE", v)

    def test_null_is_not_assigned(self):
        v = self.evaluated(config("10", False, None))
        self.assertNotIn("BRANCH_KERNEL_RPI", v)
        self.assertNotIn("KERNEL_DIST_DIR", v)
        self.assertNotIn("ALLOW_NINJA_ENV", v)
        self.assertEqual(v["PYTHON2_AS_PYTHON"], (False, "1"))
        self.assertEqual(v["ARG_ARCH"], (True, "arm"))
        self.assertEqual(v["ARCH"], (True, "arm"))

    def test_no_gen(self):
        v = self.evaluated(config("14", True, None, use_gen=False))
        self.assertEqual(v["ARG_NO_GEN"], (True, "true"))

    def test_quoted(self):
        tricky = "/mnt/a b/$(touch x)'\"`;"
        v = self.evaluated(config("14", True, None,
                                  container_srcdir=tricky))
        self.assertEqual(v["CONTAINER_SRCDIR"], (True, tricky))

    def test_unknown_keys_are_ignored(self):
        v = self.evaluated(config("14", True, None, follow_up="x"))
        self.assertEqual(v["ARG_RPI"], (True, "rpi4"))


class TestEveryCombination(unittest.TestCase):
    def test_every_resolved_config_is_accepted(self):
        """build_env of every combination passes the checks."""
        module = load_module()
        count = 0
        for v in VERSIONS:
            for rpi in (True, False):
                for arch in (None,) + ARCHS:
                    for platform in (None,) + PLATFORMS:
                        for form_factor in (None,) + FORM_FACTORS:
                            try:
                                data = config(v, rpi, arch, platform,
                                              form_factor)
                            except ConfigError:
                                continue
                            lines = module.assignments(data)
                            self.assertIn("export ARG_RPI=%s"
                                          % ("rpi4" if rpi else "''"), lines)
                            count += 1
        self.assertGreater(count, 100)


class TestErrors(ConfigEnvTestCase):
    def assertFails(self, data, message):
        rc, out, err = self.run_script(data)
        self.assertEqual(rc, 2)
        self.assertEqual(out, "")
        self.assertIn("error: Invalid resolved config", err)
        self.assertIn(message, err)

    def test_schema(self):
        self.assertFails(config("14", True, None, schema=2),
                         "unsupported schema: 2")
        self.assertFails(config("14", True, None, schema=True),
                         "unsupported schema: True")

    def test_missing_key(self):
        data = config("14", True, None)
        del data["lunch_choice"]
        self.assertFails(data, "missing key: lunch_choice")

    def test_types(self):
        self.assertFails(config("14", True, None, rpi="yes"),
                         "rpi must be a boolean")
        self.assertFails(config("14", True, None, arch=None),
                         "arch must be a string")
        self.assertFails(config("14", True, None, build_env=[]),
                         "build_env must be an object")
        self.assertFails(config("14", True, None, build_env={"A": 1}),
                         "build_env.A must be a string")

    def test_build_env_names(self):
        for name in ("a", "1A", "A-B", "A;B", "A B"):
            with self.subTest(name=name):
                self.assertFails(config("14", True, None,
                                        build_env={name: "1"}),
                                 "invalid name in build_env")
        for name in ("LUNCH_CHOICE", "SCRIPTDIR", "OUTDIR", "PATH",
                     "L_CONFIG_ENV", "BASH_ENV"):
            with self.subTest(name=name):
                self.assertFails(config("14", True, None,
                                        build_env={name: "x"}),
                                 "build_env overrides %s" % name)

    def test_not_json(self):
        self.assertFails("{", "")
        self.assertFails("[]", "not an object")

    def test_no_file(self):
        r = subprocess.run([sys.executable, "-I", SCRIPT,
                            os.path.join(self.tmp.name, "none.json")],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("Run the tasks by build-aosp.sh", r.stderr)


class TestCoverage(unittest.TestCase):
    def test_every_key_is_handled(self):
        """A new key of ResolvedConfig must be added to config_env.py."""
        module = load_module()
        handled = ({key for key, _, _, _ in module.VARIABLES}
                   | {module.BUILD_ENV} | set(module.IGNORED))
        keys = {f.name for f in dataclasses.fields(ResolvedConfig)}
        self.assertEqual(keys - handled, set())
        self.assertEqual(handled - keys, set())

    def test_schema(self):
        self.assertEqual(load_module().SCHEMA, SCHEMA)

    def test_nullable(self):
        module = load_module()
        hints = {f.name: str(f.type) for f in dataclasses.fields(
            ResolvedConfig)}
        optional = {k for k, t in hints.items() if t.startswith("Optional")}
        self.assertEqual(optional, set(module.NULLABLE))

    def test_no_aosp_build(self):
        with open(SCRIPT) as f:
            self.assertNotIn("aosp_build", f.read().split('"""', 2)[2])


if __name__ == "__main__":
    unittest.main()
