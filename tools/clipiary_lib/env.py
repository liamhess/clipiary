from __future__ import annotations

import os
import re
import shlex
from pathlib import Path


LINE_RE = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$")


def load_env(root: Path) -> dict[str, str]:
    values = os.environ.copy()
    env_file = root / ".env"
    if not env_file.exists():
        return values

    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = LINE_RE.match(line)
        if not match:
            continue
        key, raw_value = match.groups()
        value = raw_value.strip()
        if value and value[0] in {"'", '"'}:
            parsed = shlex.split(value, posix=True)
            values[key] = parsed[0] if parsed else ""
        else:
            values[key] = value
    return values


def get_env(values: dict[str, str], key: str, default: str) -> str:
    return values.get(key, default)
