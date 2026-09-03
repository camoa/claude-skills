#!/usr/bin/env bash
# Behavioral spec for scripts/mechanism-disposition.sh — the deterministic mechanism-challenge matrix
# (GAP G). Exhaustive over grounding {verified,unverified,none} × mode {attended,unattended} × hint
# {none,suggested,required} = 24 cells. The matrix MUST be deterministic (no model judgment) so it is
# identical across attended/unattended runs and CI-verifiable. The load-bearing safety cells:
#   - verified + unattended + required → defer (NEVER auto-swap an author-locked mechanism)
#   - unverified + unattended          → defer (an unverified web supersede never auto-applies)
#   - any attended supersede           → surface + blocks (human decides; build halts)
#   - none (no supersede)              → keep (regardless of mode/hint)
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
SELF="$(readlink -f "$0")"
# MD_KERNEL is set only by this spec's own seeded-mutation block, which re-runs this file against a
# mutated COPY of the kernel to count how many assertions the defect kills. Unset in every other run.
K="${MD_KERNEL:-$ROOT/scripts/mechanism-disposition.sh}"
# Assertions this file runs with MD_KERNEL set, i.e. everything except the mutation block and the
# count guard. The mutation block asserts the mutant run reached exactly this many, because a mutant
# that dies early runs fewer assertions and would otherwise read as a smaller kill.
BASE_ASSERTIONS=31
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# exp <grounding> <mode> <hint> <action> <blocks> <decided_by>
exp(){
  local g="$1" m="$2" h="$3" ea="$4" eb="$5" ed="$6"
  local out; out="$("$K" --grounding "$g" --mode "$m" --hint "$h")"
  local a b d
  a="$(jq -r '.action' <<<"$out")"; b="$(jq -r '.blocks' <<<"$out")"; d="$(jq -r '.decided_by' <<<"$out")"
  if [ "$a" = "$ea" ] && [ "$b" = "$eb" ] && [ "$d" = "$ed" ]; then ok
  else no "$g/$m/$h => got {$a,$b,$d} expected {$ea,$eb,$ed}"; fi
}

# --- grounding=none → keep/false/auto for ALL mode×hint (6 cells) ---
# `none` means the cascade RAN and found no superseding pattern. That is an answer.
for m in attended unattended; do for h in none suggested required; do
  exp none "$m" "$h" keep false auto
done; done

# --- grounding=not_searched → unresolved/false/none for ALL mode×hint (6 cells) ---
# `not_searched` means the cascade did NOT run. That is not an answer, and it must never collapse
# into `none`. Two references already instruct callers to write it — gate-audit-schema.md ("Grounding
# `not_searched`, never `none`. The kernel treats those differently and only one is honest") and
# prior-art-researcher-schema.md ("Those two already mean different things to
# scripts/mechanism-disposition.sh"). Both were false: the enum had no such value, so `--grounding
# not_searched` exited 2, every caller wrote `none`, and `none` returns keep/false/auto. Measured on
# 22 real records: 59 of 99 mechanisms carry `grounding: none` and 57 of those carry no evidence any
# search ran.
#
# It does NOT block. 59 of 99 would halt, most of them on things like `ddev restart` where there is
# no native pattern to find because it is not a design decision. A gate that stops you three times a
# design phase gets bypassed. What it does is refuse to report an unasked question as a confirmed
# answer, so /review and the records can count it.
for m in attended unattended; do for h in none suggested required; do
  exp not_searched "$m" "$h" unresolved false none
done; done

# --- grounding=verified ---
# attended (any hint) → surface/true/human (3 cells)
for h in none suggested required; do exp verified attended "$h" surface true human; done
# unattended + none/suggested → auto_adopt/false/auto (2 cells)
exp verified unattended none      auto_adopt false auto
exp verified unattended suggested auto_adopt false auto
# unattended + required → defer/false/deferred (the author-lock exception) (1 cell)
exp verified unattended required  defer false deferred

# --- grounding=unverified ---
# attended (any hint) → surface/true/human (3 cells)
for h in none suggested required; do exp unverified attended "$h" surface true human; done
# unattended (any hint) → defer/false/deferred (3 cells)
for h in none suggested required; do exp unverified unattended "$h" defer false deferred; done

# A flag with no value must exit 2, not hang. Before this assertion existed, `--grounding` with no
# value sent the arg loop into a silent forever-loop: `shift 2` needs two positionals, fails with
# one, `$#` never decreases, and nothing is printed on stdout or stderr. A caller sees a hang with no
# cause. Measured at the time: exit 124 under `timeout`, 0 bytes on stderr.
for f in --grounding --mode --hint; do
  timeout 5 "$K" "$f" >/dev/null 2>&1
  [ "$?" -eq 2 ] && ok || no "$f with no value must exit 2, not hang or pass"
done

# --- input validation: bad args fail-closed (exit 2, no verdict) ---
"$K" --grounding bogus --mode attended --hint none >/dev/null 2>&1 && no "bad grounding should exit 2" || ok
"$K" --grounding verified --mode bogus --hint none >/dev/null 2>&1 && no "bad mode should exit 2" || ok
"$K" --grounding verified --mode attended --hint bogus >/dev/null 2>&1 && no "bad hint should exit 2" || ok
# hint defaults to none when omitted
DA="$("$K" --grounding none --mode attended)"; [ "$(jq -r '.action' <<<"$DA")" = "keep" ] && ok || no "omitted hint should default none"

