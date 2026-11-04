#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
# shellcheck source=../scripts/keep-current.sh
source "$root/scripts/keep-current.sh"

[[ $(pr_action yes no) == close ]]
[[ $(pr_action no yes) == close ]]
[[ $(pr_action no no) == merge ]]
if should_delete_branch main ''; then
  printf 'main must be kept\n' >&2
  exit 1
fi
if should_delete_branch refactor/run-01 ''; then
  printf 'an integration branch must be kept\n' >&2
  exit 1
fi
if should_delete_branch feat/parent 'main feat/parent'; then
  printf 'an open base must be kept\n' >&2
  exit 1
fi
if ! should_delete_branch feat/old-merged 'main'; then
  printf 'a merged head should be deleted\n' >&2
  exit 1
fi
if grep -E -q 'git rebase' "$root/scripts/keep-current.sh"; then
  printf 'keep-current must not rebase\n' >&2
  exit 1
fi

tmp=$(mktemp -d)
git init -q --bare -b main "$tmp/bare"
git init -q "$tmp/work"
git -C "$tmp/work" config user.email test@example.com
git -C "$tmp/work" config user.name test
git -C "$tmp/work" config commit.gpgsign false
git -C "$tmp/work" remote add origin "$tmp/bare"
echo base >"$tmp/work/file.txt"
echo shared >"$tmp/work/shared.txt"
git -C "$tmp/work" add file.txt shared.txt
git -C "$tmp/work" commit -q -m A
git -C "$tmp/work" branch -M main
git -C "$tmp/work" push -q -u origin main

git -C "$tmp/work" switch -q -c feat/behind
echo behind >"$tmp/work/other.txt"
git -C "$tmp/work" add other.txt
git -C "$tmp/work" commit -q -m C
git -C "$tmp/work" push -q -u origin feat/behind

git -C "$tmp/work" switch -q main
git -C "$tmp/work" switch -q -c feat/conflict
echo conflict >"$tmp/work/shared.txt"
git -C "$tmp/work" add shared.txt
git -C "$tmp/work" commit -q -m conflict
git -C "$tmp/work" push -q -u origin feat/conflict

git -C "$tmp/work" switch -q main
git -C "$tmp/work" branch feat/landed
git -C "$tmp/work" push -q origin feat/landed

git -C "$tmp/work" switch -q -c feat/old-merged
echo old >"$tmp/work/old.txt"
git -C "$tmp/work" add old.txt
git -C "$tmp/work" commit -q -m old
git -C "$tmp/work" push -q -u origin feat/old-merged
git -C "$tmp/work" switch -q main
git -C "$tmp/work" merge -q --no-edit feat/old-merged
git -C "$tmp/work" push -q origin main

git -C "$tmp/work" switch -q -c refactor/run-01
echo run >"$tmp/work/run.txt"
git -C "$tmp/work" add run.txt
git -C "$tmp/work" commit -q -m run
git -C "$tmp/work" push -q -u origin refactor/run-01
git -C "$tmp/work" switch -q main
git -C "$tmp/work" merge -q --no-edit refactor/run-01
git -C "$tmp/work" push -q origin main

git -C "$tmp/work" switch -q -c feat/parent
echo parent >"$tmp/work/parent.txt"
git -C "$tmp/work" add parent.txt
git -C "$tmp/work" commit -q -m parent
git -C "$tmp/work" push -q -u origin feat/parent
git -C "$tmp/work" switch -q -c feat/child
echo child >"$tmp/work/child.txt"
git -C "$tmp/work" add child.txt
git -C "$tmp/work" commit -q -m child
git -C "$tmp/work" push -q -u origin feat/child
git -C "$tmp/work" switch -q main
git -C "$tmp/work" merge -q --no-edit feat/parent
git -C "$tmp/work" push -q origin main

echo 'from main' >"$tmp/work/shared.txt"
echo 'main only' >"$tmp/work/main.txt"
git -C "$tmp/work" add shared.txt main.txt
git -C "$tmp/work" commit -q -m B
git -C "$tmp/work" push -q origin main

