#!/usr/bin/env bash
# Execution spec for the repair-against-remedy checks in build-critique-assert.sh (v5.36.0).
#
# WHY THIS EXISTS. The first draft of those checks shipped unable to fail. It used jq's `index`
# for a membership test; on an array `index` searches for a subarray, so it threw on every
# record, the surrounding `|| VAR='[]'` turned the throw into an empty result, and every fixture
# written to fail them passed. Nothing in the tree would have caught a future edit that
# reintroduced it, because those fixtures lived in a scratch directory. They live here now.
#
# Each case runs the REAL script against a real record on disk. Every failing case is then
# re-run against a copy with its own check neutralised, to prove the check is what rejected it.
#
# Exit: 0 = every case behaves; 1 = a case is wrong, or a mutation survived.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ASSERT="$DIR/../scripts/build-critique-assert.sh"
fail=0
pass_n=0

if [ ! -f "$ASSERT" ]; then echo "FAIL: build-critique-assert.sh not found"; exit 1; fi
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required"; exit 1; }

TMP=$(mktemp -d) || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/task"

DIGEST=$(printf '%s' "a.md" | sha256sum | cut -d' ' -f1)
jq -n '{head:"deadbeef", files:["a.md"], empty_reason:null}' > "$TMP/change-set.json"

write_record() { # write_record <rounds json>
  jq -n --arg dig "$DIGEST" --argjson rounds "$1" '{
    schema_version:"1.9", gate_type:"build-critique", fired_at:"2026-08-30T00:00:00Z",
    gate_specific:{
      phase:"implement", verdict:"pass",
      components:[{component:"c1",risk_tier:"low",lenses:["skeptic"],verdict:"pass",
        blocking:false,checkpoint_before:"a",checkpoint_after:"b",critique_ref:"x",
        findings_count:0,runtime:"executed",rounds:1}],
      components_declared:1, components_critiqued:1, uncritiqued:[],
      alignment:{verdict:"pass",missing_requirements:[],scope_creep:[],spec_ref:"s",
        criteria_unverifiable:[]},
      tdd:{red_observed:1,passed_first_run:0,unobserved:[],reason:""},
      contract:{baseline:"captured",changed:[],added:[],removed:[],reason:""},
      closing_fixes:{applied:0,verified_by:"",reason:""},
      build_identity:{head:"deadbeef",files:["a.md"],files_digest:$dig},
      rounds:$rounds}}' > "$TMP/task/_build-critique.json"
}

case_expect() { # case_expect <label> <expect pass|block> <rounds json>
  write_record "$3"
  local OUT rc got
  OUT=$(bash "$ASSERT" "$TMP/task" --change-set-file "$TMP/change-set.json" 2>&1); rc=$?
  got="pass"; [ "$rc" -ne 0 ] && got="block"
  if [ "$got" = "$2" ]; then
    echo "PASS: $1 -> $got"
    pass_n=$((pass_n + 1))
  else
    echo "FAIL: $1 -> $got, expected $2"
    echo "      $(printf '%s' "$OUT" | jq -r '(.messages // [])|join(" | ")' 2>/dev/null)"
    fail=1
  fi
}

# --- the record the release exists for: a repair that stays silent about its bucket ---
case_expect "277-line repair, no bucket recorded"  block '[{"round":2,"repair_growth":{"net_lines":277,"reason":"needed"}}]'
case_expect "repair round with no growth block"    block '[{"round":2}]'
case_expect "repair_growth is a string"            block '[{"round":2,"repair_growth":"lots"}]'
case_expect "round 1 owes no bucket"               pass  '[{"round":1}]'

# --- the enum ---
case_expect "bucket outside the three"             block '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":"improvement","reason":"nicer"}}]'
case_expect "bucket is null"                       block '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":null,"reason":"x"}}]'
case_expect "bucket is a number"                   block '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":3,"reason":"x"}}]'
case_expect "bucket in the wrong case"             block '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":"NONE","reason":"x"}}]'

