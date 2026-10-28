#!/usr/bin/env bash
# acceptance-spec.sh: review's acceptance step and its mutation opt-in. The verifier's evidence is
# kept and shown beside a person's criterion, a bug it names reaches reopen, a page surface reads
# met only with a row at its viewport, a light task with no demo-path script is not unmet, and the
# mutation half of check 4 reads off when the project sets no review.mutation.
# Each case sources the helper in a subshell, so it starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"
REVIEW="$PLUGIN/skills/review/scripts/review-actions.sh"

# review_records [light] [<step>]: task t1 built on its branch, every order at <step>, default
# code-written, finish recorded over the one build commit, and c1 a person's criterion. With
# light, the task runs light.
review_records() {
  task_records branch
  jq '.criteria[0].verifiedBy = "person"' "$TASK/alignment.json" >"$ROOT/a.json" && mv "$ROOT/a.json" "$TASK/alignment.json"
  [ "${1:-}" != light ] || { jq '.runMode = "light"' "$TASK/task.json" >"$ROOT/t.json" && mv "$ROOT/t.json" "$TASK/task.json"; }
  order_records "${2:-code-written}"
  order_commit
  jq -n --arg r "$(git -C "$WT" rev-parse HEAD~1)..$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, commitRange: $r, criteria: [{id: "c1", verifiedBy: "person"}], checklists: []}' >"$IMPL/finished.json"
  mkdir -p "$TASK/review/evidence" "$TASK/records"
}

# reviewed_record [<recipes JSON>]: the review record as findings leaves it, at the worktree's head.
reviewed_record() {
  jq -n --arg at "$(git -C "$WT" rev-parse HEAD)" --arg r "$(jq -r '.commitRange' "$IMPL/finished.json")" --argjson rc "${1:-[]}" '
    {schemaVersion: 1, takenAt: "2026-10-28", task: "t1", reviewedRange: $r, reviewedAt: $at, hasUpstream: false,
     runMode: "interactive", recipes: $rc, criteria: [], findings: [], surfaces: [], catalogNotes: [],
     mutation: {verdict: "undeclared", detail: "no row", survivors: []},
     checks: [{id: "solid", verdict: "met", detail: "none"}]}' >"$TASK/review/review.json"
}

# evidence <row JSON>...: the verifier's file with these rows.
evidence() { jq -n '{rows: [$ARGS.positional[] | fromjson]}' --args "$@" >"$TASK/records/evidence.json"; }
c1_row() { jq -nc --arg p "${2:-}" --arg v "${1:-met}" '{criterion: "c1", sentence: "the export holds three rows", path: $p, verdict: $v, note: "three rows came out"}'; }

# close_case: the verifier's row for c1 names a file by a path relative to review/evidence. Prints
# the line close prints after the criterion's own line, with the task folder cut from the path.
close_case() (
  source "$HERE/records.bash"
  review_records
  reviewed_record
  : >"$TASK/review/evidence/export.txt"
  evidence "$(c1_row met export.txt)"
  run "$REVIEW" acceptance "$TASK"
  run "$REVIEW" acceptance "$TASK" --evidence
  run "$REVIEW" close "$TASK"
  grep -A1 '^criterion(c1)' "$OUT" | tail -1 | sed "s|$TASK/||"
)

# outside_case: a row whose path climbs out of review/evidence. The file is on disk there and
# beside the worktree, so only the folder decides. Prints the exit and whether the record holds
# evidence.
outside_case() (
  source "$HERE/records.bash"
  review_records
  reviewed_record
  : >"$TASK/review/outside.txt"
  : >"$ROOT/outside.txt"
  evidence "$(c1_row met ../outside.txt)"
  run "$REVIEW" acceptance "$TASK"
  run "$REVIEW" acceptance "$TASK" --evidence
  printf '%s|%s\n' "$RC" "$(jq 'has("evidence")' "$TASK/review/review.json")"
)

# bug_case: the verifier judged c1 unmet and named the file the bug is in. wo1, which owns a.php
# and c1, is closed. Prints the finding's lens, the review verdict and reopen's exit.
bug_case() (
  source "$HERE/records.bash"
  review_records "" closed
  printf '{"findings": []}\n' >"$IMPL/review-wo1.json"
  reviewed_record
  evidence "$(c1_row unmet | jq -c '. + {file: "a.php", note: "the export drops the last row"}')"
  run "$REVIEW" acceptance "$TASK"
  run "$REVIEW" acceptance "$TASK" --evidence
  run "$REVIEW" close "$TASK"
  run "$IMPLEMENT" reopen "$TASK"
  printf '%s|%s|%s\n' "$(jq -r '[ .findings[].lens ] | join(",")' "$TASK/review/review.json")" \
    "$(jq -r '.verdict' "$TASK/review/review.json")" "$RC"
)