git -C "$tmp/work" switch -q -c feat/reused
echo first >"$tmp/work/reused.txt"
git -C "$tmp/work" add reused.txt
git -C "$tmp/work" commit -q -m 'first use'
git -C "$tmp/work" push -q -u origin feat/reused
reused_merged=$(git -C "$tmp/work" rev-parse HEAD)
echo second >"$tmp/work/reused.txt"
git -C "$tmp/work" add reused.txt
git -C "$tmp/work" commit -q -m 'not landed yet'
git -C "$tmp/work" push -q origin feat/reused
git -C "$tmp/work" switch -q main

git -C "$tmp/work" branch feat/named
git -C "$tmp/work" branch feat/unlisted
git -C "$tmp/work" push -q origin feat/named feat/unlisted
mkdir -p "$tmp/work/policy"
printf '# feat/unlisted\nfeat/named\n' >"$tmp/work/policy/integration-branches"
git -C "$tmp/work" add policy/integration-branches
git -C "$tmp/work" commit -q -m 'name an integration branch'
git -C "$tmp/work" push -q origin main

git -C "$tmp/work" branch feat/racy-tip
git -C "$tmp/work" branch feat/racy-pr
git -C "$tmp/work" push -q origin feat/racy-tip feat/racy-pr

tip() { git -C "$tmp/work" rev-parse "origin/$1"; }
merged_rows="[{\"headRefName\":\"feat/old-merged\",\"headRefOid\":\"$(tip feat/old-merged)\"}"
merged_rows+=",{\"headRefName\":\"refactor/run-01\",\"headRefOid\":\"$(tip refactor/run-01)\"}"
merged_rows+=",{\"headRefName\":\"feat/parent\",\"headRefOid\":\"$(tip feat/parent)\"}"
merged_rows+=",{\"headRefName\":\"feat/reused\",\"headRefOid\":\"$reused_merged\"}"
merged_rows+=",{\"headRefName\":\"feat/behind\",\"headRefOid\":\"$(tip feat/behind)\"}"
merged_rows+=",{\"headRefName\":\"feat/named\",\"headRefOid\":\"$(tip feat/named)\"}"
merged_rows+=",{\"headRefName\":\"feat/unlisted\",\"headRefOid\":\"$(tip feat/unlisted)\"}"
merged_rows+=",{\"headRefName\":\"feat/racy-tip\",\"headRefOid\":\"$(tip feat/racy-tip)\"}"
merged_rows+=",{\"headRefName\":\"feat/racy-pr\",\"headRefOid\":\"$(tip feat/racy-pr)\"}]"

cat >"$tmp/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/log"
case "\$*" in
  "pr list --repo acme/app --state open --limit 200 --json number,headRefName,baseRefName")
    if [[ -e "$tmp/first-read-done" ]]; then
      if [[ ! -e "$tmp/raced" ]]; then
        touch "$tmp/raced"
        tree=\$(git --git-dir="$tmp/bare" rev-parse 'feat/racy-tip^{tree}')
        later=\$(git --git-dir="$tmp/bare" -c user.name=t -c user.email=t@e.com commit-tree "\$tree" -p feat/racy-tip -m 'pushed during the run')
        git --git-dir="$tmp/bare" update-ref refs/heads/feat/racy-tip "\$later"
      fi
      printf '%s\n' '[{"number":1,"headRefName":"feat/behind","baseRefName":"main"},{"number":2,"headRefName":"feat/conflict","baseRefName":"main"},{"number":3,"headRefName":"feat/landed","baseRefName":"main"},{"number":4,"headRefName":"feat/child","baseRefName":"feat/parent"},{"number":9,"headRefName":"feat/racy-pr","baseRefName":"main"}]'
    else
      touch "$tmp/first-read-done"
      printf '%s\n' '[{"number":1,"headRefName":"feat/behind","baseRefName":"main"},{"number":2,"headRefName":"feat/conflict","baseRefName":"main"},{"number":3,"headRefName":"feat/landed","baseRefName":"main"},{"number":4,"headRefName":"feat/child","baseRefName":"feat/parent"}]'
    fi
    ;;
  "pr list --repo acme/app --state merged --limit 200 --json headRefName,headRefOid")
    printf '%s\n' '$merged_rows'
    ;;
  "pr close 3 --repo acme/app --comment Already on main. Closing.")
    ;;
  pr\ comment\ 2\ --repo\ acme/app\ --body\ *)
    ;;
  *)
    printf 'unexpected gh: %s\n' "\$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/gh"