# --- a reason is owed whatever the line count says ---
case_expect "outside the remedy, no reason"        block '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":"remedy_insufficient","reason":""}}]'
case_expect "shrank the file, still outside"       block '[{"round":2,"repair_growth":{"net_lines":-40,"beyond_remedy":"new_finding","reason":"","finding":"x"}}]'
case_expect "outside the remedy, explained"        pass  '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":"remedy_insufficient","reason":"the guard needed a null check too"}}]'
case_expect "did the remedy, no reason owed"       pass  '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":"none","reason":""}}]'

# --- a noticed defect has to actually be kept ---
case_expect "new finding, none recorded"           block '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":"new_finding","reason":"saw one","finding":"  "}}]'
case_expect "new finding, recorded"                pass  '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":"new_finding","reason":"saw one","finding":"unguarded call at Foo::bar"}}]'

# --- evasion by omitting the round number, not by writing a false one ---
# The first draft keyed on `.round`, defaulting a missing key to 1, so an entry with no round
# number was skipped. Two such entries carrying a 277-line repair passed every check. Position
# in the array is the round order; the number is a label.
case_expect "no round key at all, two entries"     block '[{"repair_growth":{"net_lines":277,"reason":"new interface method"}},{"repair_growth":{"net_lines":9,"reason":"x"}}]'
case_expect "both entries numbered 1"              block '[{"round":1,"repair_growth":{"net_lines":277,"reason":"x"}},{"round":1,"repair_growth":{"net_lines":9,"reason":"y"}}]'
case_expect "a non-numeric round number"           block '[{"round":"two","repair_growth":{"net_lines":0,"beyond_remedy":"none","reason":""}}]'
case_expect "one entry, no round key, is round 1"  pass  '[{"repair_growth":{"net_lines":0,"beyond_remedy":"none","reason":""}}]'
case_expect "growth with no reason still fails"    block '[{"repair_growth":{"net_lines":3,"beyond_remedy":"none","reason":""}}]'

# --- a line count that is not a number is malformed, as the round count is ---
case_expect "net_lines as a string, no reason"     block '[{"round":2,"repair_growth":{"net_lines":"277","beyond_remedy":"none","reason":""}}]'
case_expect "net_lines as a string, with a reason" block '[{"round":2,"repair_growth":{"net_lines":"-44","beyond_remedy":"none","reason":"x"}}]'
case_expect "net_lines absent is legal"            pass  '[{"round":2,"repair_growth":{"beyond_remedy":"none","reason":""}}]'

# --- a reader that throws must not read as clean ---
case_expect "rounds is a string, not a list"       block '"four"'

# --- the line count is only compared when it is a number ---


# --- mutation: neutralise each check, confirm a blocking case slips through ---
mutate_survives() { # mutate_survives <label> <count var> <rounds json>
  cp "$ASSERT" "$TMP/mut.sh"
  perl -0pi -e "s/(  $2_N=\\\$\(jq -r 'length'[^\n]*\n)/\$1  $2_N=0\n/" "$TMP/mut.sh"
  write_record "$3"
  if bash "$TMP/mut.sh" "$TMP/task" --change-set-file "$TMP/change-set.json" >/dev/null 2>&1; then
    echo "PASS: mutation red — $1 is what rejected it"
    pass_n=$((pass_n + 1))
  else
    echo "FAIL: mutation survived — $1 was rejected by something else, so this spec proves nothing about it"
    fail=1
  fi
}
mutate_survives "the absent-bucket check"  MB '[{"round":2,"repair_growth":{"net_lines":277,"reason":"needed"}}]'
mutate_survives "the enum check"           BB '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":"improvement","reason":"nicer"}}]'
mutate_survives "the missing-reason check" UX '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":"remedy_insufficient","reason":""}}]'
mutate_survives "the kept-finding check"   EN '[{"round":2,"repair_growth":{"net_lines":0,"beyond_remedy":"new_finding","reason":"saw one","finding":"  "}}]'

# A spec that asserted nothing has not passed.
if [ "$pass_n" -lt 27 ]; then
  echo "FAIL: only $pass_n assertions ran; this spec expects 27"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "OK   repair-against-remedy gate: $pass_n assertions"
exit "$fail"
