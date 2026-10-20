#!/usr/bin/env bash
# Set author, signing, and git hooks before the first commit. Safe to run again.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"
# shellcheck source=lib/common.sh
source "$root/scripts/lib/common.sh"

author_file=$root/policy/author
if [[ ! -f $author_file ]]; then
  printf 'agent-preflight: missing %s\n' "$author_file" >&2
  exit 1
fi
if [[ ! -x $root/.githooks/commit-msg ]]; then
  printf 'agent-preflight: missing .githooks/commit-msg\n' >&2
  exit 1
fi

mapfile -t author < <(read_author_file "$author_file")
name=${author[0]}
email=${author[1]}

git config --local user.name "$name"
git config --local user.email "$email"
git config --global user.name "$name"
git config --global user.email "$email"

install_signing() {
  if [[ -n ${SSH_SIGNING_KEY_BASE64:-} ]]; then
    mkdir -p "$HOME/.ssh"
    local key=$HOME/.ssh/agent_signing
    printf '%s' "$SSH_SIGNING_KEY_BASE64" | base64 -d >"$key.tmp"
    chmod 600 "$key.tmp"
    if [[ ! -s $key.tmp ]]; then
      rm -f "$key.tmp"
      printf 'agent-preflight: SSH_SIGNING_KEY_BASE64 did not decode to a key\n' >&2
      return 1
    fi
    if [[ -f $key ]] && cmp -s "$key.tmp" "$key"; then
      rm -f "$key.tmp"
    else
      mv "$key.tmp" "$key"
    fi
    chmod 600 "$key"
    git config --local gpg.format ssh
    git config --local user.signingkey "$key"
    git config --local commit.gpgsign true
    git config --global gpg.format ssh
    git config --global user.signingkey "$key"
    git config --global commit.gpgsign true
    return 0
  fi

  local key sign
  key=$(git config --get user.signingkey || true)
  sign=$(git config --get commit.gpgsign || true)
  if [[ -n $key && $sign == true ]]; then
    return 0
  fi
  printf 'agent-preflight: no signing key. Set SSH_SIGNING_KEY_BASE64. Refusing unsigned commits.\n' >&2
  return 1
}

install_hooks() {
  local hooks_path
  hooks_path=$(git config --get core.hooksPath || true)
  if [[ -n $hooks_path && -f $hooks_path/.dispatcher ]]; then
    # Cursor runs its co-author hook after the repo hook, so a strip in
    # .githooks/commit-msg is too early. Chain .githooks first, then strip again.
    printf '%s\n' "$root/.githooks" >"$hooks_path/.cursor-original-hooks-path"
    local late=$hooks_path/commit-msg.cursor.z-strip-cursor-trailer
    cat >"$late" <<EOF
#!/usr/bin/env bash
set -euo pipefail
root=\$(git rev-parse --show-toplevel)
exec "\$root/.githooks/commit-msg" "\$1"
EOF
    chmod +x "$late"
    return 0
  fi
  git config --local core.hooksPath .githooks
}

install_signing
install_hooks
printf 'agent-preflight: author %s <%s>\n' "$name" "$email"
