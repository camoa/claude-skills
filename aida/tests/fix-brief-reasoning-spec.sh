#!/usr/bin/env bash
# fix-brief-reasoning-spec.sh: the fix brief carries the order's reasoning paragraphs added after
# its last build brief, and never a struck one (gap row 485). A fixer then sees an owner's ruling.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# brief_case <snapshot reasoning> <build brief reasoning> [<live design reasoning>]: wo1 in review
# with one open finding and a build brief that carried the second reasoning. The third argument
# rewrites design/wo1.json alone, as `update --append-reasoning` does. Prints the paragraphs
# fix-brief adds.
brief_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records reviewed
  test_recipe
  tests_record
  edit "$IMPL/snapshot.json" '.workOrders[0].reasoning = $r' --arg r "$1"
  [ -z "${3:-}" ] || edit "$TASK/design/wo1.json" '.reasoning = $r' --arg r "$3"
  jq -n --arg r "$2" '{unit: {id: "wo1", reasoning: $r}}' >"$IMPL/brief-wo1-build.json"
  jq -n '{schemaVersion: 1, unit: "wo1", findings: [{id: "f1", severity: "high", file: "a.php", lines: "",
      linkedTo: "c1", evidence: "a.php is wrong", fixScope: ["a.php"],
      actionable: true, status: "open", origin: "review"}]}' >"$IMPL/review-wo1.json"
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" '{schemaVersion: 1, unit: "wo1", commit: $c, commits: []}' >"$IMPL/build-wo1.json"
  run "$IMPLEMENT" fix-brief "$TASK" wo1
  printf '%s|%s' "$RC" "$(jq -c '.newReasoning' "$IMPL/brief-wo1-fix-1.json")"
)
expect "a paragraph added after the build reaches the fixer, a struck one does not" \
  "$(brief_case $'the contract asks it\n\n[struck] old rule\n\nuse damaged()\n\n[struck] dropped later' $'the contract asks it\n\n[struck] old rule')" \
  '0|"use damaged()"'
expect "reasoning the build already carried is not repeated" \
  "$(brief_case 'the contract asks it' 'the contract asks it')" '0|""'
expect "a ruling appended to the live design file alone reaches the fixer" \
  "$(brief_case 'the contract asks it' 'the contract asks it' $'the contract asks it\n\nuse damaged()')" '0|"use damaged()"'
expect "a live edit of earlier text does not reach the fixer" \
  "$(brief_case 'the contract asks it' 'the contract asks it' $'changed rule\n\nuse damaged()')" '0|""'

finish
