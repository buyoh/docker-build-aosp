"""Static checks for the python code."""
from __future__ import annotations

import ast
import glob
import os
import re
import unittest

from helpers import REPODIR

SOURCES = sorted(glob.glob(REPODIR + "/src/**/*.py", recursive=True))
# The code that must not change the environment of the tool itself.
ENV_SOURCES = [p for p in SOURCES
               if "/aosp_build/" in p or p.endswith("/container_main.py")]
# The scripts the user runs. Each must be a wrapper of a python script.
WRAPPERS = ["build-aosp.sh"]


def rel(path: str) -> str:
    return os.path.relpath(path, REPODIR)


def read(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def is_os_environ(node) -> bool:
    return (isinstance(node, ast.Attribute) and node.attr == "environ"
            and isinstance(node.value, ast.Name) and node.value.id == "os")


class TestStatic(unittest.TestCase):
    def test_sources_exist(self):
        self.assertTrue(SOURCES)

    def test_python38_syntax(self):
        for path in SOURCES:
            with self.subTest(path=rel(path)):
                ast.parse(read(path), path, feature_version=(3, 8))

    def test_future_annotations(self):
        for path in SOURCES:
            with self.subTest(path=rel(path)):
                tree = ast.parse(read(path))
                imports = [n for n in tree.body
                           if isinstance(n, ast.ImportFrom)
                           and n.module == "__future__"
                           and any(a.name == "annotations" for a in n.names)]
                self.assertTrue(imports)

    def test_environ_is_not_modified(self):
        mutators = {"update", "setdefault", "pop", "popitem", "clear"}
        for path in ENV_SOURCES:
            with self.subTest(path=rel(path)):
                for node in ast.walk(ast.parse(read(path))):
                    targets = []
                    if isinstance(node, (ast.Assign, ast.AugAssign)):
                        targets = getattr(node, "targets", None) \
                            or [node.target]
                    elif isinstance(node, ast.Delete):
                        targets = node.targets
                    for t in targets:
                        self.assertFalse(
                            isinstance(t, ast.Subscript)
                            and is_os_environ(t.value),
                            "os.environ[...] at line %d" % node.lineno)
                    if isinstance(node, ast.Call) and \
                            isinstance(node.func, ast.Attribute):
                        f = node.func
                        self.assertFalse(
                            is_os_environ(f.value) and f.attr in mutators,
                            "os.environ.%s at line %d" % (f.attr, node.lineno))
                        self.assertFalse(
                            isinstance(f.value, ast.Name)
                            and f.value.id == "os"
                            and f.attr in ("putenv", "unsetenv"),
                            "os.%s at line %d" % (f.attr, node.lineno))

    def test_yaml_is_imported_lazily(self):
        for path in SOURCES:
            tree = ast.parse(read(path))
            top = [n for n in tree.body
                   if isinstance(n, (ast.Import, ast.ImportFrom))]
            for n in top:
                names = [a.name for a in n.names] if isinstance(n, ast.Import) \
                    else [n.module or ""]
                self.assertNotIn("yaml", names, rel(path))
            uses = [n for n in ast.walk(tree) if isinstance(n, ast.Import)
                    and any(a.name == "yaml" for a in n.names)]
            if uses:
                self.assertTrue(path.endswith("/aosp_build/config_file.py"),
                                rel(path))

    def test_wrappers(self):
        pattern = re.compile(
            r'\A#!/bin/bash\nexec python3 "\$\(dirname "\$\(readlink -f '
            r'"\$0"\)"\)/(src/[\w/]+\.py)" "\$@"\n\Z')
        for name in WRAPPERS:
            with self.subTest(wrapper=name):
                path = os.path.join(REPODIR, name)
                m = pattern.match(read(path))
                self.assertIsNotNone(m, "not a plain wrapper")
                self.assertTrue(os.path.isfile(os.path.join(REPODIR,
                                                            m.group(1))))
                self.assertTrue(os.access(path, os.X_OK))


if __name__ == "__main__":
    unittest.main()
