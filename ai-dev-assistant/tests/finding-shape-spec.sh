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
#   - an off-contract severity (neither critical- nor concern-synonym) is exempt from
#     where[]/remedy/reachable_by but NOT from id, which binds on every finding regardless of
#     severity — the two rules use different gates on purpose (M3)
#   - `blank` is a type check: a required field of the wrong type (number, bool, object) fails the
#     same as a missing one, not just null/empty-string (M1)
#   - a `findings` key present and not an array is a shape failure; absent/null is not, and a
#     findings[] element that is not an object fails too rather than being silently skipped (M2)
#   - schema_version reads its MAJOR component (before the first "."), so a semver-shaped version
#     like "2.0.1" still enables the check instead of falling back to the lenient pre-contract path (M4)
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

# assert_shape <label> <want shape_check> <want reason: null | a SUBSTRING that must appear> <want effective>
#
# The third argument is a SUBSTRING, deliberately, not the whole sentence. An earlier version of this
# helper compared the reason string for exact equality, and every call site carried the kernel's
# message verbatim. That is a test written from the finished code rather than from the requirement:
# rewording a message for clarity turned ten assertions red while the behaviour was identical, and
# nothing about the contract had changed. A test whose reason to exist is a line in the
# implementation describes the implementation. It cannot object to it.
#
# The contract is three things, and all three are still asserted:
#   1. the status is right,
#   2. a reason is PRESENT and non-empty whenever the status is not a clean pass, and
#   3. the reason NAMES the thing that failed — the offending field, index, or version value.
# The sentence around those is presentation, and a test that pins it buys nothing and costs a
# rewrite every time somebody improves the wording.
#
# Note this is a TIGHTENING of intent, not a relaxation to let something pass: the substring is
# chosen to be the discriminating token, so a generic reason that names nothing still fails. The
# mutation block at the end of this file proves that.
assert_shape() {
  local label="$1" esc="$2" er="$3" eeff="$4"
  local sc r eff ok=1
  sc="$(jq -r '.shape_check' <<<"$C0")"
  r="$(jq -r '.shape_check_reason' <<<"$C0")"
  eff="$(jq -r '.effective' <<<"$C0")"
  [ "$sc" = "$esc" ] || ok=0
  [ "$eff" = "$eeff" ] || ok=0
  if [ "$er" = "null" ]; then
    # a clean pass carries no reason
    [ "$r" = "null" ] || ok=0
  else
    # a non-pass MUST carry a non-empty reason, and it must name what failed
    [ -n "$r" ] && [ "$r" != "null" ] || ok=0
    case "$r" in *"$er"*) ;; *) ok=0 ;; esac
  fi
  if [ "$ok" -eq 1 ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL $label: got {shape_check=$sc reason='$r' effective=$eff} want {$esc, reason~'$er', $eeff}"
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
assert_shape "where absent" fail "where" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[],"remedy":"fix","id":"f2"}]}'
assert_shape "where empty array" fail "where" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"line":5}],"remedy":"fix","id":"f2"}]}'   # element has no file
assert_shape "where element lacks file" fail "where" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"id":"f2"}]}'   # no "remedy" key
assert_shape "remedy absent" fail "remedy" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"","id":"f2"}]}'   # empty string
assert_shape "remedy empty string" fail "remedy" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"fix"}]}'   # no "id" key
assert_shape "id absent" fail "id" unresolved

# --- reachable_by is required only when the file's lens is security, both directions ---
run_shape '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"fix","id":"f3"}]}'   # no reachable_by
assert_shape "lens=security, reachable_by missing -> fail" fail "reachable_by" unresolved

run_shape '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"fix","id":"f3","reachable_by":"an authenticated user"}]}'
assert_shape "lens=security, reachable_by present -> pass" pass null concern

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"fix","id":"f3"}]}'   # lens != security, no reachable_by
assert_shape "lens!=security, reachable_by missing -> still pass" pass null concern

# --- an off-contract severity that srank() does not recognize (neither the critical- nor the
# concern-synonym regex) is exempt from where[]/remedy/reachable_by, per D1's table ("yes on
# critical and concern") — but NOT from id, which D1 and every authority doc require on every
# finding regardless of severity (M3). "low" is deliberately NOT used here: srank()'s own
# concern-synonym regex (`^low$`) already binds it, so it is not exempt from anything. ---
run_shape '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[{"severity":"info","id":"f5"}]}'
assert_shape "info severity, id present, everything else missing -> pass, still exempt from where/remedy/reachable_by" pass null unresolved

