#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d)
export HOME=$tmp/home
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
unset SSH_SIGNING_KEY_BASE64 || true

seed() {
  local repo=$1
  mkdir -p "$repo/scripts/lib" "$repo/policy" "$repo/.githooks"
  cp "$root/scripts/lib/common.sh" "$repo/scripts/lib/"
  cp "$root/scripts/agent-preflight.sh" "$repo/scripts/"
  cp "$root/policy/author" "$repo/policy/"
  cp "$root/policy/forbidden-trailers" "$repo/policy/"
  cp "$root/.githooks/commit-msg" "$repo/.githooks/"
  chmod +x "$repo/scripts/agent-preflight.sh" "$repo/.githooks/commit-msg"
  git init -q "$repo"
}

# No key and no prior signing config: refuse.
seed "$tmp/bare"
if (cd "$tmp/bare" && bash scripts/agent-preflight.sh >/dev/null 2>"$tmp/err"); then
  printf 'preflight should fail without a signing key\n' >&2
  exit 1
fi
if ! grep -q 'no signing key' "$tmp/err"; then
  printf 'missing-key error was:\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

# A generated key signs a commit and a second run does not rewrite the key.
seed "$tmp/repo"
ssh-keygen -q -t ed25519 -N '' -f "$tmp/id" -C 'preflight test'
export SSH_SIGNING_KEY_BASE64
SSH_SIGNING_KEY_BASE64=$(base64 -w0 "$tmp/id")
(cd "$tmp/repo" && bash scripts/agent-preflight.sh >/dev/null)
email=$(git -C "$tmp/repo" config --local --get user.email)
name=$(git -C "$tmp/repo" config --local --get user.name)
sign=$(git -C "$tmp/repo" config --local --get commit.gpgsign)
hooks=$(git -C "$tmp/repo" config --local --get core.hooksPath)
if [[ $email != '60485595+jhonnyisaacc@users.noreply.github.com' || $name != jhonnyisaacc || $sign != true || $hooks != .githooks ]]; then
  printf 'preflight config mismatch: %s <%s> sign=%s hooks=%s\n' "$name" "$email" "$sign" "$hooks" >&2
  exit 1
fi
mode=$(stat -c '%a' "$HOME/.ssh/agent_signing")
if [[ $mode != 600 ]]; then
  printf 'signing key mode is %s\n' "$mode" >&2
  exit 1
fi
sum1=$(sha256sum "$HOME/.ssh/agent_signing" | awk '{print $1}')
(cd "$tmp/repo" && bash scripts/agent-preflight.sh >/dev/null)
sum2=$(sha256sum "$HOME/.ssh/agent_signing" | awk '{print $1}')
if [[ $sum1 != "$sum2" ]]; then
  printf 'second preflight rewrote the signing key\n' >&2
  exit 1
fi
echo hi >"$tmp/repo/a"
git -C "$tmp/repo" add a
git -C "$tmp/repo" commit -q -m 'signed'
if [[ $(git -C "$tmp/repo" log -1 --format='%an <%ae>') != 'jhonnyisaacc <60485595+jhonnyisaacc@users.noreply.github.com>' ]]; then
  printf 'commit author drifted\n' >&2
  exit 1
fi
if [[ $(git -C "$tmp/repo" cat-file commit HEAD | grep -c '^gpgsig ') -ne 1 ]]; then
  printf 'commit has no signature\n' >&2
  exit 1
fi

# Cursor appends the trailer after the repo hook. The late hook removes it.
seed "$tmp/cursor-repo"
disp=$tmp/dispatcher
mkdir -p "$disp"
printf 'dispatcher\n' >"$disp/.dispatcher"
cat >"$disp/commit-msg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
orig=$(cat "$dir/.cursor-original-hooks-path")
if [[ -x $orig/commit-msg ]]; then
  "$orig/commit-msg" "$1"
fi
for h in "$dir"/commit-msg.cursor*; do
  [[ -x $h ]] || continue
  "$h" "$1"
done
EOF
cat >"$disp/commit-msg.cursor.co-author" <<'EOF'
#!/usr/bin/env bash
printf '\nCo-authored-by: Cursor <cursoragent@cursor.com>\n' >> "$1"
EOF
chmod +x "$disp/commit-msg" "$disp/commit-msg.cursor.co-author"
git -C "$tmp/cursor-repo" config core.hooksPath "$disp"
(cd "$tmp/cursor-repo" && bash scripts/agent-preflight.sh >/dev/null)
if [[ $(git -C "$tmp/cursor-repo" config --get core.hooksPath) != "$disp" ]]; then
  printf 'preflight replaced the Cursor hooks path\n' >&2
  exit 1
fi
if [[ ! -x $disp/commit-msg.cursor.z-strip-cursor-trailer ]]; then
  printf 'late strip hook was not installed\n' >&2
  exit 1
fi
echo b >"$tmp/cursor-repo/b"
git -C "$tmp/cursor-repo" add b
git -C "$tmp/cursor-repo" commit -q -m 'keep human trailers'
body=$(git -C "$tmp/cursor-repo" log -1 --format=%B)
if printf '%s\n' "$body" | grep -E -q 'Co-authored-by:.*[Cc]ursor'; then
  printf 'Cursor trailer survived preflight:\n%s\n' "$body" >&2
  exit 1
fi

rm -rf "$tmp"
printf 'preflight ok\n'
