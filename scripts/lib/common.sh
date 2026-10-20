#!/usr/bin/env bash
# Helpers sourced by the policy scripts. Not an entry point.

read_author_file() {
  local file=$1
  local name email
  name=$(grep -E '^name=' "$file" | head -n 1 | cut -d= -f2-)
  email=$(grep -E '^email=' "$file" | head -n 1 | cut -d= -f2-)
  if [[ -z $name || -z $email ]]; then
    printf 'author file %s needs name= and email=\n' "$file" >&2
    return 1
  fi
  printf '%s\n%s\n' "$name" "$email"
}

branch_name_allowed() {
  local name=$1
  local regex_file=$2
  printf '%s\n' "$name" | grep -E -q -f "$regex_file"
}

strip_forbidden_trailers() {
  local msg=$1
  local patterns=$2
  local tmp line
  tmp=$(mktemp)
  cp "$msg" "$tmp"
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    grep -E -v -e "$line" "$tmp" >"$tmp.next" || true
    mv "$tmp.next" "$tmp"
  done <"$patterns"
  awk '
    { line[NR] = $0 }
    END {
      n = NR
      while (n > 0 && line[n] ~ /^[[:space:]]*$/) n--
      for (i = 1; i <= n; i++) print line[i]
      if (NR > 0) print ""
    }
  ' "$tmp" >"$msg"
  rm -f "$tmp"
}
