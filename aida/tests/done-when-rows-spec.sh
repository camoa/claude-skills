#!/usr/bin/env bash
# done-when-rows-spec.sh: the design check warns on an order that holds more than a handful of
# done-when rows, and a row design added after the freeze can be taken out again through go-on
# keep, with no judgement left owed on it (gap row 439).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# rows_case <count>: wo1 with that many done-when rows. Prints the check's exit and the orders it
# names past a handful.
rows_case() (
  source "$HERE/records.bash"
  task_records branch
  edit "$TASK/design/wo1.json" '.doneWhen = [ range($n) | "row \(.)" ]' --argjson n "$1"
  bash "$PLUGIN/scripts/check-design.sh" "$TASK" >"$OUT" 2>/dev/null
  printf '%s|%s\n' "$?" "$(jq -c '[ (.graph.ordersPastHandfulOfRows // [])[] | .id ]' "$OUT")"
)
expect "nine done-when rows are named, and the check does not stop" "$(rows_case 9)" '0|["wo1"]'
expect "eight done-when rows are not named" "$(rows_case 8)" '0|[]'

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

finish
