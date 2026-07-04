#!/usr/bin/env bash
# Structural spec for the autonomous_workflow_path wiring (v5.18.0+, epic orchestrator_context_hygiene).
#
# This task is routing + doc + doctrine (no new script logic), so the assertions are structural:
#   S1 (AC1): run-work-orders.md Step 4 threads a <run_mode> input keyed on .runMode into the loop
#             invocation for all three paths, + the two autonomous invariant notes.
#   S2 (AC6): the default/--parallel/--in-place flag-routing is intact; NO --autonomous CLI flag anywhere
#             (attended path byte-unchanged; mode is disk-scoped).
#   S3 (AC5 legibility): BOTH loop SKILLs declare <run_mode> in Inputs and name BRANCH_ASSEMBLED_AWAITING_HUMAN,
#             tied to the wo-mode-gate.sh autonomous_irreversible refusal, guarded on autonomous run_mode,
#             and do NOT print LOOP_COMPLETE on that branch.
#   S4 (AC2/AC3): references/autonomous-recipe.md documents §5 containment (inline loop NOT the CC runtime),
#             the milestone set + verdict-only reads, the three terminal outcomes, and HALT-composition.
#   S5 (§5/doctrine): orchestration-context-hygiene.md gains a MARKED copy-paste block naming the autonomous
#             recipe vs an attended agent team and stating "NOT the dynamic-workflows runtime"; no auto-edit.
#   S6 (containment): no new skill dir + no new wo-*/autonomous kernel added for this feature.
#
# Assert CONTENT, not tautologies. Exit 0 = all pass; 1 = a failure / missing file.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$DIR/.."
RWO="$ROOT/commands/run-work-orders.md"
LOOP="$ROOT/skills/work-order-loop/SKILL.md"
PAR="$ROOT/skills/work-order-loop-parallel/SKILL.md"
REC="$ROOT/references/autonomous-recipe.md"
DOC="$ROOT/references/orchestration-context-hygiene.md"
fail=0

for f in "$RWO" "$LOOP" "$PAR" "$REC" "$DOC"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; fail=1; }
done
[ "$fail" -eq 0 ] || { echo; echo "autonomous-recipe-spec: FAILURES (missing files)"; exit 1; }

has()  { local f="$1" d="$2"; shift 2
  if grep -Eq "$@" "$f"; then echo "PASS: $d"; else echo "FAIL: $d  (missing: $* in $(basename "$f"))"; fail=1; fi; }
hasnt(){ local f="$1" d="$2"; shift 2
  if grep -Eq "$@" "$f"; then echo "FAIL: $d  (present but must not be: $* in $(basename "$f"))"; fail=1; else echo "PASS: $d"; fi; }

echo "── S1: run-work-orders.md threads run_mode at Step 4 ──"
has  "$RWO" "S1: threads a <run_mode> input into the loop"        -i 'thread.{0,30}<run_mode>|<run_mode>.{0,30}(into|=).{0,30}\.runMode|Set <run_mode> ='
has  "$RWO" "S1: keyed on the Step-1 .runMode (zero new reads)"   '\.runMode'
has  "$RWO" "S1: fail-closed default interactive"                 -i 'interactive.{0,60}fail-closed|fail-closed.{0,60}interactive|→ .?interactive'
has  "$RWO" "S1: run_mode is orthogonal to the flags"             -i 'orthogonal'
has  "$RWO" "S1: attended path byte-identical to today"           -i 'byte-identical'
has  "$RWO" "S1: names the PR-refusal invariant"                  'wo-mode-gate\.sh'
has  "$RWO" "S1: names BRANCH_ASSEMBLED_AWAITING_HUMAN terminal"  'BRANCH_ASSEMBLED_AWAITING_HUMAN'
has  "$RWO" "S1: cites the autonomous-recipe contract"            'autonomous-recipe\.md'

echo "── S2: attended flag-routing intact, no --autonomous flag ──"
has  "$RWO" "S2: default → work-order-loop path intact"           'work-order-loop'
has  "$RWO" "S2: --parallel → work-order-loop-parallel path intact" 'work-order-loop-parallel'
has  "$RWO" "S2: --in-place path intact"                          '\-\-in-place'
hasnt "$RWO" "S2: NO --autonomous CLI flag in the command"        '\-\-autonomous'

