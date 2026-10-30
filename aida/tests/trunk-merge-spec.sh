#!/usr/bin/env bash
# trunk-merge-spec.sh: trunk merged into a paused build (gap row 476). A commit the upstream of
# the task's base holds is trunk's and leaves every owned-files list. A merge commit is judged on
# its own edits, against the files of the whole task. A frozen test that trunk changes still stops.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# build_records [upstream]: task t1 on its branch with orders wo1 and wo2, wo1 frozen, built on
# a.php and at checks-passed, with its build record at that commit. With upstream, main tracks
# origin/main, so main@{upstream} resolves. The empty findings file is at $ROOT/findings.json.
build_records() {
  task_records branch wo2
  [ "${1:-}" != upstream ] || { git -C "$CODE" config branch.main.remote origin; git -C "$CODE" config branch.main.merge refs/heads/main; }
  order_records checks-passed
  tests_record
  printf 'b\n' >"$WT/a.php"
  git -C "$WT" commit -qam "build wo1"
  build_record wo1
  printf '{"findings": []}\n' >"$ROOT/findings.json"
}

# build_record <order>: the order's build record at HEAD, over the commits after its freeze.
build_record() {
  jq -n --arg u "$1" --arg s "$(jq -r '.commit' "$IMPL/tests-$1.json" 2>/dev/null || git -C "$WT" rev-parse HEAD~1)" \
    --arg c "$(git -C "$WT" rev-parse HEAD)" --argjson l "$(git -C "$WT" rev-list --reverse "$(git -C "$WT" rev-parse HEAD~1)..HEAD" | jq -Rsc 'split("\n") | map(select(. != ""))')" \
    '{schemaVersion: 1, unit: $u, attempt: 1, startedAt: $s, commit: $c, commits: $l, checks: []}' >"$IMPL/build-$1.json"
}

# trunk <file> <text> [push]: one commit on main in the code repository that writes <text> to
# <file>. With push, origin/main moves to it, as a push and a fetch would.
trunk() {
  git -C "$CODE" checkout -q main
  mkdir -p "$(dirname "$CODE/$1")"
  printf '%s\n' "$2" >"$CODE/$1"
  git -C "$CODE" add "$1" && git -C "$CODE" commit -qm "trunk $1"
  [ "${3:-}" != push ] || git -C "$CODE" update-ref refs/remotes/origin/main main
  git -C "$CODE" checkout -q --detach
}

# merge_main [<file> <text>]: main merged into the branch. With a file, the merge commit also
# writes <text> to it, an edit made inside the merge.
merge_main() {
  git -C "$WT" merge -q --no-edit --no-commit "${MERGE_FROM:-main}" >/dev/null 2>&1
  if [ -n "${1:-}" ]; then printf '%s\n' "$2" >"$WT/$1"; git -C "$WT" add "$1"; fi
  git -C "$WT" commit -qm "merge trunk" --no-edit >/dev/null
}

stops() { jq -c '[ .orders[] | select(.id == "wo1") | (.stopped // [])[] | .allows ]' "$IMPL/ledger.json"; }
unrecorded() { jq -c '[ .orders[] | select(.id == "wo1") | (.unrecordedCommits // [])[] ] | length' "$IMPL/ledger.json"; }

review() { run "$IMPLEMENT" review-record "$TASK" "${1:-wo1}" --findings "$ROOT/findings.json"; }
warnings() { jq '[ (.warnings // [])[] | select(.order == "'"${1:-wo1}"'") ] | length' "$TASK/task.json"; }

# wo2_records: build_records upstream, then wo1 closed over its build, and wo2 frozen on nothing,
# built on b.php and at checks-passed, with its build record at that commit.
wo2_records() {
  build_records upstream
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")) |= (.lastStep = "closed" | .commitRange = $r)' \
    --arg r "$(jq -r '.startedAt + ".." + .commit' "$IMPL/build-wo1.json")"
  printf 'b\n' >"$WT/b.php"
  git -C "$WT" add b.php && git -C "$WT" commit -qm "build wo2"
  build_record wo2
}

echo "--- trunk's commits, set aside by the upstream"
clean_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk c.php c push
  merge_main
  review
  printf '%s|%s\n' "$RC" "$(unrecorded)"
)
expect "a pushed trunk commit merged after the record: review-record goes on, and wo1's list takes none" "$(clean_case)" "0|0"

behind_case() (
  source "$HERE/records.bash"
  build_records upstream
  git -C "$CODE" checkout -q --detach main
  printf 'c\n' >"$CODE/c.php" && git -C "$CODE" add c.php && git -C "$CODE" commit -qm "trunk c.php"
  git -C "$CODE" update-ref refs/remotes/origin/main HEAD
  git -C "$CODE" checkout -q --detach
  MERGE_FROM=origin/main merge_main
  review
  echo "$RC"
)
expect "origin/main merged while main is behind it: review-record goes on" "$(behind_case)" "0"

no_upstream_case() (
  source "$HERE/records.bash"
  build_records
  trunk c.php c push
  merge_main
  review
  echo "$RC"
)
expect "a base with no upstream sets nothing aside" "$(no_upstream_case)" "63"

local_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk c.php c
  merge_main
  review
  echo "$RC"
)
expect "a commit on local main that origin/main does not hold stays on the order's list" "$(local_case)" "63"