# page_case <yes|no>: one page surface, home, at one viewport, wide, with end to end on. The suite
# counts its runs. acceptance runs, then acceptance --evidence with a home@wide row or without one.
# Prints the e2e check's verdict, whether home reads looked, and how often the suite ran.
page_case() (
  source "$HERE/records.bash"
  review_records
  jq -n '{schemaVersion: 1, viewports: [{name: "wide", width: 1280, height: 800}],
    surfaces: [{id: "home", url: "/", kinds: ["e2e"], enabled: true, masks: []}]}' >"$ROOT/surfaces.json"
  jq --arg s "$ROOT/surfaces.json" '.surfaces = {e2e: {enabled: true}, visualRegression: {enabled: false}, registryPath: $s}' \
    "$PROJECT/project.json" >"$ROOT/p.json" && mv "$ROOT/p.json" "$PROJECT/project.json"
  printf 'echo ran >>"%s/runs.txt"\necho home\n' "$ROOT" >"$ROOT/e2e.sh"
  printf -- '---\nname: fake_review\ncapability: review\nrecipe_class: process\nframework: fake\n---\n\n## Surface commands\n\n```yaml\nsurface_commands:\n  - id: e2e\n    argv: ["sh", "%s/e2e.sh"]\n```\n' "$ROOT" >"$ROOT/checks.md"
  reviewed_record "$(jq -nc --arg c "$ROOT/checks.md" '[{framework: "fake", lookup: "resolved", testRecipe: "", checkRecipe: $c}]')"
  run "$REVIEW" acceptance "$TASK"
  : >"$TASK/review/evidence/home-wide.png"
  if [ "$1" = yes ]; then
    evidence "$(c1_row)" "$(jq -nc '{surface: "home", viewport: "wide", sentence: "home shows the list", path: "home-wide.png", verdict: "met", note: "the list shows"}')"
  else
    evidence "$(c1_row)"
  fi
  run "$REVIEW" acceptance "$TASK" --evidence
  printf '%s|%s|%s\n' "$(jq -r '.checks[] | select(.id == "e2e") | .verdict' "$TASK/review/review.json")" \
    "$(jq -r '.surfaces[] | select(.id == "home") | .looked' "$TASK/review/review.json")" "$(grep -c . "$ROOT/runs.txt")"
)

# body_case: a passed review whose evidence holds one row for c1. Prints c1's line in the pull
# request body completion writes, with the task folder cut from the path.
body_case() (
  source "$HERE/records.bash"
  review_records
  reviewed_record
  : >"$TASK/review/evidence/export.txt"
  jq --arg p "$TASK/review/evidence/export.txt" '.verdict = "passed" | .criteria = [{id: "c1", verifiedBy: "person", verdict: "met", answeredBy: "person"}]
    | .evidence = [{criterion: "c1", sentence: "the export holds three rows", path: $p, verdict: "met", note: "three rows came out"}]' \
    "$TASK/review/review.json" >"$ROOT/r.json" && mv "$ROOT/r.json" "$TASK/review/review.json"
  jq '.criteria[0].verdict = "met"' "$TASK/alignment.json" >"$ROOT/a.json" && mv "$ROOT/a.json" "$TASK/alignment.json"
  run "$PLUGIN/skills/completion/scripts/completion-actions.sh" close "$TASK" -- "the export works"
  grep '^- c1:' "$TASK/completion/pr-body.md" | sed "s|$TASK/||g"
)

# light_case: the acceptance step on a light task in a project that never set end to end up.
# Prints the verdict of the e2e check.
light_case() (
  source "$HERE/records.bash"
  review_records light
  reviewed_record
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

# hook_case <path>: the write hook's decision on the verifier's Write to <path>.
hook_case() (
  source "$HERE/records.bash"
  review_records
  write_hook "$(file "$1")" aida:acceptance-verifier
)

echo "--- acceptance --evidence, then close"
expect "close prints the evidence row under the criterion, its path resolved in review/evidence" "$(close_case)" \
  "evidence(c1): met review/evidence/export.txt | three rows came out"
expect "a path that climbs out of review/evidence refuses, and records no evidence" "$(outside_case)" "52|false"
expect "an unmet row naming a file is a finding that fails the review, and reopen takes it" "$(bug_case)" "acceptance|failed|0"

echo "--- a page surface and the verifier's look"
expect "with a row at its viewport, e2e reads met, home is looked at, and the suite ran once" "$(page_case yes)" "met|true|1"
expect "with no row at its viewport, e2e reads unknown" "$(page_case no)" "unknown|false|1"

echo "--- completion: the pull request body"
expect "a criterion's line names the evidence it was judged from" "$(body_case)" \
  "- c1: a.php says b (met; evidence: met review/evidence/export.txt)"

echo "--- acceptance: a light task with no demo-path script"
expect "a light task whose project has no end to end set up is not unmet" "$(light_case)" "undeclared"

echo "--- checks: mutation testing is opt-in"
expect "with no review.mutation, check 4's audit line reads off" "$(mutation_case)" "off"
expect "with review.mutation false, it reads off" "$(mutation_case false)" "off"
expect "with review.mutation true, the row is read again" "$(mutation_case true)" "read"

echo "--- the write hook: the verifier writes its evidence and nothing else"
expect "the verifier may not write the code" "$(hook_case "$WT/a.php")" "deny"
expect "the verifier may write under review/evidence" "$(hook_case "$TASK/review/evidence/home-wide.png")" "allow"

finish
