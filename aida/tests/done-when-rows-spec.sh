#!/usr/bin/env bash
# done-when-rows-spec.sh: the design check warns on an order that holds more than a handful of
# done-when rows, or more than three per criterion it owns, and a row design added after the freeze can be taken out again through go-on
# keep, with no judgement left owed on it (gap row 439).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# rows_case <count> [none]: wo1, which owns one criterion, or none, with that many done-when rows. Prints the check's exit and the orders it
# names past a handful.
rows_case() (
  source "$HERE/records.bash"
  task_records branch
  edit "$TASK/design/wo1.json" '.doneWhen = [ range($n) | "row \(.)" ]' --argjson n "$1"
  [ "${2:-}" != none ] || edit "$TASK/design/wo1.json" '.criteriaOwned = []'
  bash "$PLUGIN/scripts/check-design.sh" "$TASK" >"$OUT" 2>/dev/null
  printf '%s|%s\n' "$?" "$(jq -c '[ (.graph.ordersPastHandfulOfRows // [])[] | .id ]' "$OUT")"
)
expect "nine done-when rows are named, and the check does not stop" "$(rows_case 9 none)" '0|["wo1"]'
expect "eight done-when rows on an order that owns no criterion are not named" "$(rows_case 8 none)" '0|[]'
expect "three done-when rows for one owned criterion are not named" "$(rows_case 3)" '0|[]'
expect "four done-when rows for one owned criterion are named" "$(rows_case 4)" '0|["wo1"]'

# The snapshot holds a row design added after the freeze, still owed its judgement, and the live
# design took it out again. Attended, start leaves that as a change on wo1. go-on keep takes the
# live design and leaves no judgement owed on the row that is gone.
removed_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records tests-frozen
  suite_records ""
  tests_record
  edit "$IMPL/snapshot.json" '(.workOrders[] | select(.id == "wo1")).doneWhen += ["a cosmetic row"]'
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")) |= . + {doneWhenGained: ["a cosmetic row"], doneWhenGainedAt: "2026-10-28T00:00:00Z",
      changed: [{step: "start", reason: "design drift: the design file for wo1 has changed since the snapshot was taken", allows: ["keep"]}]}'
  answer "implement go-on keep" wo1 "keep the design without the cosmetic row"
  run "$IMPLEMENT" go-on "$TASK" wo1 --continue keep --because "keep the design without the cosmetic row"
  printf '%s|%s|%s|' "$RC" "$(ledger '.doneWhenGained // "none"')" "$(sed -n 's/^next: //p' "$OUT")"
  run "$IMPLEMENT" build-brief "$TASK" wo1
  printf '%s\n' "$RC"
)
expect "go-on keep takes out a row added after the freeze, and the build is not refused" "$(removed_case)" \
  '0|none|build wo1|0'

# The same gained row, reworded: design removes it and adds the new text. go-on keep lists the new
# text as gained, so the build waits for its judgement.
reworded_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records tests-frozen
  suite_records ""
  tests_record
  edit "$IMPL/snapshot.json" '(.workOrders[] | select(.id == "wo1")).doneWhen += ["a cosmetic row"]'
  edit "$TASK/design/wo1.json" '.doneWhen += ["a reworded cosmetic row"]'
  edit "$TASK/design-closed.json" '.hash = $h' --arg h "$(records_hash_for "$TASK")"
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")) |= . + {doneWhenGained: ["a cosmetic row"], doneWhenGainedAt: "2026-10-28T00:00:00Z",
      changed: [{step: "start", reason: "design drift: the design file for wo1 has changed since the snapshot was taken", allows: ["keep"]}]}'
  answer "implement go-on keep" wo1 "keep the reworded row"
  run "$IMPLEMENT" go-on "$TASK" wo1 --continue keep --because "keep the reworded row"
  printf '%s|%s|' "$RC" "$(ledger '.doneWhenGained | join(",")')"
  run "$IMPLEMENT" build-brief "$TASK" wo1
  printf '%s\n' "$RC"
)
expect "go-on keep lists a reworded gained row as gained, and the build waits for its judgement" "$(reworded_case)" \
  '0|a reworded cosmetic row|120'

# A gained row keeps the judgement of the frozen rows. Taking it out again leaves that judgement.
judged_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records tests-frozen
  suite_records ""
  tests_record
  edit "$TASK/design/wo1.json" '.doneWhen += ["a cosmetic row"]'
  edit "$TASK/design-closed.json" '.hash = $h' --arg h "$(records_hash_for "$TASK")"
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).doneWhenJudgement = {verdict: "confirmed", judgedBy: "model", note: "the row reads a.php"}'
  run "$IMPLEMENT" start "$TASK"
  printf '%s|%s|' "$(ledger '.doneWhenGained | join(",")')" "$(ledger '.doneWhenJudgement.verdict // "none"')"
  edit "$TASK/design/wo1.json" '.doneWhen = ["a.php says b"]'
  edit "$TASK/design-closed.json" '.hash = $h' --arg h "$(records_hash_for "$TASK")"
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).changed = [{step: "start", reason: "design drift: the design file for wo1 has changed since the snapshot was taken", allows: ["keep"]}]'
  answer "implement go-on keep" wo1 "take the cosmetic row out"
  run "$IMPLEMENT" go-on "$TASK" wo1 --continue keep --because "take the cosmetic row out"
  printf '%s|%s\n' "$(ledger '.doneWhenGained // "none"')" "$(ledger '.doneWhenJudgement.verdict // "none"')"
)
expect "the frozen rows keep their judgement through a gained row added and taken out" "$(judged_case)" \
  'a cosmetic row|confirmed|none|confirmed'

finish
