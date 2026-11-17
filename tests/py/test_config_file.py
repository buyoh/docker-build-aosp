"""Tests for aosp_build.config_file and aosp_build.fields."""
from __future__ import annotations

import os
import tempfile
import textwrap
import unittest

from aosp_build import ConfigError
from aosp_build.config_file import load
from aosp_build.fields import merge
from helpers import REPODIR


class TestLoad(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def load_raw(self, text: str) -> dict:
        path = os.path.join(self.dir, "c.ini")
        with open(path, "w") as f:
            f.write(textwrap.dedent(text))
        return load(path)

    def load(self, body: str) -> dict:
        """Load body in the [build-aosp] section with schema = 1."""
        return self.load_raw("[build-aosp]\nschema = 1\n"
                             + textwrap.dedent(body))

    def assertFails(self, body: str, pattern: str):
        with self.assertRaisesRegex(ConfigError, pattern):
            self.load(body)

    def assertRawFails(self, text: str, pattern: str):
        with self.assertRaisesRegex(ConfigError, pattern):
            self.load_raw(text)

    def test_all_keys(self):
        v = self.load("""
            # comment
            ; comment
            android = 14
            rpi = true
              # indented comment
            arch = arm64  # inline comment
            workdir = /w#x
            outdir = /o ; inline comment
            gen = false
            mount_same = true
        """)
        self.assertEqual(v, {"android": "14", "rpi": True, "arch": "arm64",
                             "workdir": "/w#x", "outdir": "/o", "gen": False,
                             "mount_same": True})

    def test_example(self):
        with open(os.path.join(REPODIR, "build-aosp.example.ini")) as f:
            text = f.read()
        v = self.load_raw(text)
        self.assertEqual(v["android"], "14")
        self.assertIs(v["rpi"], True)
        self.assertIsNone(v["platform"])
        self.assertEqual(v["workdir"], os.path.expanduser("~/work/aosp/var"))

    def test_unknown_key(self):
        self.assertFails("mount-same = true\n",
                         r"c\.ini: mount-same: unknown key")

    def test_keys_are_case_sensitive(self):
        self.assertFails("Android = 14\n", "Android: unknown key")

    def test_cli_only_keys(self):
        self.assertFails("daemon = true\n", "daemon.*command line")
        self.assertFails("adduser = true\n", "adduser")

    def test_bool(self):
        self.assertFails("gen = yes\n", "gen: must be true or false")
        self.assertFails("gen = True\n", "gen: must be true or false")
        self.assertFails("gen = 1\n", "gen: must be true or false")

    def test_quoted_value(self):
        self.assertFails("arch = \"arm64\"\n", "arch: do not quote")
        self.assertFails("arch = 'arm64'\n", "arch: do not quote")

    def test_multi_line_value(self):
        self.assertFails("workdir = /a\n  /b\n", "workdir: must be a single")

    def test_percent_is_plain(self):
        self.assertEqual(self.load("workdir = /a%(x)s\n")["workdir"],
                         "/a%(x)s")

    def test_schema(self):
        self.assertRawFails("[build-aosp]\nandroid = 14\n",
                            "schema = 1 is required")
        self.assertRawFails("[build-aosp]\nschema = 2\n", "schema")
        self.assertRawFails("[build-aosp]\nschema = true\n", "schema")

    def test_section(self):
        self.assertRawFails("schema = 1\n", "not YAML")
        self.assertRawFails("", r"\[build-aosp\] section is required")
        self.assertRawFails("[build-aosp]\nschema = 1\n[run]\n",
                            r"\[run\]: unknown section")
        self.assertRawFails("[DEFAULT]\nschema = 1\n[build-aosp]\n",
                            r"\[DEFAULT\]: unknown section")

    def test_arch_choices(self):
        self.assertFails("arch = aarch64\n", "unsupported arch")

    def test_relative_path(self):
        v = self.load("workdir = ../var\n")
        self.assertEqual(os.path.normpath(v["workdir"]),
                         os.path.normpath(os.path.join(self.dir, "../var")))

    def test_home(self):
        v = self.load("workdir = ~/var\n")
        self.assertEqual(v["workdir"], os.path.expanduser("~/var"))

    def test_empty_is_unspecified(self):
        self.assertEqual(self.load("arch =\nworkdir =\ngen =\n"),
                         {"arch": None, "workdir": None, "gen": None})

    def test_no_value(self):
        self.assertFails("arch\n", r"c\.ini: expected 'key = value' at line 3$")

    def test_colon_is_not_a_separator(self):
        self.assertFails("arch: arm64\n", "expected 'key = value'")

    def test_yaml_file(self):
        self.assertRawFails("schema: 1\nandroid: 14\n",
                            r"c\.ini:1: .*\[build-aosp\].*not YAML")

    def test_duplicate_key(self):
        self.assertFails("android = 14\nandroid = 12\n",
                         r"c\.ini:4: android: duplicate key")

    def test_duplicate_section(self):
        self.assertRawFails("[build-aosp]\nschema = 1\n[build-aosp]\n",
                            r"c\.ini:3: \[build-aosp\]: duplicate section")

    def test_bom_and_crlf(self):
        path = os.path.join(self.dir, "c.ini")
        with open(path, "wb") as f:
            f.write(b"\xef\xbb\xbf[build-aosp]\r\nschema = 1\r\n"
                    b"gen = true \r\n")
        self.assertEqual(load(path), {"gen": True})

    def test_not_utf8(self):
        path = os.path.join(self.dir, "c.ini")
        with open(path, "wb") as f:
            f.write(b"[build-aosp]\nschema = 1\nworkdir = /\xff\n")
        with self.assertRaisesRegex(ConfigError, "not UTF-8"):
            load(path)

    def test_version_is_checked_later(self):
        # The loader does not know the versions. host.py rejects it.
        self.assertEqual(self.load("android = 14.0\n"), {"android": "14.0"})

    def test_missing_file(self):
        with self.assertRaisesRegex(ConfigError, "nonexistent"):
            load(os.path.join(self.dir, "nonexistent.ini"))


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