export PATH="$tmp:$PATH"

out=$(bash "$root/scripts/keep-current.sh" --repo acme/app --workdir "$tmp/work" --apply)
printf '%s\n' "$out" | grep -q 'merge #1 feat/behind'
printf '%s\n' "$out" | grep -q 'conflict #2 feat/conflict shared.txt'
printf '%s\n' "$out" | grep -q 'close #3 feat/landed'
printf '%s\n' "$out" | grep -q 'delete feat/old-merged'
printf '%s\n' "$out" | grep -q 'keep refactor/run-01'
printf '%s\n' "$out" | grep -q 'keep feat/parent'
printf '%s\n' "$out" | grep -q 'keep feat/reused'
printf '%s\n' "$out" | grep -q 'keep feat/behind'
printf '%s\n' "$out" | grep -q 'keep feat/named'
printf '%s\n' "$out" | grep -q 'delete feat/unlisted'
printf '%s\n' "$out" | grep -q 'keep feat/racy-tip'
printf '%s\n' "$out" | grep -q 'keep feat/racy-pr'
git --git-dir="$tmp/bare" fetch "$tmp/bare" >/dev/null 2>&1 || true
subjects=$(git --git-dir="$tmp/bare" log --format=%s feat/behind)
if ! printf '%s\n' "$subjects" | grep -q '^Merge '; then
  printf 'behind was not merged\n' >&2
  git --git-dir="$tmp/bare" log --oneline feat/behind >&2
  exit 1
fi
parents=$(git --git-dir="$tmp/bare" rev-list --parents -n 1 feat/behind)
if [[ $(wc -w <<<"$parents") -lt 3 ]]; then
  printf 'merge commit should have two parents: %s\n' "$parents" >&2
  exit 1
fi
if [[ $(git --git-dir="$tmp/bare" show feat/conflict:shared.txt) != conflict ]]; then
  printf 'conflict branch was pushed\n' >&2
  exit 1
fi
if git --git-dir="$tmp/bare" show-ref --verify --quiet refs/heads/feat/old-merged; then
  printf 'merged branch was not deleted\n' >&2
  exit 1
fi
git --git-dir="$tmp/bare" show-ref --verify --quiet refs/heads/refactor/run-01
git --git-dir="$tmp/bare" show-ref --verify --quiet refs/heads/feat/parent
git --git-dir="$tmp/bare" show-ref --verify --quiet refs/heads/feat/reused
git --git-dir="$tmp/bare" show-ref --verify --quiet refs/heads/feat/behind
git --git-dir="$tmp/bare" show-ref --verify --quiet refs/heads/feat/named
if [[ $(git --git-dir="$tmp/bare" log -1 --format=%s feat/racy-tip) != 'pushed during the run' ]]; then
  printf 'a commit pushed during the run was lost\n' >&2
  exit 1
fi
git --git-dir="$tmp/bare" show-ref --verify --quiet refs/heads/feat/racy-pr
if git --git-dir="$tmp/bare" show-ref --verify --quiet refs/heads/feat/unlisted; then
  printf 'a branch named only in a comment was kept\n' >&2
  exit 1
fi
if ! grep -q 'Not rebasing' "$tmp/log"; then
  printf 'conflict comment missing\n' >&2
  cat "$tmp/log" >&2
  exit 1
fi

rm -rf "$tmp"
printf 'keep-current ok\n'
