#!/usr/bin/env bash
# Spec for the maintainer guide create-on-miss trigger.
#
# The offer had never once fired on a task worth authoring for, and the proof sat in its own
# reference file. Two surfaces read the same coverage-map.json:
#
#   Surface 2 (recipes) — "a load-bearing capability aspect in coverage-map.json is uncovered".
#     Per-aspect. It fired on a live task and named both uncovered aspects out loud.
#   Surface 1 (guides)  — "the Domain guides matched: group is empty". Whole-task. Cannot fire
#     once anything matches.
#
# Measured on that task: coverage-map.json listed 2 uncovered aspects out of 6, and both were the
# point of the task, while _dev-guides-load.json carried 12 catalog candidates and 4 matched
# guides for the other four aspects. Sixteen is not zero, so the guide offer stayed silent about a
# gap the framework had already identified and reported.
#
# An all-or-nothing test can only fire when nothing matched, which is the case where a maintainer
# has least idea what to write. Surface 1 now uses the per-aspect test Surface 2 already had.
#
# Exit: 0 = all checks pass.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"
REF="$ROOT/references/maintainer-create-on-miss.md"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }

[ -f "$REF" ] || { echo "FAIL: $REF missing" >&2; exit 1; }

# Surface 1 keys on an uncovered aspect, the way Surface 2 always did.
grep -q 'An uncovered load-bearing aspect' "$REF" \
  && ok "Surface 1 triggers on an uncovered load-bearing aspect" \
  || bad "Surface 1 triggers on an uncovered load-bearing aspect"

grep -q 'uncovered_aspects' "$REF" \
  && ok "Surface 1 reads coverage-map.json uncovered_aspects" \
  || bad "Surface 1 reads coverage-map.json uncovered_aspects"

grep -q 'same per-aspect test Surface 2' "$REF" \
  && ok "the reference says the two surfaces now apply the same test" \
  || bad "the reference says the two surfaces now apply the same test"

# The whole-task test survives only as the no-coverage-map fallback.
grep -q 'Fallback when there is no coverage map' "$REF" \
  && ok "the whole-task union test survives as an explicit fallback" \
  || bad "the whole-task union test survives as an explicit fallback"

grep -q 'Say which test' "$REF" \
  && ok "a decline records which test produced it, so the weaker is not mistaken for the stronger" \
  || bad "a decline records which test produced it"

# The old whole-task condition must not still read as the primary trigger.
if grep -qE '^2\. \*\*Genuine domain miss\*\*' "$REF"; then
  bad "the whole-task test is still the primary Surface 1 trigger"
else
  ok "the whole-task test is no longer the primary Surface 1 trigger"
fi

# One offer per aspect — the sidecar is keyed by topic already.
grep -q 'one offer per aspect' "$REF" \
  && ok "the offer is per aspect rather than per task" \
  || bad "the offer is per aspect rather than per task"

# The three phase commands must not restate the trigger — restating it in four places is how
# Surface 1 and Surface 2 drifted apart in the first place.
for f in research design implement; do
  C="$ROOT/commands/$f.md"
  if grep -q 'Surface 1 trigger in .references/maintainer-create-on-miss.md. holds' "$C"; then
    ok "/$f defers to the reference for the trigger instead of restating it"
  else
    bad "/$f defers to the reference for the trigger instead of restating it"
  fi
  # Match the group name itself, not one phrasing of it: /research said "group
  # showed" where /design and /implement said "group was empty", so a pattern
  # keyed on the latter could never fail for /research — a check that cannot fail
  # for a third of its inputs.
  if grep -q 'Domain guides matched:' "$C"; then
    bad "/$f still carries its own copy of the old whole-task trigger"
  else
    ok "/$f no longer carries its own copy of the old whole-task trigger"
  fi
done

echo "----"
echo "create-on-miss-per-aspect-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
