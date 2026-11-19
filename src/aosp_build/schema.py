"""The resolved configuration passed from the host to the container (JSON)."""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass, fields
from typing import Any, Dict, Optional

from aosp_build import ConfigError

# The container reads the JSON (src/config_env.py). Increment SCHEMA (and
# the one of config_env.py) when a key is renamed, removed or changes its
# meaning. Adding a key does not need it.
SCHEMA = 1


@dataclass
class ResolvedConfig:
    schema: int
    android_version: str
    rpi: bool
    arch: str
    aosp_branch: str
    repo_rev: str
    android_rpi_branch: str
    kernel_rpi_branch: Optional[str]
    kernel_dist_dir: Optional[str]
    platform: str
    form_factor: str
    lunch_choice: str
    aosp_make: Dict[str, Any]
    kernel_build: str
    artifacts: str
    kernel_env: Dict[str, str]
    build_env: Dict[str, str]
    python2_as_python: bool
    use_gen: bool
    container_srcdir: str
    outdir_name: str
    # For the record only. The container does not read it.
    record: Dict[str, Any]

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2) + "\n"

    @classmethod
    def from_json(cls, text: str) -> "ResolvedConfig":
        data = json.loads(text)
        if not isinstance(data, dict):
            raise ConfigError("The resolved config is not an object.")
        if data.get("schema") != SCHEMA:
            raise ConfigError("Unsupported schema of the resolved config: %r"
                              % data.get("schema"))
        names = {f.name for f in fields(cls)}
        unknown = sorted(set(data) - names)
        missing = sorted(names - set(data))
        if unknown or missing:
            raise ConfigError("Invalid resolved config: unknown %s, missing %s"
                              % (unknown, missing))
        return cls(**data)
