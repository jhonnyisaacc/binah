#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
merge=$root/scripts/merge-cursor-environment.py
tmp=$(mktemp -d)

python3 "$merge" "$tmp/fresh/.cursor/environment.json"
python3 - "$tmp/fresh/.cursor/environment.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["install"] == "bash scripts/agent-preflight.sh"
assert data["start"] == "bash scripts/agent-preflight.sh"
PY

cat >"$tmp/existing.json" <<'EOF'
{
  "install": "bun install --frozen-lockfile",
  "start": "exec bun run dev"
}
EOF
python3 "$merge" "$tmp/existing.json"
python3 "$merge" "$tmp/existing.json"
python3 - "$tmp/existing.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["install"] == "bash scripts/agent-preflight.sh && bun install --frozen-lockfile", data["install"]
assert data["start"] == "bash scripts/agent-preflight.sh\nexec bun run dev", data["start"]
text = open(sys.argv[1]).read()
assert text.count("agent-preflight.sh") == 2
PY

# Installer copies the kit and is a no-op the second time.
dest=$tmp/repo
mkdir -p "$dest"
git init -q "$dest"
bash "$root/scripts/install-policy-kit.sh" "$dest" >"$tmp/out"
for f in \
  policy/author \
  policy/branch-name.regex \
  scripts/agent-preflight.sh \
  .githooks/commit-msg \
  .githooks/pre-push \
  .cursor/skills/agent-preflight/SKILL.md \
  .cursor/environment.json
do
  if [[ ! -f $dest/$f ]]; then
    printf 'kit missing %s\n' "$f" >&2
    exit 1
  fi
done
before=$(find "$dest" -type f -exec sha256sum {} \; | sort)
bash "$root/scripts/install-policy-kit.sh" "$dest" >/dev/null
after=$(find "$dest" -type f -exec sha256sum {} \; | sort)
if [[ $before != "$after" ]]; then
  printf 'second install changed files\n' >&2
  exit 1
fi

rm -rf "$tmp"
printf 'environment json ok\n'
