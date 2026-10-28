#!/usr/bin/env bash
# plan-stages-spec.sh: the controls of scope, research and design. Only a few stop: a person's
# answer, a design the build cannot start from, and, when nobody is there, a gap a person would
# have seen. Everything else is a warning in the task record and the stage goes on. Each case
# sources the helper in a subshell, so it starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"

# warned <step>: how many warnings of <step> the task record holds.
warned() { jq --arg s "$1" '[ (.warnings // [])[] | select(.step == $s) ] | length' "$TASK/task.json"; }
closed() { [ -f "$TASK/design-closed.json" ] && echo closed || echo open; }
# unattended: the task runs autonomous, as task set-run-mode writes it.
unattended() { jq '.runMode = "autonomous"' "$TASK/task.json" >"$ROOT/t.json" && mv "$ROOT/t.json" "$TASK/task.json"; }

# design_case <mode> <change>: design close's exit, whether it closed, and its warnings, on wo1 and
# wo2 after <change>, a jq-free shell step. The design is not closed before the call.
design_case() (
  source "$HERE/records.bash"
  task_records branch wo2
  rm -f "$TASK/design-closed.json"
  eval "$2"
  run "$DESIGN" --run-mode "$1" close "$TASK" --no-recipe
  printf '%s|%s|%s\n' "$RC" "$(closed)" "$(warned "design close")"
)
overlap='jq ".ownedFiles += [\"a.php\"]" "$TASK/design/wo2.json" >"$ROOT/w" && mv "$ROOT/w" "$TASK/design/wo2.json"'
unserved='jq ".criteria += [.criteria[0] | .id = \"c3\"] | .nextCriterionId = 4" "$TASK/alignment.json" >"$ROOT/a" && mv "$ROOT/a" "$TASK/alignment.json"'
unconfirmed='jq ".dispositions = [{candidate: \"lib/x.php\", disposition: \"reuse\", runMode: \"autonomous\"}]" "$TASK/design/wo1.json" >"$ROOT/w" && mv "$ROOT/w" "$TASK/design/wo1.json"'
confirm='jq ".proof = \"confirm\" | .tests = []" "$TASK/design/wo1.json" >"$ROOT/w" && mv "$ROOT/w" "$TASK/design/wo1.json"'
finding='mkdir -p "$TASK/research" && jq -n "{schemaVersion: 1, search: \"s1\", searchedFor: \"a\", findings: [{text: \"a.php exists\", source: \"a.php\", lookedAt: \"2026-10-28\", criteriaServed: [\"c1\"]}]}" >"$TASK/research/s1.json"'

expect "an overlap of owned files closes the design, with a warning" "$(design_case interactive "$overlap")" "0|closed|1"
expect "a criterion no order serves closes an attended design, with a warning" "$(design_case interactive "$unserved")" "0|closed|2"
expect "a criterion no order serves stops an unattended design" "$(design_case autonomous "$unserved")" "5|open|0"
expect "an unconfirmed reuse closes an unattended design, with a warning" "$(design_case autonomous "$unconfirmed")" "0|closed|1"
expect "a confirm order that owns code on a task with tests stops an attended design" "$(design_case interactive "$confirm")" "5|open|0"
expect "a research finding no order accounts for closes an attended design, with a warning" "$(design_case interactive "$finding")" "0|closed|1"
expect "a research finding no order accounts for stops an unattended design" "$(design_case autonomous "$finding")" "7|open|0"

# The critique outcome is taken in any run mode.
outcome_case() (
  source "$HERE/records.bash"
  task_records branch
  mkdir -p "$TASK/records"
  printf 'one finding\nfindings: 1\n' >"$TASK/records/design-critique-contract.md"
  run "$DESIGN" --run-mode autonomous close "$TASK" --no-recipe --critique-outcome "fixed in wo1"
  printf '%s|%s\n' "$RC" "$(jq -r '.critique.outcome // "none"' "$TASK/design-closed.json")"
)
expect "an unattended close records the critique outcome" "$(outcome_case)" "0|fixed in wo1"