# --- SEEDED MUTATION: this spec is shown failing on a defect before it ships ------------------
#
# Everything above is green against the kernel as written, and a green run is not evidence that any
# of it CAN go red. So one defect is seeded against the guard this kernel exists for, and the number
# of assertions it kills is asserted here rather than reported in prose somewhere else.
#
# THE GUARD CHOSEN. `not_searched` returns `unresolved`, never `keep`. That cell is the kernel's
# central promise: every other cell routes a search RESULT, and only this one refuses to route the
# absence of a search as a result. It is also the measured defect — 59 of 99 mechanisms carried
# `grounding: none` and 57 of those had no evidence any search ran, so the conflation this cell
# forbids is the one that actually happened. The alternative guards are narrower: the `required`
# author-lock (one cell, and a wrong answer there is a silent auto-swap a human can still see in the
# record) and the attended `blocks: true` (a scheduling fact, not a truth claim). Only the
# not_searched cell decides whether "nobody looked" is reported as "we looked and it was fine".
#
# The defect is the historic one exactly: not_searched answers keep/false/auto, which is what `none`
# answers. Nothing else changes — the enum still accepts the value, so a caller writing
# `not_searched` still gets a clean verdict, and only its content is wrong. That is what makes it
# worth seeding: it is invisible to every check except one that reads the answer.
if [ -z "${MD_KERNEL:-}" ]; then
  MTMP="$(mktemp -d)"; trap 'rm -rf "$MTMP"' EXIT
  cp "$K" "$MTMP/clean.sh"; chmod +x "$MTMP/clean.sh"

  # seed_defect <literal-old> <literal-new> <src> <dst>: one LITERAL replacement, exactly once.
  # Fixed strings rather than a regex, because the kernel lines carry shell and jq metacharacters and
  # a pattern that quietly matches nothing is the failure mode this whole block exists to rule out.
  seed_defect() {
    awk -v old="$1" -v new="$2" '
      { i = index($0, old)
        if (i > 0) { $0 = substr($0, 1, i - 1) new substr($0, i + length(old)); n++ }
        print }
      END { exit (n == 1 ? 0 : 3) }' "$3" > "$4"
  }

  # A mutation that silently fails to apply reads exactly like a survivor: the sub-run comes back
  # green and the spec reports the check as unkillable. Assert the edit landed before trusting it.
  if ! seed_defect 'emit unresolved false none' 'emit keep false auto' "$MTMP/clean.sh" "$MTMP/mutant.sh" \
     || diff -q "$MTMP/clean.sh" "$MTMP/mutant.sh" >/dev/null 2>&1; then
    echo "MUTATION NOT APPLIED: the not_searched branch of $K no longer holds exactly one 'emit unresolved false none'; re-read the kernel and re-target the seed" >&2
    exit 1
  fi
  chmod +x "$MTMP/mutant.sh"
  ok

  # subrun <kernel-path>  -> SUB_PASS / SUB_FAIL from the tally line.
  subrun() {
    local line
    line="$(MD_KERNEL="$1" bash "$SELF" 2>&1 | tail -1)"
    SUB_PASS="$(sed -n 's/.*: \([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1/p' <<<"$line")"
    SUB_FAIL="$(sed -n 's/.*: \([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\2/p' <<<"$line")"
    [ -n "$SUB_PASS" ] && [ -n "$SUB_FAIL" ] || { SUB_PASS=-1; SUB_FAIL=-1; }
  }

  # The control. An UNMUTATED copy, run the same way, has to be green: without it a red mutant run
  # proves only that the kernel was moved, not that the defect was seen.
  subrun "$MTMP/clean.sh"
  { [ "$SUB_FAIL" = "0" ] && [ "$SUB_PASS" = "$BASE_ASSERTIONS" ]; } && ok \
    || no "the unmutated copy must be green and complete: $SUB_PASS passed, $SUB_FAIL failed (want $BASE_ASSERTIONS/0)"

  # The kill count. A named number, not "it went red": the six not_searched cells are exhaustive over
  # mode x hint, so a defect in that one branch kills all six and nothing else. A smaller number
  # means a cell stopped covering the branch; a larger one means the seed reached further than the
  # branch it was aimed at, and either is worth failing on.
  MUTANT_KILLS=6
  subrun "$MTMP/mutant.sh"
  [ "$SUB_FAIL" = "$MUTANT_KILLS" ] && ok \
    || no "the seeded not_searched defect must kill exactly $MUTANT_KILLS assertions, killed $SUB_FAIL"
  # And it killed them by failing, not by aborting the run early.
  [ "$((SUB_PASS + SUB_FAIL))" = "$BASE_ASSERTIONS" ] && ok \
    || no "the mutant run must still reach $BASE_ASSERTIONS assertions, reached $((SUB_PASS + SUB_FAIL))"

  # A spec that checked nothing has not passed. BASE_ASSERTIONS + the four above.
  EXPECTED=$((BASE_ASSERTIONS + 4))
  TOTAL=$((PASS + FAIL))
  [ "$TOTAL" -eq "$EXPECTED" ] && ok || no "expected $EXPECTED assertions, ran $TOTAL (a skipped block reads as green)"
fi

echo "----"; echo "mechanism-disposition-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
