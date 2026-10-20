#!/usr/bin/env python3
"""Add agent-preflight to .cursor/environment.json without dropping the repo install."""

import json
import sys
from pathlib import Path

PREFLIGHT = "bash scripts/agent-preflight.sh"


def merge(data: dict) -> dict:
    install = data.get("install", "")
    start = data.get("start", "")
    if install is None:
        install = ""
    if start is None:
        start = ""
    if not isinstance(install, str) or not isinstance(start, str):
        raise SystemExit("install and start must be strings")
    if "agent-preflight.sh" not in install:
        data["install"] = PREFLIGHT if install == "" else f"{PREFLIGHT} && {install}"
    if "agent-preflight.sh" not in start:
        data["start"] = PREFLIGHT if start == "" else f"{PREFLIGHT}\n{start}"
    return data


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: merge-cursor-environment.py <environment.json>")
    path = Path(sys.argv[1])
    if path.exists():
        data = json.loads(path.read_text())
        if not isinstance(data, dict):
            raise SystemExit("environment.json must be an object")
    else:
        data = {}
        path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(merge(data), indent=2) + "\n")


if __name__ == "__main__":
    main()
