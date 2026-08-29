#!/usr/bin/env bash
# review-contract-drift-spec.sh — the goalposts can move during the review too.
#
# v5.34.0 froze the contract in front of the BUILD, because a builder can edit `alignment.md` and
# `architecture/` and a scope question then resolves against text written to describe the code it
# is judging. Everything in that argument applies to `/review`, which reads the same two documents
# at the moment each gate fires, and can edit them.
#
# Observed live: a review found a defect, corrected the two architecture documents that had
# specified the defective behaviour, and DELETED four acceptance criteria describing a check that
# was withdrawn — between one run of the Spec gate and the next. Every one of those edits was
# right. None was recorded. A criterion that no longer exists cannot be reported as unimplemented,
# so removing one during review silently retires a thing the Spec gate exists to check.
#
# The posture is the same as the build's and the script already states it: editing the contract is
# legitimate, editing it invisibly is not. This never blocks. The one non-advisory consequence is
# that a Spec verdict computed against a superseded criteria list is stale, and a stale verdict
# must not be reported as a current one.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CB="${PLUGIN_ROOT}/scripts/contract-baseline.sh"
REVIEW="${PLUGIN_ROOT}/commands/review.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
for f in "$CB" "$REVIEW"; do [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }; done
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

mktask() {
  local d; d=$(mktemp -d "$T/task.XXXXXX")
  mkdir -p "$d/architecture"
  printf '### Success criteria\n- [ ] one\n- [ ] two\n' > "$d/alignment.md"
  printf '# design\nthe checker returns Finished when the window is empty\n' > "$d/architecture/main.md"
  printf '%s' "$d"
}

# --- review has a baseline of its own ---------------------------------------------
D=$(mktask)
OUT=$(bash "$CB" capture "$D" --slot review 2>/dev/null) || OUT='{}'
[ "$(jq -r '.status' <<<"$OUT")" = "captured" ] \
  && pass_check "review can capture a contract baseline" \
  || fail_check "capture --slot review must capture, got $(jq -r '.status' <<<"$OUT")"

# --- it does not collide with the build's -----------------------------------------
# The two answer different questions: the build's asks whether the design moved while the code was
# written, review's asks whether it moved while the code was judged. Sharing one would report the
# build's own legitimate amendments as review drift, and capture refuses to overwrite — which is
# the property that makes a baseline mean anything.
OUT=$(bash "$CB" capture "$D" 2>/dev/null) || OUT='{}'
[ "$(jq -r '.status' <<<"$OUT")" = "captured" ] \
  && pass_check "the build baseline is still capturable after review's" \
  || fail_check "the two slots must be independent, build capture got $(jq -r '.status' <<<"$OUT")"

# --- an unchanged contract reports unchanged --------------------------------------
OUT=$(bash "$CB" diff "$D" --slot review 2>/dev/null) || OUT='{}'
[ "$(jq -r '.status' <<<"$OUT")" = "unchanged" ] \
  && pass_check "a review that changed nothing reports unchanged" \
  || fail_check "an untouched contract must report unchanged, got $(jq -r '.status' <<<"$OUT")"

# --- an amended architecture document is seen -------------------------------------
# The live case: the document specified the defective behaviour and had to be corrected.
printf '# design\nan unlimited rule is never finished\n' > "$D/architecture/main.md"
OUT=$(bash "$CB" diff "$D" --slot review 2>/dev/null) || OUT='{}'
[ "$(jq -r '.status' <<<"$OUT")" = "changed" ] \
  && pass_check "an architecture document corrected during review is recorded" \
  || fail_check "an amended architecture doc must be visible, got $(jq -r '.status' <<<"$OUT")"
jq -e '(.changed // []) | index("architecture/main.md")' <<<"$OUT" >/dev/null 2>&1 \
  && pass_check "the record names which document moved" \
  || fail_check "the drift record must name the file"

# --- a deleted success criterion is seen ------------------------------------------
# The sharpest case, and the one that happened. Four acceptance criteria were removed because the
# check they described was withdrawn. Correct, and invisible.
D2=$(mktask)
bash "$CB" capture "$D2" --slot review >/dev/null 2>&1
printf '### Success criteria\n- [ ] one\n' > "$D2/alignment.md"
OUT=$(bash "$CB" diff "$D2" --slot review 2>/dev/null) || OUT='{}'
[ "$(jq -r '.status' <<<"$OUT")" = "changed" ] \
  && pass_check "a success criterion deleted during review is recorded" \
  || fail_check "a removed criterion must not be invisible, got $(jq -r '.status' <<<"$OUT")"
jq -e '(.changed // []) | index("alignment.md")' <<<"$OUT" >/dev/null 2>&1 \
  && pass_check "the record names alignment.md, which is what makes the Spec verdict stale" \
  || fail_check "alignment.md must appear in changed[] when a criterion is removed"

# --- a baseline that was never captured says so, rather than reporting clean -------
# The failure that would make this whole check decorative: no capture, and diff answering
# "nothing changed" because it has nothing to compare.
D3=$(mktask)
OUT=$(bash "$CB" diff "$D3" --slot review 2>/dev/null) || OUT='{}'
[ "$(jq -r '.status' <<<"$OUT")" != "unchanged" ] \
  && pass_check "diff without a baseline does not report unchanged" \
  || fail_check "an uncaptured baseline must never read as a clean contract"

# --- both halves of the wiring are in the command ---------------------------------
# The defect fixed alongside this one was a command calling a script with an argument the script
# rejected, for five releases, because nothing compared the caller with the callee.
grep -q 'contract-baseline.sh" capture .*--slot review' "$REVIEW" \
  && pass_check "/review captures its baseline before the gates run" \
  || fail_check "review.md must capture a review-slot baseline at step 0"
grep -q 'contract-baseline.sh" diff .*--slot review' "$REVIEW" \
  && pass_check "/review diffs that baseline after the gates report" \
  || fail_check "review.md must diff the review-slot baseline before aggregating"
grep -q 'contract_drift' "$REVIEW" \
  && pass_check "the drift lands in the review record" \
  || fail_check "review.md must record contract_drift in _review.json"

# The one non-advisory consequence, stated where the reader of the command finds it.
grep -q 'Re-run 5.0d' "$REVIEW" \
  && pass_check "an amended alignment.md forces the Spec gate to be re-run or marked unresolved" \
  || fail_check "review.md must say a Spec verdict against a superseded contract is stale"

# --- the slot argument is validated ------------------------------------------------
RC=0; bash "$CB" capture "$D" --slot nonsense >/dev/null 2>&1 || RC=$?
[ "$RC" = "2" ] \
  && pass_check "an unknown slot is a usage error, not a silent third baseline" \
  || fail_check "an unknown slot must exit 2, got $RC"

if [ "$FAIL" = "0" ]; then
  printf '\nAll invariants pass for review contract drift.\n'
else
  printf '\nreview-contract-drift-spec: FAILURES\n' >&2
  exit 1
fi
