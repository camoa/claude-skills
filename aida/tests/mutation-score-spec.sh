#!/usr/bin/env bash
# mutation-score-spec.sh: review records mutmut's outcome counts as the mutation score (gap row
# 508). mutmut 3.8.1 redraws its counts with carriage returns, and its last line is a rate after a
# full run, or one mutant's result after a run given mutant names. The stub prints both shapes with
# real carriage returns.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# score_case <counts> <tail>: a task that changed a.php, a project that opts in to mutation testing,
# and a mutation row that runs a mutmut stub over the changed files. With <counts> yes, the stub
# prints two redraws of the counts on one line. It then prints <tail> and exits 0. Prints the score
# review recorded, the row's verdict, and whether its detail says no score line was printed.
score_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records code-written
  order_commit
  tests_record
  jq -n --arg r "$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, commitRange: $r, criteria: [{id: "c1", verifiedBy: "machine"}], checklists: []}' >"$IMPL/finished.json"
  suite_records ""
  edit "$PROJECT/project.json" '.review.mutation = true'
  printf '%s\n' 'printf "Running mutation testing\n"' >"$ROOT/mutmut-stub.sh"
  [ "$1" != yes ] || printf '%s\n' \
    'printf "\342\240\213 1/11  \360\237\216\211 0 \360\237\253\245 0  \342\217\260 0  \360\237\244\224 0  \360\237\231\201 1  \360\237\224\207 0  \360\237\247\231 0\r"' \
    'printf "\342\240\231 11/11  \360\237\216\211 4 \360\237\253\245 3  \342\217\260 0  \360\237\244\224 0  \360\237\231\201 4  \360\237\224\207 0  \360\237\247\231 0\n"' \
    >>"$ROOT/mutmut-stub.sh"
  printf "printf '%s\\n' '%s'\n" '%s' "$2" >>"$ROOT/mutmut-stub.sh"
  awk -v stub="$ROOT/mutmut-stub.sh" '
    /^  - id: mutation$/ { print; print "    argv: [\"sh\", \"" stub "\", \"{paths}\"]"; print "    cost: once"; skip = 2; next }
    skip > 0 { skip--; next }
    { print }' "$RECIPE" >"$ROOT/recipe.new" && mv "$ROOT/recipe.new" "$RECIPE"
  run "$REVIEW" checks "$TASK" --recipe "fake=$RECIPE"
  jq -r '.mutation | .score + "|" + .verdict + "|" + (.detail | test("printed no score line") | tostring)' \
    "$TASK/review/review.json" 2>/dev/null || { echo "exit $RC"; cat "$OUT"; }
)
COUNTS="$(printf '\342\240\231 11/11  \360\237\216\211 4 \360\237\253\245 3  \342\217\260 0  \360\237\244\224 0  \360\237\231\201 4  \360\237\224\207 0  \360\237\247\231 0')"
expect "a full run records the last counts, not the rate line" "$(score_case yes '12.50 mutations/second')" "$COUNTS|met|false"
expect "a run given mutant names records the counts, not a mutant's result" \
  "$(score_case yes "$(printf '\360\237\231\201 mpkg.a.x_is_big__mutmut_2')")" "$COUNTS|met|false"
expect "a run that draws no counts says it printed no score line" "$(score_case no 'nothing to mutate')" "|met|true"

finish
