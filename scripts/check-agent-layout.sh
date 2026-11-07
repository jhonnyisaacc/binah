#!/usr/bin/env bash
set -euo pipefail

layout=(
  "canonical .agents/skills"
  "link .claude/skills ../.agents/skills"
  "forbidden .cursor/skills"
  "forbidden .github/skills"
  "forbidden .codex/skills"
  "scanned .agents"
  "scanned AGENTS.md"
)
symlink_mode=120000
home_path='/(Users|home)/[^/[:space:]]+/'

root=$(git rev-parse --show-toplevel)
cd "$root"
failures=()

frontmatter_name() {
  awk '
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
    /^---[[:space:]]*$/ { exit }
    {
      key = $0
      sub(/:.*/, "", key)
      gsub(/[[:space:]]/, "", key)
      if (key == "name") {
        value = $0
        sub(/^[^:]*:/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        gsub(/^["\047]+|["\047]+$/, "", value)
        print "=" value
        exit
      }
    }
  '
}

check_canonical() {
  local dir=$1 path folder name
  while IFS= read -r -d '' path; do
    folder=${path#"$dir"/}
    folder=${folder%/SKILL.md}
    [[ $path == "$dir/$folder/SKILL.md" && $folder != */* ]] || continue
    name=$(git show ":$path" | frontmatter_name)
    if [[ -z $name ]]; then
      failures+=("$path has no frontmatter name; add 'name: $folder' between the opening --- lines")
    elif [[ ${name#=} != "$folder" ]]; then
      failures+=("$path has name '${name#=}' but lives in '$folder'; rename the folder or set 'name: $folder'")
    fi
  done < <(git ls-files -z -- "$dir")
}

check_link() {
  local link=$1 target=$2 fix entries exact mode blob actual
  fix="run: git rm -r --cached $link; rm -rf $link; ln -s $target $link; git add $link"
  entries=$(git ls-files -s -- "$link")
  exact=$(printf '%s\n' "$entries" | awk -F '\t' -v p="$link" '$2 == p { print $1 }')
  if [[ -z $entries ]]; then
    failures+=("$link is not tracked; $fix")
    return
  fi
  if [[ -z $exact ]]; then
    failures+=("$link is a directory of $(printf '%s\n' "$entries" | wc -l | tr -d ' ') tracked files, not a symlink to $target; move its skills into $canonical, then $fix")
    return
  fi
  read -r mode blob _ <<<"$exact"
  if [[ $mode != "$symlink_mode" ]]; then
    failures+=("$link is a regular file, not a symlink to $target; $fix")
    return
  fi
  actual=$(git cat-file blob "$blob")
  if [[ $actual != "$target" ]]; then
    failures+=("$link points to $actual, not $target; $fix")
  fi
}

check_forbidden() {
  local dir=$1 count
  count=$(git ls-files -- "$dir" | wc -l | tr -d ' ')
  if [[ $count -gt 0 ]]; then
    failures+=("$dir holds $count tracked files; skills live only in $canonical, so git mv them there and delete $dir")
  fi
}

scanned=()
for row in "${layout[@]}"; do
  read -r kind path target <<<"$row"
  case $kind in
    canonical)
      canonical=$path
      check_canonical "$path"
      ;;
    link) check_link "$path" "$target" ;;
    forbidden) check_forbidden "$path" ;;
    scanned) scanned+=("$path") ;;
  esac
done

while IFS= read -r hit; do
  failures+=("$hit")
done < <(git grep --cached -I -n -o -E "$home_path" -- "${scanned[@]}" |
  awk -F: '!seen[$1 ":" $2]++ { print $1 ":" $2 " has the home path " $3 "; use a repo-relative path or ~ instead" }')

if [[ ${#failures[@]} -gt 0 ]]; then
  printf 'agent-layout: %s\n' "${failures[@]}" >&2
  exit 1
fi
printf 'agent-layout ok\n'
