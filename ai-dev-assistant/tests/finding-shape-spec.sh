#!/usr/bin/env bash
# Behavioral spec for the shape check inside scripts/wo-critique-aggregate.sh (D1-D5 of
# ../../projects/ai_dev_assistant/.../finding_contract/design/finding-contract.md). The kernel's
# effective()/loop logic already has its own spec (wo-critique-aggregate-spec.sh); this file is
# scoped to the NEW behavior only: shape_check() and its two consequences — the version gate (D4)
# and the floor it applies to `effective` (D3).
#
# The load-bearing cells:
#   - a shape-compliant critical finding                    → shape_check pass, effective untouched
#   - each of where[]/remedy/id missing, one at a time       → shape_check fail (rule-specific reason)
#   - reachable_by required ONLY when the file's lens is security, both directions asserted
#   - low/info severity findings are exempt even missing everything (rules bind critical/concern only)
#   - a file with no schema_version SKIPS the check and records shape_check:"not_run" WITH a reason —
#     not just "still passes". D4 names this the exact defect the epic keeps re-finding: an unchecked
#     thing that reports as checked. Asserting only the pass/fail outcome would miss a mutation that
#     turns "not_run" into "pass" (see the mutation report in build/wo-e.md) while leaving every
#     effective/blocking value unchanged — the recorded field is the only place that mutation shows.
#   - a shape failure FLOORS effective to (at least) unresolved and never WEAKENS an already-critical
#     file — asserted explicitly, because a flat overwrite here would fail open (D3, wo-a.md).
#   - a pre-contract file (no schema_version) behaves byte-identically to before this kernel existed —
#     asserted against the same fixtures wo-critique-aggregate-spec.sh already uses for overall/blocking.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
KERNEL="$ROOT/scripts/wo-critique-aggregate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
WO="wo-01"

# run_shape <json body of one critic file> — writes it as the sole critic file for $WO in a fresh
# dir, runs the kernel, and leaves the merged critics[0] entry in $C0 for assert_shape to read.
run_shape() {
  local d; d="$(mktemp -d "$TMP/sd.XXXX")"
  printf '%s' "$1" > "$d/${WO}.critic-1.json"
  local env; env="$(bash "$KERNEL" --wo "$WO" --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true)"
  C0="$(jq -c '.critics[0]' <<<"$env")"
}

# assert_shape <label> <want shape_check> <want reason, or "null"> <want effective>
assert_shape() {
  local label="$1" esc="$2" er="$3" eeff="$4"
  local sc r eff
  sc="$(jq -r '.shape_check' <<<"$C0")"
  r="$(jq -r '.shape_check_reason' <<<"$C0")"
  eff="$(jq -r '.effective' <<<"$C0")"
  if [ "$sc" = "$esc" ] && [ "$r" = "$er" ] && [ "$eff" = "$eeff" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL $label: got {shape_check=$sc reason='$r' effective=$eff} want {$esc,'$er',$eeff}"
    echo "  critic entry: $C0"
  fi
}

# --- a compliant schema_version:2.0 critical finding passes ---
run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"critical","text":"x","where":[{"file":"a.php","line":10}],"remedy":"do the fix","id":"f1"}]}'
assert_shape "compliant critical finding" pass null critical

# --- each required field missing, one at a time (severity:concern, verdict:pass, so the floor's
# effect is visible: base effective would be "concern", a shape failure raises it to "unresolved") ---
run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","remedy":"fix","id":"f2"}]}'   # no "where" key at all
assert_shape "where absent" fail "finding[0]: where[] missing/empty/not-an-array, or an element lacks file" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[],"remedy":"fix","id":"f2"}]}'
assert_shape "where empty array" fail "finding[0]: where[] missing/empty/not-an-array, or an element lacks file" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"line":5}],"remedy":"fix","id":"f2"}]}'   # element has no file
assert_shape "where element lacks file" fail "finding[0]: where[] missing/empty/not-an-array, or an element lacks file" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"id":"f2"}]}'   # no "remedy" key
assert_shape "remedy absent" fail "finding[0]: remedy missing or empty" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"","id":"f2"}]}'   # empty string
assert_shape "remedy empty string" fail "finding[0]: remedy missing or empty" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"fix"}]}'   # no "id" key
assert_shape "id absent" fail "finding[0]: id missing or empty" unresolved

# --- reachable_by is required only when the file's lens is security, both directions ---
run_shape '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"fix","id":"f3"}]}'   # no reachable_by
assert_shape "lens=security, reachable_by missing -> fail" fail "finding[0]: lens=security and reachable_by missing or empty" unresolved