# Approving run lines is a person's answer, in every run mode.
runs_case() (
  source "$HERE/records.bash"
  task_records branch
  jq '.verify = [{run: "true", pass: "exit 0", cites: "research/s1.json", binding: false, criterion: "c1"}]' \
    "$TASK/design/wo1.json" >"$ROOT/w" && mv "$ROOT/w" "$TASK/design/wo1.json"
  [ "${1:-}" != answered ] || answer "design close" "" "true"
  run "$DESIGN" --run-mode interactive close "$TASK" --no-recipe --approve-runs
  printf '%s|%s\n' "$RC" "$(jq -r '.verify[0].approved.by // "none"' "$TASK/design/wo1.json")"
)
expect "an attended close stamps no run line without the person's answer" "$(runs_case)" "70|none"
expect "an attended close stamps a run line with the person's answer" "$(runs_case answered)" "0|person"

# Gap row 442: an order of documents whose proof is tests does not close.
doc_case() (
  source "$HERE/records.bash"
  task_records branch
  jq '.ownedFiles = ["docs/guide.md"]' "$TASK/design/wo1.json" >"$ROOT/w" && mv "$ROOT/w" "$TASK/design/wo1.json"
  run "$DESIGN" check "$TASK"
  sed -n 's/^status: //p' "$OUT"
)
expect "a tests order that owns only a document does not pass the design check" "$(doc_case)" "5"

# Design starts without a closed research; the gap is a warning.
start_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$DESIGN" start "$TASK"
  printf '%s|%s\n' "$RC" "$(warned "design start")"
)
expect "design starts when research has not closed, with a warning" "$(start_case)" "0|1"

# approve_answer: the person's answer to approve, with the words approve's own refusal names. They
# name the contract as it is now.
approve_answer() {
  run "$SCOPE" approve "$TASK"
  answer "scope approve" "" "$(sed -n "s/.* -- '\(approve [^']*\)'.*/\1/p" "$OUT")"
}

# scope_case <answered> <action> [<args>...]: the action's exit, c1's author and whether the answer is
# used. c1 starts as designer. With answered, the person answered the action's step first.
scope_case() (
  source "$HERE/records.bash"
  task_records branch
  jq '.criteria[0].author = "designer"' "$TASK/alignment.json" >"$ROOT/a" && mv "$ROOT/a" "$TASK/alignment.json"
  local how="$1" action="$2"; shift 2
  case "$how:$action" in
    answered:approve) approve_answer ;;
    answered:update) answer "scope update" "" "c1 author owner" ;;
  esac
  run "$SCOPE" "$action" "$TASK" "$@"
  printf '%s|%s|%s\n' "$RC" "$(jq -r '.criteria[0].author' "$TASK/alignment.json")" \
    "$(jq -r 'map(select(.usedAt != null)) | length' "$TASK/person-answers.json" 2>/dev/null || echo 0)"
)
expect "an attended approve with no person's answer promotes nothing" "$(scope_case none approve)" "70|designer|0"
expect "approve with the person's answer promotes, and uses the answer" "$(scope_case answered approve)" "0|owner|1"
expect "update --author owner with no person's answer promotes nothing" "$(scope_case none update --id c1 --author owner)" "70|designer|0"
expect "update --author owner with the person's answer promotes" "$(scope_case answered update --id c1 --author owner)" "0|owner|1"

# Gap row 473: the person's yes is for the contract they saw. A change after it needs a new yes.
changed_case() (
  source "$HERE/records.bash"
  task_records branch
  jq '.criteria[0].author = "designer"' "$TASK/alignment.json" >"$ROOT/a" && mv "$ROOT/a" "$TASK/alignment.json"
  approve_answer
  run "$SCOPE" update "$TASK" --id c1 --text "a.php says c"
  run "$SCOPE" approve "$TASK"
  printf '%s|%s\n' "$RC" "$(jq -r '.criteria[0].author' "$TASK/alignment.json")"
)
expect "an answer given before a change does not approve the changed contract" "$(changed_case)" "70|designer"

