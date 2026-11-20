"""Print the shell assignments of a resolved config (build-config-*.json).

Usage: python3 config_env.py <build-config.json>

Runs in the container: keep it compatible with Python 3.8 and use only the
standard library. Do not import aosp_build (host only). The host resolves the
config (src/host/aosp_build/versions/) and writes the JSON. preprocess.sh
evaluates the output (docs-ai/done-task/build-config-single-source/02).
"""
from __future__ import annotations

import json
import re
import shlex
import sys

SCHEMA = 1

# (JSON key, shell variable, export, type of the value)
#   "str":    the value as it is. null is not assigned.
#   "rpi":    true -> "rpi4", false -> "" (ARG_RPI. Always assigned)
#   "no_gen": true -> "false", false -> "true" (ARG_NO_GEN)
#   "flag":   true -> "1", false -> ""
VARIABLES = (
    ("android_version", "ANDROID_VERSION", True, "str"),
    ("android_version", "ARG_ANDROID_VERSION", True, "str"),
    ("rpi", "ARG_RPI", True, "rpi"),
    ("arch", "ARG_ARCH", True, "str"),
    ("platform", "ARG_PLATFORM", True, "str"),
    ("form_factor", "ARG_FORM_FACTOR", True, "str"),
    ("use_gen", "ARG_NO_GEN", True, "no_gen"),
    ("container_srcdir", "CONTAINER_SRCDIR", True, "str"),
    ("aosp_branch", "BRANCH_AOSP_PLATFORM", True, "str"),
    ("android_rpi_branch", "BRANCH_ANDROID_RPI", True, "str"),
    ("kernel_rpi_branch", "BRANCH_KERNEL_RPI", True, "str"),
    ("kernel_dist_dir", "KERNEL_DIST_DIR", False, "str"),
    ("repo_rev", "REPO_REV", False, "str"),
    ("lunch_choice", "LUNCH_CHOICE", False, "str"),
    ("outdir_name", "OUTDIR_NAME", False, "str"),
    ("python2_as_python", "PYTHON2_AS_PYTHON", False, "flag"),
)
# Every item of build_env is exported with its own name.
BUILD_ENV = "build_env"
# The keys that are not used by the container (yet). Unknown keys are also
# ignored. tests/py/test_config_env.py checks that every key of
# ResolvedConfig is in VARIABLES, BUILD_ENV or IGNORED.
IGNORED = ("schema", "aosp_make", "kernel_build", "artifacts", "kernel_env",
           "record")

# The keys that may be null. android_rpi_branch is null for a version without
# RPi (16); only the RPi part of fetch.sh uses BRANCH_ANDROID_RPI.
NULLABLE = ("android_rpi_branch", "kernel_rpi_branch", "kernel_dist_dir")
NAME = re.compile(r"[A-Z_][A-Z0-9_]*\Z")
# The names that build_env must not override: the variables of the scripts
# in the container (L_* is the prefix of their local variables) and of the
# shell.
RESERVED = ("SCRIPTDIR", "OUTDIR", "PATH", "HOME", "PWD", "SHELL", "IFS",
            "TEST_MNT_OUT")
RESERVED_PREFIXES = ("L_", "BASH")


class Error(Exception):
    pass


def _check(data):
    if not isinstance(data, dict):
        raise Error("not an object")
    schema = data.get("schema")
    if type(schema) is not int or schema != SCHEMA:
        raise Error("unsupported schema: %r" % (schema,))
    for key, _, _, kind in VARIABLES:
        if key not in data:
            raise Error("missing key: %s" % key)
        value = data[key]
        if kind == "str":
            if value is None and key in NULLABLE:
                continue
            if not isinstance(value, str):
                raise Error("%s must be a string: %r" % (key, value))
        elif not isinstance(value, bool):
            raise Error("%s must be a boolean: %r" % (key, value))
    env = data.get(BUILD_ENV)
    if not isinstance(env, dict):
        raise Error("%s must be an object" % BUILD_ENV)
    names = {name for _, name, _, _ in VARIABLES}
    for name, value in env.items():
        if not NAME.match(name):
            raise Error("invalid name in %s: %r" % (BUILD_ENV, name))
        if (name in names or name in RESERVED
                or name.startswith(RESERVED_PREFIXES)):
            raise Error("%s overrides %s" % (BUILD_ENV, name))
        if not isinstance(value, str):
            raise Error("%s.%s must be a string: %r" % (BUILD_ENV, name,
                                                        value))


def _value(kind, value):
    if kind == "rpi":
        return "rpi4" if value else ""
    if kind == "no_gen":
        return "false" if value else "true"
    if kind == "flag":
        return "1" if value else ""
    return value


def assignments(data):
    """Return the lines of the shell assignments. Raises Error."""
    _check(data)
    lines = []
    for key, name, export, kind in VARIABLES:
        value = data[key]
        if value is None:
            continue
        lines.append("%s%s=%s" % ("export " if export else "", name,
                                   shlex.quote(_value(kind, value))))
    for name, value in data[BUILD_ENV].items():
        lines.append("export %s=%s" % (name, shlex.quote(value)))
    return lines


def main(argv):
    if len(argv) != 2:
        print("usage: config_env.py <build-config.json>", file=sys.stderr)
        return 2
    try:
        with open(argv[1]) as f:
            data = json.load(f)
        lines = assignments(data)
    except (OSError, ValueError, Error) as e:
        print("error: Invalid resolved config %s: %s. Run the tasks by "
              "build-aosp.sh." % (argv[1], e), file=sys.stderr)
        return 2
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
