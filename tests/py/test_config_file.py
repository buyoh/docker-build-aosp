"""Tests for aosp_build.config_file and aosp_build.fields."""
from __future__ import annotations

import os
import tempfile
import textwrap
import unittest

from aosp_build import ConfigError
from aosp_build.config_file import load
from aosp_build.fields import merge
from helpers import has_yaml


@unittest.skipUnless(has_yaml(), "PyYAML is not installed")
class TestLoad(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def load(self, text: str) -> dict:
        path = os.path.join(self.dir, "c.yaml")
        with open(path, "w") as f:
            f.write(textwrap.dedent(text))
        return load(path)

    def assertFails(self, text: str, pattern: str):
        with self.assertRaisesRegex(ConfigError, pattern):
            self.load(text)

    def test_all_keys(self):
        v = self.load("""
            schema: 1
            android: 14
            rpi: true
            arch: arm64
            workdir: /w
            outdir: /o
            gen: false
            mount_same: true
        """)
        self.assertEqual(v, {"android": "14", "rpi": True, "arch": "arm64",
                             "workdir": "/w", "outdir": "/o", "gen": False,
                             "mount_same": True})

    def test_android_int_and_str(self):
        self.assertEqual(self.load("schema: 1\nandroid: 14\n")["android"],
                         "14")
        self.assertEqual(self.load("schema: 1\nandroid: '14'\n")["android"],
                         "14")

    def test_android_float_and_bool(self):
        self.assertFails("schema: 1\nandroid: 14.0\n", "android")
        self.assertFails("schema: 1\nandroid: true\n", "android")

    def test_unknown_key(self):
        self.assertFails("schema: 1\nmount-same: true\n",
                         r"c\.yaml: mount-same: unknown key")

    def test_cli_only_keys(self):
        self.assertFails("schema: 1\ndaemon: true\n", "daemon.*command line")
        self.assertFails("schema: 1\nadduser: true\n", "adduser")

    def test_yaml11_bool_for_string(self):
        self.assertFails("schema: 1\narch: off\n", "arch")

    def test_string_for_bool(self):
        self.assertFails("schema: 1\ngen: 'yes'\n", "gen")
        self.assertFails("schema: 1\ngen: ''\n", "gen")

    def test_unhashable_key(self):
        self.assertFails("schema: 1\n? [a, b]\n: 1\n", "invalid YAML")

    def test_schema(self):
        self.assertFails("android: 14\n", "schema")
        self.assertFails("schema: 2\n", "schema")
        self.assertFails("schema: true\n", "schema")

    def test_arch_choices(self):
        self.assertFails("schema: 1\narch: aarch64\n", "unsupported arch")

    def test_relative_path(self):
        v = self.load("schema: 1\nworkdir: ../var\n")
        self.assertEqual(os.path.normpath(v["workdir"]),
                         os.path.normpath(os.path.join(self.dir, "../var")))

    def test_home(self):
        v = self.load("schema: 1\nworkdir: ~/var\n")
        self.assertEqual(v["workdir"], os.path.expanduser("~/var"))

    def test_null_is_unspecified(self):
        self.assertEqual(self.load("schema: 1\narch:\n"), {"arch": None})

    def test_top_level_list(self):
        self.assertFails("- schema: 1\n", "mapping")

    def test_unsafe_tag(self):
        self.assertFails("schema: 1\nx: !!python/object/apply:os.system "
                         "['true']\n", "invalid YAML")

    def test_duplicate_key(self):
        self.assertFails("schema: 1\nandroid: 14\nandroid: 12\n",
                         "duplicate key: 'android'")

    def test_empty_string_is_unspecified(self):
        self.assertEqual(self.load("schema: 1\nworkdir: ''\narch: ''\n"),
                         {"workdir": None, "arch": None})

    def test_missing_file(self):
        with self.assertRaisesRegex(ConfigError, "nonexistent"):
            load(os.path.join(self.dir, "nonexistent.yaml"))


class TestMerge(unittest.TestCase):
    def test_priority(self):
        v = merge({"arch": "arm", "gen": None},
                  {"arch": "arm64", "gen": False, "android": "14"})
        self.assertEqual(v["arch"], "arm")
        self.assertEqual(v["gen"], False)
        self.assertEqual(v["android"], "14")
        self.assertEqual(v["mount_same"], False)
        self.assertIsNone(v["workdir"])

    def test_cli_false_overrides_file(self):
        self.assertEqual(merge({"gen": True}, {"gen": False})["gen"], True)
        self.assertEqual(merge({"gen": False}, {"gen": True})["gen"], False)


if __name__ == "__main__":
    unittest.main()