echo "── S3: both loop SKILLs name the terminal outcome, guarded ──"
for f in "$LOOP" "$PAR"; do
  n="skills/$(basename "$(dirname "$f")")"
  has  "$f" "$n: declares <run_mode> in Inputs"                   '<run_mode>'
  has  "$f" "$n: run_mode is advisory/reporting-only"             -i 'advisory|reporting-only'
  has  "$f" "$n: names BRANCH_ASSEMBLED_AWAITING_HUMAN"           'BRANCH_ASSEMBLED_AWAITING_HUMAN'
  has  "$f" "$n: guarded on autonomous run_mode"                  -i 'autonomous'
  has  "$f" "$n: tied to the autonomous_irreversible refusal"     'autonomous_irreversible'
  has  "$f" "$n: does NOT print LOOP_COMPLETE on that branch"     -i 'NOT.{0,20}(print )?.?LOOP_COMPLETE|do \*\*NOT\*\* print .?LOOP_COMPLETE'
  has  "$f" "$n: still emits the /goal string for the human"      '/goal'
  # advisory boundary: the refusal itself is owned by the kernel reading disk, not by the passed input.
  has  "$f" "$n: refusal owned by the disk-reading kernel"        -i 'disk is truth|re-read(ing)? disk|reads? disk'
done

echo "── S4: references/autonomous-recipe.md is the verdict-only contract ──"
has  "$REC" "S4: §5 containment = inline loop, NOT the CC runtime"  -i 'inline .*loop.{0,80}NOT|NOT.{0,80}dynamic-workflows runtime|declines the runtime'
has  "$REC" "S4: reaffirms the flat call tree / depth-0"           -i 'flat.call.tree|depth-0|depth-2'
has  "$REC" "S4: documents the compact-line milestone set"         'wo-NN critique='
has  "$REC" "S4: names the mode_gate + merge_gate lines"           'mode_gate'
has  "$REC" "S4: verdict-only scalar jq -r reads"                  'jq -r'
has  "$REC" "S4: .HALT as a file-existence test"                   -i '\.HALT.{0,40}file-exist|file-exist'
has  "$REC" "S4: BRANCH_ASSEMBLED_AWAITING_HUMAN terminal named"   'BRANCH_ASSEMBLED_AWAITING_HUMAN'
has  "$REC" "S4: ESCALATION failure terminal named"               'ESCALATION'
has  "$REC" "S4: LOOP_COMPLETE-with-PR marked impossible"          -i 'structurally impossible|impossible'
has  "$REC" "S4: HALT-composition — two choke points, same disk fact" -i 'choke point'
has  "$REC" "S4: composition names the PR-refusal kernel"          'wo-mode-gate\.sh'
has  "$REC" "S4: composition names the forced fan-out critique"   -i 'forced.{0,30}critique|fan-out critique'
has  "$REC" "S4: honest boundary — gate only as strong as disk fact" -i 'OS-sandbox|only as strong as'
has  "$REC" "S4: terminal-transcript distill kept OPTIONAL"        -i 'optional'

echo "── S5: doctrine snippet in orchestration-context-hygiene.md ──"
has  "$DOC" "S5: names the autonomous recipe doctrine"            -i 'autonomous recipe'
has  "$DOC" "S5: contrasts with an attended agent team"          -i 'agent team'
has  "$DOC" "S5: states NOT the dynamic-workflows runtime"        -i 'NOT.{0,60}dynamic-workflows|dynamic-workflows runtime'
has  "$DOC" "S5: autonomous never opens a PR"                     -i 'never open a PR|never open.{0,20}PR'
has  "$DOC" "S5: points at the autonomous-recipe mechanism"       'autonomous-recipe\.md'
has  "$DOC" "S5: MARKED copy-paste block start"                  'BEGIN copy-paste'
has  "$DOC" "S5: MARKED copy-paste block end"                    'END copy-paste'
has  "$DOC" "S5: opt-in, never auto-applied to global CLAUDE.md" -i 'never auto-|by hand|opt.?in'
has  "$DOC" "S5: plugin must not auto-edit ~/.claude/CLAUDE.md"  -i 'must not auto-edit|never writes? (your|this) (global )?file'

echo "── S6: containment — no new skill / kernel for this feature ──"
if [ -d "$ROOT/skills/autonomous-recipe" ] || [ -d "$ROOT/skills/autonomous-workflow" ]; then
  echo "FAIL: S6: a new autonomous skill directory was added (containment violated)"; fail=1
else echo "PASS: S6: no new autonomous-recipe/autonomous-workflow skill directory"; fi
if ls "$ROOT/scripts/"autonomous*.sh "$ROOT/scripts/"wo-autonomous*.sh >/dev/null 2>&1; then
  echo "FAIL: S6: a new autonomous wo-*.sh kernel was added (containment violated)"; fail=1
else echo "PASS: S6: no new autonomous kernel added"; fi
# The recipe is a reference DOC, not a SKILL (no frontmatter name: line).
if head -1 "$REC" | grep -Eq '^---[[:space:]]*$'; then
  echo "FAIL: S6: autonomous-recipe.md looks like a SKILL (frontmatter) — must be a plain reference doc"; fail=1
else echo "PASS: S6: autonomous-recipe.md is a plain reference doc (no skill frontmatter)"; fi

echo
if [ "$fail" -eq 0 ]; then echo "autonomous-recipe-spec: ALL PASS"; exit 0; else echo "autonomous-recipe-spec: FAILURES"; exit 1; fi
