#!/usr/bin/env bash
# observe-look-spec.sh: the look at an observe order's page. build-record refuses when it cannot
# list the rows the order owes, and completion names a before image only where a row has one.
# Each case sources the helper in a subshell, so it starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# observe_records <done-when JSON> [<c1 verifiedBy>]: wo1 proved by a look at surface home, with
# those done-when rows, frozen with no test, at tests-frozen. wo1 owns c1, a person's criterion
# unless the second argument says otherwise.
observe_records() {
  task_records branch
  jq --argjson d "$1" '.proof = "observe" | .surfaces = ["home"] | .ownedFiles = ["a.php"] | .tests = [] | .interface = "" | .doneWhen = $d' \
    "$TASK/design/wo1.json" >"$ROOT/wo1.json" && mv "$ROOT/wo1.json" "$TASK/design/wo1.json"
  jq --arg v "${2:-person}" '.criteria[0].verifiedBy = $v' "$TASK/alignment.json" >"$ROOT/a.json" && mv "$ROOT/a.json" "$TASK/alignment.json"
  # The surface file the look read for its viewports before 6.1.0. It is kept so the case runs
  # the same on an older plugin, where its absence refused first.
  jq '.surfaces = {registryPath: "'"$ROOT"'/surfaces.json"}' "$PROJECT/project.json" >"$ROOT/p.json" && mv "$ROOT/p.json" "$PROJECT/project.json"
  jq -n '{surfaces: [{id: "home", url: "/", kinds: ["e2e"], enabled: true}], viewports: [{name: "wide"}]}' >"$ROOT/surfaces.json"
  order_records tests-frozen
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, takenAt: "2026-10-28", unit: "wo1", commit: $c, testGlobs: [], rows: [],
      proof: "observe", support: [], freezeCommits: []}' >"$IMPL/tests-wo1.json"
}

# observed_record <row JSON>...: observed-wo1.json with these rows, each screenshot and before
# image written on disk where the row names it.
observed_record() {
  mkdir -p "$IMPL/observed-wo1" "$IMPL/observed-wo1-before"
  jq -n '{order: "wo1", observedAt: "2026-10-28", judgedBy: "model", rows: [$ARGS.positional[] | fromjson]}' \
    --args "$@" >"$IMPL/observed-wo1.json"
  jq -r '.rows[] | .screenshot, (.before // empty)' "$IMPL/observed-wo1.json" | while IFS= read -r f; do : >"$f"; done
}

# build_case <done-when JSON> [<c1 verifiedBy>]: build-record on wo1 after a look whose one row
# judges "the page shows b". Prints the exit, the attempts used and whether a build record exists.
build_case() (
  source "$HERE/records.bash"
  observe_records "$@"
  printf 'b\n' >"$WT/a.php" && git -C "$WT" commit -qam "build wo1"
  observed_record "$(jq -nc --arg s "$IMPL/observed-wo1/home-wide.png" --arg b "$IMPL/observed-wo1-before/home-wide.png" \
    '{doneWhen: "the page shows b", surface: "home", viewport: "wide", screenshot: $s, before: $b, verdict: "met", note: "b shows"}')"
  printf 'Stop: none\nDeviation: none\n' >"$IMPL/answers-wo1-attempt1.md"
  run "$IMPLEMENT" build-record "$TASK" wo1 --report "$IMPL/answers-wo1-attempt1.md" --interface "$IMPL/interface-wo1.md" \
    --started-at "$(git -C "$WT" rev-parse HEAD~1)" --observed "$IMPL/observed-wo1.json"
  printf '%s|%s|%s\n' "$RC" "$(ledger '.attemptsUsed')" "$([ -f "$IMPL/build-wo1.json" ] && echo written || echo none)"
)

# before_case <with a before>: the observedRow line completion's read prints for wo1's one row,
# whose before image is there or not.
before_case() (
  source "$HERE/records.bash"
  observe_records '["the page shows b"]'
  observed_record "$(jq -nc --arg s "$IMPL/observed-wo1/home-wide.png" --arg b "$IMPL/observed-wo1-before/home-wide.png" \
    --argjson with "$1" '{doneWhen: "the page shows b", surface: "home", viewport: "wide", screenshot: $s,
      verdict: "met", note: "b shows"} + (if $with then {before: $b} else {} end)')"
  run "$PLUGIN/skills/completion/scripts/completion-actions.sh" read "$TASK"
  sed -n 's/^observedRow(c1): //p' "$OUT" | sed "s|$IMPL/||g"
)

echo "--- build-record: the rows an observe order owes"
# A done-when row that is not a sentence makes the list of owed rows fail to compute. Before the
# fix that failure read as no row missing, and the attempt was recorded.
expect "a failure to list the owed rows refuses, and records no attempt" "$(build_case '["the page shows b", 5]')" "3|0|none"
expect "a machine criterion the order owns is owed no row of the look" "$(build_case '["the page shows b"]' machine)" "0|1|written"

echo "--- completion: a before image only where a row has one"
expect "a row with no before image prints no before" "$(before_case false)" \
  "met home@wide after=observed-wo1/home-wide.png :: the page shows b"
expect "a row with a before image names it" "$(before_case true)" \
  "met home@wide before=observed-wo1-before/home-wide.png after=observed-wo1/home-wide.png :: the page shows b"

finish
