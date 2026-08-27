#!/usr/bin/env bash
# The traceability walkthrough only ever walked one way.
#
# Step 2 asked "for each criterion, which section addresses it" and step 3 marked a criterion with
# nothing behind it as NOT YET ADDRESSED. Nothing asked the reverse: what is in the artifact that
# no criterion asked for. A scan that starts from the criteria list is structurally blind to a
# section nobody requested.
#
# Observed at the end of a live Phase 2: the mapping returned all nine criteria addressed, nothing
# missing — and walking the other way by hand surfaced a fixture row beyond the six the contract
# listed, plus a --dry-run flag no criterion mentioned. Both defensible, neither decided. Phase 4's
# spec review would have found the same two after they were built.
#
# It stays advisory. references/spec-axis-review.md settled that scope creep never hard-fails on
# its own, because an untraceable-to-what judgment produced false fails under unattended runs.
# That is a decision about severity, not about looking, and this walkthrough issues no verdict at
# all — it is opt-in and ends in [c]/[r]/[d].
#
# Exit: 0 = both walkthroughs carry both directions, and the reverse one still cannot block.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }

for w in design research; do
  W="$ROOT/references/$w-walkthrough.md"
  [ -f "$W" ] || { bad "$w-walkthrough.md exists"; continue; }

  # Direction 1 survives unchanged.
  grep -q 'NOT YET ADDRESSED' "$W" \
    && ok "$w: a criterion with nothing behind it is still marked NOT YET ADDRESSED" \
    || bad "$w: a criterion with nothing behind it is still marked NOT YET ADDRESSED"

  # Direction 2 exists.
  grep -q 'Then walk it the other way' "$W" \
    && ok "$w: the walkthrough also walks artifact to criteria" \
    || bad "$w: the walkthrough also walks artifact to criteria"

  grep -q 'UNASKED' "$W" \
    && ok "$w: something answering to no criterion is named UNASKED" \
    || bad "$w: something answering to no criterion is named UNASKED"

  grep -q 'invisible to a scan that starts from the criteria list' "$W" \
    && ok "$w: says why one direction cannot cover the other" \
    || bad "$w: says why one direction cannot cover the other"

  # And it cannot block — the severity decision in spec-axis-review.md stands.
  grep -q 'advisory and produces no verdict' "$W" \
    && ok "$w: the reverse walk is advisory and issues no verdict" \
    || bad "$w: the reverse walk is advisory and issues no verdict"

  grep -q 'about severity, not about looking' "$W" \
    && ok "$w: distinguishes the never-hard-fail rule from never looking" \
    || bad "$w: distinguishes the never-hard-fail rule from never looking"
done

# The Phase 4 rule it defers to must still say scope creep never drives the verdict alone.
S="$ROOT/references/spec-axis-review.md"
if grep -q 'never drives the verdict' "$S" && grep -q 'deliberate de-risking' "$S"; then
  ok "spec-axis-review still holds scope creep advisory at Phase 4"
else
  bad "spec-axis-review still holds scope creep advisory at Phase 4"
fi

echo "----"
echo "traceability-both-directions-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