side_case() (
  source "$HERE/records.bash"
  build_records upstream
  git -C "$CODE" branch side main
  git -C "$CODE" checkout -q side
  printf 'c\n' >"$CODE/c.php" && git -C "$CODE" add c.php && git -C "$CODE" commit -qm "side c.php"
  git -C "$CODE" checkout -q --detach
  MERGE_FROM=side merge_main
  review
  echo "$RC"
)
expect "a merge from a side branch keeps the side branch's commits on the order's list" "$(side_case)" "63"

trunk_side_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk c.php c push
  git -C "$WT" checkout -q --detach main
  git -C "$WT" merge -q --no-edit feature/t1 >/dev/null
  git -C "$WT" branch -q -f feature/t1 HEAD
  git -C "$WT" checkout -q feature/t1
  review
  echo "$RC"
)
expect "a merge made from trunk's side, with the branch moved to it: review-record goes on" "$(trunk_side_case)" "0"

echo "--- a merge's own edits"
own_edit_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk c.php c push
  merge_main c.php "c by hand"
  review
  printf '%s|%s\n' "$RC" "$(stops)"
)
expect "an edit inside the merge to a file no order owns stops wo1, and the stop allows go-on" "$(own_edit_case)" '63|[["build"]]'

owns_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk c.php c push
  merge_main c.php "c by hand"
  review
  answer "implement go-on build" wo1 "give c.php to wo1"
  run "$IMPLEMENT" go-on "$TASK" wo1 --continue build --owns c.php --because "give c.php to wo1"
  review
  echo "$RC"
)
expect "go-on --owns names the file, and review-record then goes on" "$(owns_case)" "0"

conflict_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk a.php trunk push
  git -C "$WT" merge -q --no-edit main >/dev/null 2>&1
  printf 'b\ntrunk\n' >"$WT/a.php"
  git -C "$WT" add a.php && git -C "$WT" commit -qm "merge trunk" --no-edit >/dev/null
  review
  printf '%s|%s|%s\n' "$RC" "$(warnings)" "$(unrecorded)"
)
expect "a conflict in wo1's file resolved in the merge: review-record goes on with one warning" "$(conflict_case)" "0|1|0"

closed_conflict_case() (
  source "$HERE/records.bash"
  wo2_records
  trunk a.php trunk push
  git -C "$WT" merge -q --no-edit main >/dev/null 2>&1
  printf 'b\ntrunk\n' >"$WT/a.php"
  git -C "$WT" add a.php && git -C "$WT" commit -qm "merge trunk" --no-edit >/dev/null
  review wo2
  echo "$RC"
)
expect "a conflict in a closed order's file, resolved in a merge after wo2's record: wo2 goes on" "$(closed_conflict_case)" "0"

kept_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk c.php c push
  merge_main
  trunk c.php c2 push
  git -C "$WT" merge -q --no-edit --no-commit main >/dev/null 2>&1
  git -C "$WT" checkout -q HEAD -- c.php
  git -C "$WT" commit -qm "merge trunk" --no-edit >/dev/null
  review
  echo "$RC"
)
expect "a merge that keeps the branch side of a file only trunk changed is an own edit" "$(kept_case)" "63"

deleted_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk c.php c push
  git -C "$WT" merge -q --no-edit --no-commit main >/dev/null 2>&1
  git -C "$WT" rm -qf c.php
  git -C "$WT" commit -qm "merge trunk" --no-edit >/dev/null
  review
  echo "$RC"
)
expect "a merge that deletes a file trunk added is an own edit" "$(deleted_case)" "63"

taken_case() (
  source "$HERE/records.bash"
  wo2_records
  trunk c.php c push
  git -C "$WT" merge -q --no-edit --no-commit main >/dev/null 2>&1
  git -C "$WT" checkout -q main -- a.php
  git -C "$WT" commit -qm "merge trunk" --no-edit >/dev/null
  review wo2
  printf '%s|%s\n' "$RC" "$(warnings wo2)"
)
expect "a merge that takes trunk's side of wo1's file: wo2 goes on with one warning" "$(taken_case)" "0|1"

echo "--- a frozen test trunk changed"
frozen_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk tests/a_test.sh "$(cat "$WT/tests/a_test.sh")" push
  merge_main
  trunk tests/a_test.sh "exit 0" push
  merge_main
  review
  printf '%s|%s\n' "$RC" "$(stops)"
)
expect "trunk's change to wo1's frozen test stops wo1, and the stop allows no go-on" "$(frozen_case)" '63|[[]]'

echo "--- the readers of the range"
unattributed_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk c.php c push
  merge_main
  run "$IMPLEMENT" unattributed "$TASK"
  grep -c '^unattributed: none$' "$OUT"
)
expect "unattributed names no trunk commit and no clean merge" "$(unattributed_case)" "1"

unattributed_edit_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk c.php c push
  merge_main c.php "c by hand"
  run "$IMPLEMENT" unattributed "$TASK"
  grep -c '^unattributed: [0-9a-f]* merge trunk$' "$OUT"
)
expect "unattributed names a merge that edits a file by its own hand" "$(unattributed_edit_case)" "1"

close_case() (
  source "$HERE/records.bash"
  build_records upstream
  trunk c.php c push
  merge_main
  review
  run "$IMPLEMENT" close "$TASK" wo1
  [ "$(ledger '.commitRange' | cut -d. -f3)" = "$(jq -r '.commit' "$IMPL/build-wo1.json")" ] && echo "$RC|record" || { echo "$RC|$(ledger '.commitRange')"; cat "$OUT"; }
)
expect "close ends wo1's range at its record's commit, past trunk's commits" "$(close_case)" "0|record"

finish
