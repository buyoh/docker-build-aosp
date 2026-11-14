"""The parameters (FIELDS) and their documents must be consistent."""
from __future__ import annotations

import unittest

from aosp_build.config_file import load
from aosp_build.fields import DEFAULTS, FIELDS
from aosp_build.host import build_parser
from helpers import REPODIR, has_yaml


class TestFields(unittest.TestCase):
    def test_defaults_cover_fields(self):
        self.assertEqual(set(DEFAULTS), {f.key for f in FIELDS})

    def test_options(self):
        parser = build_parser()
        options = {o for a in parser._actions for o in a.option_strings}
        for f in FIELDS:
            if f.cli:
                self.assertIn(f.cli, options)
            if f.cli_negate:
                self.assertIn(f.cli_negate, options)
                self.assertEqual(f.type, "bool")

    def test_negate_option(self):
        args = build_parser().parse_intermixed_args(["--no-gen"])
        self.assertIs(args.gen, False)
        args = build_parser().parse_intermixed_args([])
        self.assertIsNone(args.gen)

    @unittest.skipUnless(has_yaml(), "PyYAML is not installed")
    def test_example_describes_all_keys(self):
        values = load(REPODIR + "/build-aosp.example.yaml")
        self.assertEqual(set(values), {f.key for f in FIELDS if f.in_file})


if __name__ == "__main__":
    unittest.main()
