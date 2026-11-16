"""The parameters of build-aosp.sh.

Each parameter is declared once in FIELDS. The command line options and the
validation of the config file are made from it. When adding a parameter, also
describe it in build-aosp.example.yaml (tests check that the keys match).
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Optional, Tuple

from aosp_build import ConfigError
from aosp_build.versions import FORM_FACTORS, PLATFORMS


@dataclass(frozen=True)
class Field:
    key: str                 # the key in the config file (snake_case)
    type: str                # "str", "bool", "version" or "path"
    help: str                # the help of the command line option
    cli: Optional[str] = None         # the command line option
    cli_negate: Optional[str] = None  # the negative option of a bool
    in_file: bool = True     # can be written in the config file
    choices: Tuple[str, ...] = ()
    metavar: Optional[str] = None


FIELDS = (
    Field("android", "version", "The android version (10, 11, 12 or 14)",
          cli="--android", metavar="VERSION"),
    Field("rpi", "bool",
          "Enable Raspberry Pi specific build. Same as --platform rpi4.",
          cli="--rpi", cli_negate="--no-rpi"),
    Field("platform", "str",
          "The platform to build for (rpi4, cuttlefish or emulator). "
          "The default is rpi4 with --rpi, otherwise depends on the android "
          "version (14: cuttlefish, 10-12: emulator).",
          cli="--platform", choices=PLATFORMS,
          metavar="PLATFORM"),
    Field("form_factor", "str",
          "The form factor (phone, tv or auto). The default depends on the "
          "android version and the platform (14: tv). RPi supports only tv.",
          cli="--form-factor", choices=FORM_FACTORS,
          metavar="FORM_FACTOR"),
    Field("arch", "str",
          "The taget architecture (arm or arm64 or x86_64). "
          "For Android 14, rpi supports only arm64 (default) and the "
          "others only x86_64 (default).",
          cli="--arch", choices=("arm", "arm64", "x86_64"), metavar="ARCH"),
    Field("workdir", "path",
          "The folder that store sources will be <WORKDIR>/work.",
          cli="--workdir", metavar="DIR"),
    Field("outdir", "path", "The directory that output binaries.",
          cli="--outdir", metavar="DIR"),
    Field("gen", "bool",
          "Create gen directory (default). gen directory is used to separate "
          "out directory for each architecture.",
          cli="--gen", cli_negate="--no-gen"),
    Field("mount_same", "bool",
          "Mount the source directory to the same path in the docker "
          "container. It fails if the path is already used in the container. "
          "This option is useful when you want to avoid broken symlinks to "
          "run the emulator.",
          cli="--mount-same", cli_negate="--no-mount-same"),
    Field("daemon", "bool", "Run the docker container as daemon",
          cli="--daemon", in_file=False),
    Field("adduser", "bool",
          "Add the user in the docker container before running the docker "
          "container. This feature is useful when you use non "
          "rootless-docker. (deprecated)",
          cli="--adduser", in_file=False),
)

FIELDS_BY_KEY = {f.key: f for f in FIELDS}

# Used when neither the command line nor the config file specifies the value.
# None means the value is decided later (e.g. by the android version) or is
# required.
DEFAULTS = {
    "android": None,
    "rpi": False,
    "platform": None,
    "form_factor": None,
    "arch": None,
    "workdir": None,
    "outdir": None,
    "gen": True,
    "mount_same": False,
    "daemon": False,
    "adduser": False,
}

_TYPE_NAMES = {"str": "a string", "bool": "true or false",
               "version": "an integer or a string", "path": "a string"}


def normalize(field: Field, value: Any, base_dir: str) -> Any:
    """Validate and normalize a value. None means "not specified".

    base_dir is the base of a relative path: the directory of the config file
    for a value in the file, the current directory for a command line option.
    """
    if value is None:
        return None
    t = field.type
    # An empty string is "not specified" too (e.g. --arch "" or arch: ""),
    # as the shell scripts treated it. A path must not become base_dir.
    # It is still a type error for a bool.
    if value == "" and t != "bool":
        return None
    # bool is a subclass of int, so compare the types exactly.
    if t == "bool":
        ok = type(value) is bool
    elif t == "version":
        ok = type(value) in (int, str)
    else:
        ok = type(value) is str
    if not ok:
        raise ConfigError("%s: must be %s, not %r"
                          % (field.key, _TYPE_NAMES[t], value))
    if t == "version":
        value = str(value)
    elif t == "path":
        value = os.path.join(base_dir, os.path.expanduser(value))
    if field.choices and value not in field.choices:
        raise ConfigError("unsupported %s: %s" % (field.key, value))
    return value


def merge(cli: dict, file: dict) -> dict:
    """Merge the values. The command line > the config file > DEFAULTS."""
    merged = {}
    for f in FIELDS:
        for source in (cli, file, DEFAULTS):
            value = source.get(f.key)
            if value is not None:
                break
        merged[f.key] = value
    return merged