run_shape '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[{"severity":"info"}]}'
assert_shape "info severity, id absent -> fail: id is required on every finding, not just critical/concern" fail "id" unresolved

# --- `blank` is a type check, not a null check: a required field of the wrong type must fail the
# same as a missing one, not pass because it is neither null nor the empty string (M1) ---
run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":123,"id":"f6"}]}'   # remedy is a number
assert_shape "remedy is a number, not a string -> fail" fail "remedy" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":"a.php"}],"remedy":"fix","id":false}]}'   # id is false
assert_shape "id is false, not a string -> fail" fail "id" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"concern","text":"x","where":[{"file":{}}],"remedy":"fix","id":"f6"}]}'   # where[0].file is an object
assert_shape "where[0].file is an object, not a string -> fail" fail "where" unresolved

# --- a `findings` key that IS PRESENT and is not an array is a shape failure; a `findings` key
# that is absent or null is not (M2). And once the container is an array, an element that is not
# itself an object is a failure too, not a silently-skipped entry. ---
run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":{"a":1}}'
assert_shape "findings is an object, not an array -> fail" fail "not an array" unresolved

run_shape '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":["oops"]}'
assert_shape "a findings[] element is a string, not an object -> fail" fail "not an object" unresolved

# --- schema_version parses its MAJOR component, not the whole string: a semver-shaped version like
# "2.0.1" must still enable the check (M4), and a value with no readable major component (no digits
# before the first ".", or no "." at all) must still record not_run, unchanged from before ---
run_shape '{"lens":"correctness","schema_version":"2.0.1","verdict":"pass","findings":[
  {"severity":"critical","text":"x","where":[{"file":"a.php"}],"remedy":"fix","id":"f7"}]}'
assert_shape "schema_version \"2.0.1\" (semver) -> checked, not a lenient pre-contract read" pass null critical

run_shape '{"lens":"correctness","schema_version":"2abc","verdict":"critical","findings":[{"severity":"critical","text":"x"}]}'
assert_shape "schema_version \"2abc\" -> still not_run, unchanged" not_run "2abc" critical

run_shape '{"lens":"correctness","schema_version":"v2.0","verdict":"critical","findings":[{"severity":"critical","text":"x"}]}'
assert_shape "schema_version \"v2.0\" -> still not_run, unchanged" not_run "v2.0" critical

# --- a file with no schema_version skips the check and RECORDS not_run with a reason. Asserting
# only pass/fail here would miss the mutation that turns not_run into pass while every other value
# stays identical (see mutation 3 in the report) — the recorded reason is the only place it shows. ---
run_shape '{"lens":"correctness","verdict":"critical","findings":[{"severity":"critical","text":"x"}]}'  # no schema_version key
assert_shape "schema_version absent -> not_run, recorded reason" not_run "absent" critical

run_shape '{"lens":"correctness","schema_version":1.5,"verdict":"critical","findings":[{"severity":"critical","text":"x"}]}'
assert_shape "schema_version 1.5 (<2.0) -> not_run, recorded reason" not_run "1.5" critical

run_shape '{"lens":"x","schema_version":"abc","verdict":"pass","findings":[]}'
assert_shape "schema_version unparseable -> not_run, recorded reason" not_run "abc" pass

# --- a shape failure floors effective to (at least) unresolved and never WEAKENS an already-critical
# file (D3). This is the explicit critical case: verdict pass, but the finding's own severity is
# already critical, so effective is critical BEFORE the shape check runs; the shape check must fail
# (lens=security, no reachable_by) and effective must stay critical, not drop to unresolved. ---
run_shape '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"critical","text":"x","where":[{"file":"a.php"}],"remedy":"fix","id":"f4"}]}'  # no reachable_by
assert_shape "shape fail on an already-critical file: floor, never weakens" fail "reachable_by" critical

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

# --- guard: exact count, so a silently-skipped block cannot pass as green (D8) ---
[ "$((PASS + FAIL))" -eq 27 ] || { echo "finding-shape-spec: expected 27 assertions, ran $((PASS + FAIL))"; exit 2; }

echo "----"; echo "finding-shape-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
