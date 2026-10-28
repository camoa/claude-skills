#!/usr/bin/env bash
# acceptance-spec.sh: review's acceptance step and its mutation opt-in. close shows the verifier's
# evidence beside a person's criterion, a light task with no demo-path script is not unmet, and the
# mutation half of check 4 reads off when the project sets no review.mutation.
# Each case sources the helper in a subshell, so it starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"
REVIEW="$PLUGIN/skills/review/scripts/review-actions.sh"

# review_records [light]: task t1 built on its branch, at code-written, finish recorded over the
# one build commit, and c1 a person's criterion. With light, the task runs light.
review_records() {
  task_records branch
  jq '.criteria[0].verifiedBy = "person"' "$TASK/alignment.json" >"$ROOT/a.json" && mv "$ROOT/a.json" "$TASK/alignment.json"
  [ "${1:-}" != light ] || { jq '.runMode = "light"' "$TASK/task.json" >"$ROOT/t.json" && mv "$ROOT/t.json" "$TASK/task.json"; }
  order_records code-written
  order_commit
  jq -n --arg r "$(git -C "$WT" rev-parse HEAD~1)..$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, commitRange: $r, criteria: [{id: "c1", verifiedBy: "person"}], checklists: []}' >"$IMPL/finished.json"
}

# reviewed_record <evidence JSON>: the review record as findings leaves it, at the worktree's head.
# With evidence, the acceptance step's rows are in it.
reviewed_record() {
  mkdir -p "$TASK/review"
  jq -n --arg at "$(git -C "$WT" rev-parse HEAD)" --arg r "$(jq -r '.commitRange' "$IMPL/finished.json")" --argjson e "$1" '
    {schemaVersion: 1, takenAt: "2026-10-28", task: "t1", reviewedRange: $r, reviewedAt: $at, hasUpstream: false,
     runMode: "interactive", recipes: [], criteria: [], findings: [], surfaces: [], catalogNotes: [],
     mutation: {verdict: "undeclared", detail: "no row", survivors: []},
     checks: [{id: "solid", verdict: "met", detail: "none"}]}
    + (if $e == null then {} else {evidence: $e} end)' >"$TASK/review/review.json"
}

# close_case: close with no row on a person's criterion that holds one evidence row. Prints the
# line after the criterion's own line, with the task folder cut from the path.
close_case() (
  source "$HERE/records.bash"
  review_records
  : >"$ROOT/export.txt"
  reviewed_record "$(jq -nc --arg p "$ROOT/export.txt" \
    '[{criterion: "c1", sentence: "the export holds three rows", path: $p, verdict: "met", note: "three rows came out"}]')"
  run "$REVIEW" close "$TASK"
  grep -A1 '^criterion(c1)' "$OUT" | tail -1 | sed "s|$ROOT/||"
)

# light_case: the acceptance step on a light task in a project that never set end to end up.
# Prints the verdict of the e2e check.
light_case() (
  source "$HERE/records.bash"
  review_records light
  reviewed_record null
  run "$REVIEW" acceptance "$TASK"
  jq -r '.checks[] | select(.id == "e2e") | .verdict' "$TASK/review/review.json"
)

# mutation_case [<review.mutation>]: checks with no recipe found for the fake framework, then the
# audit line of check 4. With an argument, project.json sets review.mutation to it.
mutation_case() (
  source "$HERE/records.bash"
  review_records
  suite_records ""
  [ -z "${1:-}" ] || { jq --argjson m "$1" '.review = {mutation: $m}' "$PROJECT/project.json" >"$ROOT/p.json" && mv "$ROOT/p.json" "$PROJECT/project.json"; }
  run "$REVIEW" checks "$TASK" --lookup-failed fake=no-recipe
  run "$REVIEW" audit "$TASK"
  sed -n 's/^check(test-and-mutation): [a-z-]* //p' "$OUT"
)

echo "--- close: the evidence beside a person's criterion"
expect "close prints the evidence row under the criterion it answers" "$(close_case)" \
  "evidence(c1): met export.txt | three rows came out"

echo "--- acceptance: a light task with no demo-path script"
expect "a light task whose project has no end to end set up is not unmet" "$(light_case)" "undeclared"

echo "--- checks: mutation testing is opt-in"
expect "with no review.mutation, check 4's audit line reads off" "$(mutation_case)" "off"
expect "with review.mutation false, it reads off" "$(mutation_case false)" "off"
expect "with review.mutation true, the row is read again" "$(mutation_case true)" "read"

finish
