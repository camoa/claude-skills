#!/usr/bin/env bash
# deleted-paths-spec.sh: a file the task deleted never reaches a check row that takes {paths}
# (gap row 509). A tool given a missing path fails, and review read that as a finding. Each case
# sources the helper in a subshell, so it starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# cs_case <change>: gone.php is on the branch before the range. The range deletes it, and with
# <change> also changes a.php. The coding-standards row runs cs.sh over {paths}, which fails on a
# path that is not there. Prints the paths the row was given and the row's verdict.
cs_case() (
  source "$HERE/records.bash"
  review_records
  suite_records ""
  printf 'g\n' >"$WT/gone.php"
  git -C "$WT" add gone.php && git -C "$WT" commit -qm "gone.php"
  start="$(git -C "$WT" rev-parse HEAD)"
  git -C "$WT" rm -q gone.php
  [ "$1" != change ] || printf 'c\n' >"$WT/a.php"
  git -C "$WT" commit -qam "delete gone.php"
  edit "$IMPL/finished.json" '.commitRange = $r' --arg r "$start..$(git -C "$WT" rev-parse HEAD)"
  printf 'for p; do echo "$p" >>"%s/cs-args.txt"; [ -e "$p" ] || exit 1; done\n' "$ROOT" >"$ROOT/cs.sh"
  printf -- '---\nname: fake_review\ncapability: review\nrecipe_class: process\nframework: fake\n---\n\n## Check commands\n\n```yaml\ncheck_commands:\n  - id: coding-standards\n    argv: ["sh", "%s/cs.sh", "{paths}"]\n```\n' \
    "$ROOT" >"$ROOT/checks.md"
  run "$REVIEW" checks "$TASK" --recipe "fake=$RECIPE" --check-recipe "fake=$ROOT/checks.md"
  printf '%s|%s\n' "$(tr '\n' ' ' 2>/dev/null <"$ROOT/cs-args.txt")" \
    "$(jq -r '.checks[] | select(.id == "coding-standards") | .verdict' "$TASK/review/review.json")"
)

expect "a range that deletes one file and changes another runs the row over the changed file only" \
  "$(cs_case change)" "a.php |met"
expect "a range whose only change is a deletion gives the row the empty-list result" \
  "$(cs_case only)" "|unknown"

finish
