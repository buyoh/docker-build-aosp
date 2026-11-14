"""Load the YAML config file of build-aosp.sh. Runs on the host only.

PyYAML is imported only when a config file is given, so that it is not
required without --config (and the docker image does not have it).
"""
from __future__ import annotations

import os

from aosp_build import ConfigError
from aosp_build.fields import FIELDS_BY_KEY, normalize

SCHEMA = 1


def _make_loader(yaml):
    class Loader(yaml.SafeLoader):
        """SafeLoader that rejects duplicate keys (they are mostly typos)."""

        def construct_mapping(self, node, deep=False):
            keys = set()
            for key_node, _ in node.value:
                key = self.construct_object(key_node, deep=deep)
                try:
                    duplicated = key in keys
                except TypeError:
                    # Unhashable. SafeLoader reports it below.
                    continue
                if duplicated:
                    raise yaml.constructor.ConstructorError(
                        None, None, "duplicate key: %r" % (key,),
                        key_node.start_mark)
                keys.add(key)
            return super().construct_mapping(node, deep=deep)

    return Loader


def load(path: str) -> dict:
    """Return the values in the config file, normalized. Raises ConfigError."""
    try:
        import yaml
    except ImportError:
        raise ConfigError(
            "PyYAML is required to read the config file. Install it by "
            "'sudo apt install python3-yaml' or 'pip install pyyaml'.")

    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.load(f, Loader=_make_loader(yaml))  # a SafeLoader
    except OSError as e:
        raise ConfigError("%s: %s" % (path, e.strerror))
    except yaml.YAMLError as e:
        raise ConfigError("%s: invalid YAML: %s" % (path, e))

    if not isinstance(data, dict):
        raise ConfigError("%s: the top level must be a mapping" % path)

    schema = data.get("schema")
    if type(schema) is not int or schema != SCHEMA:
        raise ConfigError("%s: schema: must be %d, not %r"
                          % (path, SCHEMA, schema))

    base_dir = os.path.dirname(os.path.abspath(path))
    values = {}
    for key, value in data.items():
        if key == "schema":
            continue
        field = FIELDS_BY_KEY.get(key) if isinstance(key, str) else None
        if field is None:
            raise ConfigError("%s: %s: unknown key" % (path, key))
        if not field.in_file:
            raise ConfigError("%s: %s: can be specified only by the command "
                              "line (%s)" % (path, key, field.cli))
        try:
            values[key] = normalize(field, value, base_dir)
        except ConfigError as e:
            raise ConfigError("%s: %s" % (path, e))
    return values