run_shape '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"fix","id":"f3","reachable_by":"an authenticated user"}]}'
assert_shape "lens=security, reachable_by present -> pass" pass null concern

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"fix","id":"f3"}]}'   # lens != security, no reachable_by
assert_shape "lens!=security, reachable_by missing -> still pass" pass null concern

# --- low/info severity findings are exempt even when missing everything: the rules bind
# critical/concern only, per D1's table ("yes on critical and concern") ---
run_shape '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[{"severity":"low"}]}'
assert_shape "low severity missing all -> pass, exempt" pass null concern

run_shape '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[{"severity":"info"}]}'
assert_shape "info severity missing all -> pass, exempt" pass null unresolved

# --- a file with no schema_version skips the check and RECORDS not_run with a reason. Asserting
# only pass/fail here would miss the mutation that turns not_run into pass while every other value
# stays identical (see mutation 3 in the report) — the recorded reason is the only place it shows. ---
run_shape '{"lens":"correctness","verdict":"critical","findings":[{"severity":"critical","text":"x"}]}'  # no schema_version key
assert_shape "schema_version absent -> not_run, recorded reason" not_run "schema_version absent (pre-contract)" critical

run_shape '{"lens":"correctness","schema_version":1.5,"verdict":"critical","findings":[{"severity":"critical","text":"x"}]}'
assert_shape "schema_version 1.5 (<2.0) -> not_run, recorded reason" not_run "schema_version 1.5 < 2.0 (pre-contract)" critical

run_shape '{"lens":"x","schema_version":"abc","verdict":"pass","findings":[]}'
assert_shape "schema_version unparseable -> not_run, recorded reason" not_run "schema_version abc unparseable (pre-contract)" pass

# --- a shape failure floors effective to (at least) unresolved and never WEAKENS an already-critical
# file (D3). This is the explicit critical case: verdict pass, but the finding's own severity is
# already critical, so effective is critical BEFORE the shape check runs; the shape check must fail
# (lens=security, no reachable_by) and effective must stay critical, not drop to unresolved. ---
run_shape '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"critical","text":"x","where":[{"file":"a.php"}],"remedy":"fix","id":"f4"}]}'  # no reachable_by
assert_shape "shape fail on an already-critical file: floor, never weakens" fail "finding[0]: lens=security and reachable_by missing or empty" critical

# --- existing behaviour for a pre-contract file is byte-identical to before: reuse the same
# fixture shapes wo-critique-aggregate-spec.sh already asserts overall/blocking against, none of
# which carry schema_version, so shape_check must be not_run on every one of them and must never
# move overall/blocking off the pre-existing value. ---
assert_overall() { # label want_overall want_blocking, K args...
  local label="$1" eo="$2" eb="$3"; shift 3
  local out o b sc
  out="$(bash "$KERNEL" "$@")"
  o="$(jq -r '.overall' <<<"$out")"; b="$(jq -r '.blocking' <<<"$out")"
  sc="$(jq -r '[.critics[].shape_check] | unique | join(",")' <<<"$out")"
  if [ "$o" = "$eo" ] && [ "$b" = "$eb" ] && [ "$sc" = "not_run" ]; then PASS=$((PASS+1))
  else FAIL=$((FAIL+1)); echo "FAIL $label: overall=$o blocking=$b shape_check(s)=$sc (want $eo/$eb/not_run)"; fi
}
d="$(mktemp -d "$TMP/legacy.XXXX")"
jq -nc '{lens:"skeptic",verdict:"pass",findings:[]}' > "$d/${WO}.critic-1.json"
jq -nc '{lens:"skeptic",verdict:"pass",findings:[]}' > "$d/${WO}.critic-2.json"
assert_overall "legacy T1-equivalent: all pass" pass false --wo "$WO" --tier high --mode team --expected 2 --critics-dir "$d" --evaluated true

d="$(mktemp -d "$TMP/legacy.XXXX")"
jq -nc '{lens:"skeptic",verdict:"pass",findings:[]}' > "$d/${WO}.critic-1.json"
jq -nc '{lens:"skeptic",verdict:"critical",findings:[]}' > "$d/${WO}.critic-2.json"
assert_overall "legacy T2-equivalent: one critical" critical true --wo "$WO" --tier high --mode fanout --expected 2 --critics-dir "$d" --evaluated true

d="$(mktemp -d "$TMP/legacy.XXXX")"
echo '{ not json' > "$d/${WO}.critic-1.json"
assert_overall "legacy T11-equivalent: malformed critic file" critical true --wo "$WO" --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true

# --- guard: this spec must have checked something ---
[ "$((PASS + FAIL))" -gt 0 ] || { echo "finding-shape-spec: checked nothing"; exit 2; }

echo "----"; echo "finding-shape-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