# A scope close with no distiller sidecar goes on, with a warning. The task's design is closed and
# it has no research check, so its stage reads past scope and past research.
distill_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$SCOPE" distill "$TASK"
  # shellcheck source=/dev/null disable=SC2034 # task-helpers.sh reads PLUGIN_ROOT
  printf '%s|%s|%s\n' "$RC" "$(warned "scope distill")" "$(PLUGIN_ROOT="$PLUGIN"; source "$PLUGIN/scripts/lib/task-helpers.sh" && task_stage "$TASK" none)"
)
expect "scope closes with no distiller sidecar, with a warning" "$(distill_case)" "0|1|implement"

# research_case <mode> <served> [spike]: research check's status, its warnings, and whether the
# record design start reads says research closed. <served> is the criteria the one finding serves, as JSON. With spike, a spike folder is
# left in the worktree.
research_case() (
  source "$HERE/records.bash"
  task_records branch
  [ "$1" = interactive ] || unattended
  mkdir -p "$TASK/research"
  jq -n --argjson c "$2" '{schemaVersion: 1, search: "s1", searchedFor: "a", findings: [{text: "a.php exists", source: "a.php", lookedAt: "2026-10-28", criteriaServed: $c}]}' \
    >"$TASK/research/s1.json"
  [ "${3:-}" != spike ] || mkdir -p "$WT/.aida-spike"
  run "$RESEARCH" check "$TASK"
  printf '%s|%s|%s\n' "$(sed -n 's/^status: //p' "$OUT")" "$(warned "research check")" \
    "$(jq -r 'if .exitCode == 0 then "closed" else "open" end' "$TASK/records/research-check.json")"
)
expect "a criterion with no finding closes attended research, with a warning" "$(research_case interactive '[]')" "0|2|closed"
expect "a criterion with no finding stops unattended research" "$(research_case autonomous '[]')" "5|0|open"
expect "a spike folder left behind closes research, with a warning" "$(research_case interactive '["c1"]' spike)" "0|1|closed"

# The confirmer's verdict file takes any write it makes; the check that read it is a warning now.
confirmer_case() (
  source "$HERE/records.bash"
  task_records branch
  mkdir -p "$TASK/records"
  printf '{"lib/x.php": "reuse"}\n' >"$TASK/records/disposition-wo1.json"
  write_hook "$(jq -nc --arg f "$TASK/records/disposition-wo1.json" '{file_path: $f, content: "{}"}')" aida:disposition-confirmer
)
expect "the confirmer may rewrite its own verdict file" "$(confirmer_case)" "allow"

# recipe_case: verify --recipe's exit, the entries it carried and its warnings, from a recipe whose
# second verifier entry holds a shell character.
recipe_case() (
  source "$HERE/records.bash"
  task_records branch
  printf '## Verifier\n\nverifier:\n  - id: ok\n    run: true\n    pass: exit 0\n  - id: bad\n    run: true; false\n    pass: exit 0\n' >"$ROOT/recipe.md"
  run "$DESIGN" verify "$TASK" --id wo1 --recipe "$ROOT/recipe.md"
  printf '%s|%s|%s\n' "$RC" "$(jq -r '[.verify[]?.id] | join(",")' "$TASK/design/wo1.json")" "$(warned "design verify")"
)
expect "a recipe entry with a shell character is skipped, with a warning" "$(recipe_case)" "0|ok|1"

