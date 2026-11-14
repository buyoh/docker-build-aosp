"""Tests for aosp_build.schema."""
from __future__ import annotations

import json
import unittest

from aosp_build import ConfigError
from aosp_build.schema import SCHEMA, ResolvedConfig
from aosp_build.versions import resolve


def sample() -> ResolvedConfig:
    return ResolvedConfig(schema=SCHEMA, use_gen=True,
                          container_srcdir="/mnt/aosp", record={},
                          **resolve("14", True, None))


class TestResolvedConfig(unittest.TestCase):
    def test_round_trip(self):
        c = sample()
        self.assertEqual(ResolvedConfig.from_json(c.to_json()), c)

    def mutate(self, f):
        data = json.loads(sample().to_json())
        f(data)
        return json.dumps(data)

    def test_schema_mismatch(self):
        text = self.mutate(lambda d: d.update(schema=2))
        with self.assertRaisesRegex(ConfigError, "schema"):
            ResolvedConfig.from_json(text)

    def test_unknown_field(self):
        text = self.mutate(lambda d: d.update(foo=1))
        with self.assertRaisesRegex(ConfigError, "foo"):
            ResolvedConfig.from_json(text)

    def test_missing_field(self):
        text = self.mutate(lambda d: d.pop("lunch_choice"))
        with self.assertRaisesRegex(ConfigError, "lunch_choice"):
            ResolvedConfig.from_json(text)

    def test_not_an_object(self):
        with self.assertRaises(ConfigError):
            ResolvedConfig.from_json("[]")


if __name__ == "__main__":
    unittest.main()
