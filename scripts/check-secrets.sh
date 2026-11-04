#!/usr/bin/env bash
# Scan the current tree for secrets. This does not read git history.
# A history-scanning Gitleaks job (gitleaks over every commit, fetch-depth: 0)
# stays off until this scan passes and fixture paths are listed in
# policy/secret-allowlist. Do not enable that job by default.
set -euo pipefail

if [[ $# -gt 0 ]]; then
  printf 'usage: check-secrets.sh\n' >&2
  printf 'scans the current tree only; history scanning is not enabled\n' >&2
  exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
exec python3 - "$root" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
allow_path = root / "policy" / "secret-allowlist"
patterns = [
    re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bghp_[A-Za-z0-9]{36}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}\b"),
    re.compile(r"\bgho_[A-Za-z0-9]{36}\b"),
    re.compile(r"\bxox[baprs]-[0-9A-Za-z-]{10,}"),
    re.compile(r"\bsk_live_[0-9A-Za-z]{24,}\b"),
]
skip_dirs = {".git", "node_modules", ".venv", "venv", "dist", "build", ".next"}


def load_allow() -> list[str]:
    if not allow_path.is_file():
        return []
    rules = []
    for line in allow_path.read_text().splitlines():
        line = line.split("#", 1)[0].strip().replace("\\", "/").strip("/")
        if line:
            rules.append(line)
    return rules


def allowed(rel: str, rules: list[str]) -> bool:
    for rule in rules:
        if rel == rule or rel.startswith(rule + "/"):
            return True
    return False


rules = load_allow()
hits = []
for path in sorted(root.rglob("*")):
    if not path.is_file():
        continue
    if any(part in skip_dirs for part in path.relative_to(root).parts):
        continue
    rel = path.relative_to(root).as_posix()
    if allowed(rel, rules):
        continue
    if path.stat().st_size > 1_000_000:
        continue
    data = path.read_bytes()
    if b"\0" in data[:8192]:
        continue
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        continue
    for lineno, line in enumerate(text.splitlines(), 1):
        if any(pattern.search(line) for pattern in patterns):
            hits.append(f"{rel}:{lineno}")
            break

if hits:
    for hit in hits:
        print(f"secret in {hit}", file=sys.stderr)
    sys.exit(1)
PY