# light_case <owner> <path> [playwright]: the design check's status, and the paths its light list
# names, on a light task whose project registers the command `bash tests/demo.sh tests/demo.d` as
# the script that walks the demo path. The task's base holds tests/demo.sh, tests/demo.d/a.sh and
# test/a.spec. <owner> is the order that owns <path>, or none. With playwright, the command is
# `npx playwright test`, which names the folder test/.
light_case() (
  local command='["bash", "tests/demo.sh", "tests/demo.d"]'
  [ "${3:-}" != playwright ] || command='["npx", "playwright", "test"]'
  source "$HERE/records.bash"
  task_records branch wo2
  jq '.runMode = "light"' "$TASK/task.json" >"$ROOT/t" && mv "$ROOT/t" "$TASK/task.json"
  mkdir -p "$WT/tests/demo.d" "$WT/test"
  printf 'echo ok\n' >"$WT/tests/demo.sh"; printf 'echo a\n' >"$WT/tests/demo.d/a.sh"; printf 'x\n' >"$WT/test/a.spec"
  git -C "$WT" add tests test && git -C "$WT" commit -qm "the demo path" && git -C "$WT" branch -f main HEAD
  jq -n --argjson c "$command" '{schemaVersion: 1, surfaces: [{id: "demo", command: $c, kinds: ["e2e"],
      enabled: true, masks: [], critical: true, reason: "walks the demo path"}]}' >"$WT/surfaces.json"
  jq '.surfaces = {e2e: {enabled: true}, registryPath: "surfaces.json"}' "$PROJECT/project.json" >"$ROOT/p" \
    && mv "$ROOT/p" "$PROJECT/project.json"
  [ "$1" = none ] || { jq --arg o "$2" '.ownedFiles += [$o]' "$TASK/design/$1.json" >"$ROOT/w" && mv "$ROOT/w" "$TASK/design/$1.json"; }
  run "$DESIGN" check "$TASK"
  printf '%s|%s\n' "$(sed -n 's/^status: //p' "$OUT")" \
    "$(jq -r '[ .graph.lightOrdersOwningPathScript[] | .id + " " + .path ] | join(",")' "$TASK/records/design-check.json")"
)
expect "a light order that owns the registered demo-path script does not pass the design check" "$(light_case wo2 tests/demo.sh)" "5|wo2 tests/demo.sh"
expect "a light first order that owns the registered demo-path script does not pass either" "$(light_case wo1 tests/demo.sh)" "5|wo1 tests/demo.sh"
expect "a light design that leaves the registered script alone passes" "$(light_case none -)" "0|"
expect "a light order may own a folder the registered command names when the base holds it" "$(light_case wo2 test/ playwright)" "0|"
expect "a light order that adds a file under a folder the command names does not pass" "$(light_case wo2 tests/demo.d/new.sh)" "5|wo2 tests/demo.d/new.sh"
expect "a light order may edit a file the base holds under that folder" "$(light_case wo2 tests/demo.d/a.sh)" "0|"
expect "a light order that adds a spec under the folder npx playwright test names does not pass" "$(light_case wo2 test/b.spec playwright)" "5|wo2 test/b.spec"

# unstamped_case <verify entry>: an autonomous design close's exit, whether it closed, and whether it
# named the line, when wo1 is a confirm order whose one run line, <verify entry>, names c1.
unstamped_case() (
  source "$HERE/records.bash"
  task_records branch
  rm -f "$TASK/design-closed.json"
  jq --argjson v "$1" '.proof = "confirm" | .tests = [] | .verify = [$v]' "$TASK/design/wo1.json" >"$ROOT/w" \
    && mv "$ROOT/w" "$TASK/design/wo1.json"
  run "$DESIGN" --run-mode autonomous close "$TASK" --no-recipe
  printf '%s|%s|%s\n' "$RC" "$(closed)" "$(grep -c 'rests criterion c1 on a research run line' "$OUT")"
)
expect "an unattended close stops on a confirm order that rests c1 on an unstamped research line" \
  "$(unstamped_case '{"run": "true", "pass": "exit 0", "cites": "research/s1.json", "binding": false, "criterion": "c1"}')" "5|open|1"
expect "an unattended close takes the same order when the line is binding" \
  "$(unstamped_case '{"run": "true", "pass": "exit 0", "cites": "a recipe", "binding": true, "criterion": "c1"}')" "0|closed|0"

finish
