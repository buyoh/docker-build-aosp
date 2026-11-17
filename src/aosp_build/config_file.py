"""Load the INI config file of build-aosp.sh. Runs on the host only.

The file is read by configparser of the standard library, so no external
library is required. All keys are in the [build-aosp] section. The values are
strings in INI, so they are converted by the type of each field here.
"""
from __future__ import annotations

import configparser
import os
from typing import Any, Optional

from aosp_build import ConfigError
from aosp_build.fields import FIELDS_BY_KEY, Field, normalize

SCHEMA = 1
SECTION = "build-aosp"

# configparser treats this section as the defaults of all sections. Nothing
# should be written in it, so give it a name that cannot be written.
_NO_DEFAULT_SECTION = "\0"

_BOOLS = {"true": True, "false": False}


def _parser() -> configparser.ConfigParser:
    parser = configparser.ConfigParser(
        default_section=_NO_DEFAULT_SECTION,
        interpolation=None,           # "%" is a plain character
        strict=True,                  # duplicate sections/keys are errors
        delimiters=("=",),            # not ":", to reject YAML-like lines
        empty_lines_in_values=False,
        comment_prefixes=("#", ";"),
        inline_comment_prefixes=("#", ";"),  # needs a space before them
    )
    parser.optionxform = str  # case-sensitive keys
    return parser


def _convert(field: Field, raw: str) -> Optional[Any]:
    """Convert a string in the file to the value for normalize()."""
    if "\n" in raw:
        raise ConfigError("%s: must be a single line" % field.key)
    if raw == "":
        return None
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
        raise ConfigError("%s: do not quote the value: %s" % (field.key, raw))
    if field.type == "bool":
        if raw not in _BOOLS:
            raise ConfigError("%s: must be true or false, not %r"
                              % (field.key, raw))
        return _BOOLS[raw]
    return raw


def load(path: str) -> dict:
    """Return the values in the config file, normalized. Raises ConfigError."""
    parser = _parser()
    try:
        # utf-8-sig accepts a BOM written by some editors.
        with open(path, encoding="utf-8-sig") as f:
            parser.read_file(f)
    except OSError as e:
        raise ConfigError("%s: %s" % (path, e.strerror))
    except UnicodeDecodeError as e:
        raise ConfigError("%s: not UTF-8: %s" % (path, e))
    except configparser.MissingSectionHeaderError as e:
        raise ConfigError("%s:%d: the first key must be after [%s]. The "
                          "config file is INI, not YAML"
                          % (path, e.lineno, SECTION))
    except configparser.DuplicateOptionError as e:
        raise ConfigError("%s:%d: %s: duplicate key"
                          % (path, e.lineno, e.option))
    except configparser.DuplicateSectionError as e:
        raise ConfigError("%s:%d: [%s]: duplicate section"
                          % (path, e.lineno, e.section))
    except configparser.ParsingError as e:
        lines = ", ".join(str(n) for n, _ in e.errors)
        raise ConfigError("%s: expected 'key = value' at line %s"
                          % (path, lines))
    except configparser.Error as e:
        raise ConfigError("%s: invalid INI: %s" % (path, e.message))

    for name in parser.sections():
        if name != SECTION:
            raise ConfigError("%s: [%s]: unknown section. Write the keys in "
                              "[%s]" % (path, name, SECTION))
    if parser.defaults():
        raise ConfigError("%s: keys outside [%s]" % (path, SECTION))
    if not parser.has_section(SECTION):
        raise ConfigError("%s: [%s] section is required" % (path, SECTION))
    data = dict(parser.items(SECTION))

    schema = data.get("schema")
    if schema is None:
        raise ConfigError("%s: schema = %d is required" % (path, SCHEMA))
    if schema != str(SCHEMA):
        raise ConfigError("%s: schema: must be %d, not %r"
                          % (path, SCHEMA, schema))

    base_dir = os.path.dirname(os.path.abspath(path))
    values = {}
    for key, raw in data.items():
        if key == "schema":
            continue
        field = FIELDS_BY_KEY.get(key)
        if field is None:
            raise ConfigError("%s: %s: unknown key" % (path, key))
        if not field.in_file:
            raise ConfigError("%s: %s: can be specified only by the command "
                              "line (%s)" % (path, key, field.cli))
        try:
            values[key] = normalize(field, _convert(field, raw), base_dir)
        except ConfigError as e:
            raise ConfigError("%s: %s" % (path, e))
    return values
