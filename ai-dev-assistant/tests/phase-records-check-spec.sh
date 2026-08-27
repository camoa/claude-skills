#!/usr/bin/env bash
# phase-records-check-spec.sh — the phase that was performed by hand.
#
# The bypass this guards is invisible in the terminal. A session reads the protocol, does the work
# itself, and produces a good answer; what goes missing is everything the skipped skill would have
# WRITTEN. Measured on one real task: three skills bypassed in a single phase, and manual inspection
# found only one of them.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="${PLUGIN_ROOT}/scripts/phase-records-check.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
[ -x "$K" ] || { printf 'FAIL: %s not executable\n' "$K" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
REQUIRED="_pre-analysis.json coverage-map.json _agentic-recipe.json _mechanism-challenge.json _dev-guides-load.json _playbook-load.json _internal-prior-art.json research.md"

mk() { local d="$T/$1"; mkdir -p "$d"; shift; for f in "$@"; do printf '{}' > "$d/$f"; done; printf '%s' "$d"; }
# Same, but every JSON record names the phase that wrote it. Presence alone stopped being the
# test in v5.30.3: a record is this phase's only if it says so.
mkp() { local d="$T/$1" ph="$2"; mkdir -p "$d"; shift 2
        for f in "$@"; do
          case "$f" in
            *.json) printf '{"gate_specific":{"phase":"%s"}}' "$ph" > "$d/$f" ;;
            *)      printf 'x' > "$d/$f" ;;
          esac
        done; printf '%s' "$d"; }

# --- every required record present ---------------------------------------------
# shellcheck disable=SC2086
FULL=$(mkp full research $REQUIRED)
OUT=$(bash "$K" "$FULL" --phase research)
[ "$(printf '%s' "$OUT" | jq -r .verdict)" = "complete" ] \
  && pass_check "a phase with every record reports complete" \
  || fail_check "a complete phase must report complete"

# --- the real case: three skills bypassed --------------------------------------
BYPASSED=$(mkp bypassed research _pre-analysis.json _agentic-recipe.json _dev-guides-load.json _playbook-load.json research.md)
OUT=$(bash "$K" "$BYPASSED" --phase research)
[ "$(printf '%s' "$OUT" | jq -r .verdict)" = "incomplete" ] \
  && pass_check "a hand-rolled phase is caught" \
  || fail_check "missing required records must report incomplete"
[ "$(printf '%s' "$OUT" | jq -r .missing_required)" = "3" ] \
  && pass_check "every bypassed component is counted, not just the first" \
  || fail_check "expected 3 missing, got $(printf '%s' "$OUT" | jq -r .missing_required)"

# The point of the check is not that something is missing — it is WHO did not run.
# "missing _internal-prior-art.json" is a puzzle; naming the skill is an instruction.
PRODUCER=$(printf '%s' "$OUT" | jq -r '.records[]|select(.name=="_internal-prior-art.json")|.producer')
printf '%s' "$PRODUCER" | grep -q 'internal-prior-art-finder' \
  && pass_check "a missing record names the skill that owed it" \
  || fail_check "each missing record must name its producer"
printf '%s' "$OUT" | jq -e '.records[]|select(.name=="coverage-map.json")|select(.step=="step 2c")' >/dev/null \
  && pass_check "a missing record names the step it belongs to" \
  || fail_check "each record must name its protocol step"

# --- an empty file is not a record ---------------------------------------------
# It parses as absent everywhere downstream, so counting it present hides the problem one layer on.
# shellcheck disable=SC2086
EMPTY=$(mk empty $REQUIRED)
: > "$EMPTY/_internal-prior-art.json"
OUT=$(bash "$K" "$EMPTY" --phase research)
[ "$(printf '%s' "$OUT" | jq -r '.records[]|select(.name=="_internal-prior-art.json")|.status')" = "empty" ] \
  && pass_check "an empty file is reported empty, not present" \
  || fail_check "an empty record must not count as present"
[ "$(printf '%s' "$OUT" | jq -r .verdict)" = "incomplete" ] \
  && pass_check "an empty required record still fails the phase" \
  || fail_check "an empty required record must not pass"

# --- conditional records never block -------------------------------------------
# A maintainer offer that did not fire is not a missing record.
# shellcheck disable=SC2086
OUT=$(bash "$K" "$(mkp cond research $REQUIRED)" --phase research)
[ "$(printf '%s' "$OUT" | jq -r .verdict)" = "complete" ] \
  && pass_check "absent conditional records do not block" \
  || fail_check "conditional records must never fail the phase"
[ "$(printf '%s' "$OUT" | jq -r '[.records[]|select(.requirement=="conditional")]|length')" -gt 0 ] \
  && pass_check "conditional records are still reported for visibility" \
  || fail_check "conditional records must be listed"

# --- an unknown phase is UNKNOWN, never complete -------------------------------
# A phase this script has no contract for has not been checked. Saying complete would make the
# check the same kind of confident wrong answer it exists to catch. All four lifecycle phases
# now have contracts, so this uses a name that is deliberately not one of them.
# shellcheck disable=SC2086
[ "$(bash "$K" "$(mkp other research $REQUIRED)" --phase deploy | jq -r .verdict)" = "unknown" ] \
  && pass_check "a phase with no encoded contract reports unknown" \
  || fail_check "an unchecked phase must never report complete"

# --- design and implement are checked, not waved through -----------------------
# Research was the only phase with a contract until v5.30.1. A live design phase ran this and
# got `unknown`: honest, and useless. The guardrail that had already caught one skipped gate
# could not look at the phase after it, or at implementation after that.
DESIGN_REQ="_phase-active.json _dev-guides-load.json _playbook-load.json architecture.md _mechanism-challenge.json"
IMPL_REQ="_phase-active.json _dev-guides-load.json _playbook-load.json implementation.md _mechanism-challenge.json _build-critique.json"

# shellcheck disable=SC2086
[ "$(bash "$K" "$(mkp dfull design $DESIGN_REQ)" --phase design | jq -r .verdict)" = "complete" ] \
  && pass_check "a design phase with every record reports complete" \
  || fail_check "design is checked but a complete one does not report complete"

# shellcheck disable=SC2086
[ "$(bash "$K" "$(mkp ifull implement $IMPL_REQ)" --phase implement | jq -r .verdict)" = "complete" ] \
  && pass_check "an implement phase with every record reports complete" \
  || fail_check "implement is checked but a complete one does not report complete"

# The gap that started this: a phase declaration that never landed in the task folder is the
# record whose absence made every bypass report `undetermined`.
DOUT=$(bash "$K" "$(mkp dgap design _dev-guides-load.json _playbook-load.json architecture.md)" --phase design)
[ "$(printf '%s' "$DOUT" | jq -r .verdict)" = "incomplete" ] \
  && pass_check "a design phase missing a required record reports incomplete" \
  || fail_check "a design phase missing a required record was waved through"
[ "$(printf '%s' "$DOUT" | jq -r '.records[]|select(.name=="_phase-active.json")|.producer')" \
  = "phase-active-write.sh with the task folder" ] \
  && pass_check "the missing design record names who was supposed to write it" \
  || fail_check "a missing design record is a puzzle rather than an instruction"

# The gate `/implement` calls "the unskippable catch" was not in its contract at all, so a phase
# that skipped it still read complete. Both phases run the challenge unconditionally.
for ph in design implement; do
  case "$ph" in
    design) OTHERS="_phase-active.json _dev-guides-load.json _playbook-load.json architecture.md" ;;
    *)      OTHERS="_phase-active.json _dev-guides-load.json _playbook-load.json implementation.md" ;;
  esac
  # shellcheck disable=SC2086
  MOUT=$(bash "$K" "$(mkp "nomech-$ph" "$ph" $OTHERS)" --phase "$ph")
  [ "$(printf '%s' "$MOUT" | jq -r .verdict)" = "incomplete" ] \
    && pass_check "a $ph phase with no mechanism-challenge record reports incomplete" \
    || fail_check "a $ph phase skipped the unskippable challenge and read complete"
  [ "$(printf '%s' "$MOUT" | jq -r '.records[]|select(.name=="_mechanism-challenge.json")|.requirement')" = "required" ] \
    && pass_check "the mechanism-challenge record is required for $ph, not conditional" \
    || fail_check "the mechanism-challenge record is not required for $ph, so its absence never counts"
done

# A contract answers what THIS phase owes. The epic check these phases run branches and stays
# silent; nothing in either command writes _pre-analysis.json, so listing it was a category error.
for ph in design implement; do
  [ "$(bash "$K" "$(mk "pa-$ph" _phase-active.json)" --phase "$ph" \
       | jq -r '[.records[]|select(.name=="_pre-analysis.json")]|length')" = "0" ] \
    && pass_check "$ph does not claim a record it never writes" \
    || fail_check "$ph's contract lists _pre-analysis.json, which belongs to research"
done

# --- a record belongs to the phase that wrote it --------------------------------------
# Presence was the whole test until v5.30.3, and every JSON record here is overwrite-on-fire
# and never deleted between phases. So a file written three phases back satisfied the contract
# of a phase that never ran the step. Observed live: _mechanism-challenge.json stamped
# `phase: design` counted as implementation's copy of the gate that command calls unskippable.

# shellcheck disable=SC2086
CARRIED=$(bash "$K" "$(mkp carried design $IMPL_REQ)" --phase implement)
[ "$(printf '%s' "$CARRIED" | jq -r '.records[]|select(.name=="_mechanism-challenge.json")|.status')" = "carried" ] \
  && pass_check "a design-written mechanism record reads as carried, not as implementation's own" \
  || fail_check "an earlier phase's mechanism record passed as this phase's"

[ "$(printf '%s' "$CARRIED" | jq -r '.records[]|select(.name=="_mechanism-challenge.json")|.written_by_phase')" = "design" ] \
  && pass_check "the record says which phase actually wrote it" \
  || fail_check "the record does not say which phase wrote it, so carried is unverifiable"

# Reuse is legitimate only where the contract allows it. Everything else is stale.
[ "$(printf '%s' "$CARRIED" | jq -r '.records[]|select(.name=="_dev-guides-load.json")|.status')" = "stale" ] \
  && pass_check "a non-carryable record from an earlier phase reads as stale" \
  || fail_check "an earlier phase's guides record passed as this phase's"

[ "$(printf '%s' "$CARRIED" | jq -r .verdict)" = "incomplete" ] \
  && pass_check "a phase whose required records all came from earlier is not complete" \
  || fail_check "a phase that ran no step of its own reported complete"

[ "$(printf '%s' "$CARRIED" | jq -r '.warnings|index("records_overwritten_by_a_later_phase")')" != "null" ] \
  && pass_check "the verdict says the records were an earlier phase's rather than never written" \
  || fail_check "a retrospective audit looks like a phase that skipped its work"

# A record naming no phase cannot be tied to this one. Required means that is not good enough.
# shellcheck disable=SC2086
NOPHASE=$(bash "$K" "$(mk nophase $IMPL_REQ)" --phase implement)
[ "$(printf '%s' "$NOPHASE" | jq -r '.records[]|select(.name=="_playbook-load.json")|.status')" = "unattributed" ] \
  && pass_check "a record that names no phase is unattributed, not present" \
  || fail_check "a record with no phase field was counted as this phase's"
[ "$(printf '%s' "$NOPHASE" | jq -r .verdict)" = "incomplete" ] \
  && pass_check "unattributed required records do not add up to complete" \
  || fail_check "records that cannot say who wrote them reported complete"

# A phase artifact is named for its phase, so there is nothing to attribute.
[ "$(printf '%s' "$NOPHASE" | jq -r '.records[]|select(.name=="implementation.md")|.status')" = "present" ] \
  && pass_check "a phase artifact needs no phase field to be attributed" \
  || fail_check "implementation.md was penalised for carrying no phase field"

# The count and the verdict must agree, whatever the failing status is.
[ "$(printf '%s' "$NOPHASE" | jq -r .missing_required)" -gt 0 ] \
  && pass_check "missing_required counts every required record that did not satisfy" \
  || fail_check "the verdict says incomplete while the count says nothing is missing"

# --- review has a contract of its own --------------------------------------------------
# Review was left without one when design and implement got theirs, so the last phase in the
# lifecycle — the one that decides whether the work ships — answered `unknown` about its own
# records for a whole live round.
REVIEW_REQ="_phase-active.json _review.json _spec.json _recipe-load.json _mechanism-challenge.json _internal-prior-art.json"
# shellcheck disable=SC2086
RV=$(bash "$K" "$(mkp rfull review $REVIEW_REQ)" --phase review)
[ "$(printf '%s' "$RV" | jq -r .verdict)" = "complete" ] \
  && pass_check "a review phase with every record reports complete" \
  || fail_check "review is checked but a complete one does not report complete"

[ "$(bash "$K" "$(mkp rgap review _review.json _spec.json _recipe-load.json _mechanism-challenge.json _internal-prior-art.json)" --phase review | jq -r .verdict)" = "incomplete" ] \
  && pass_check "a review that never declared its phase reports incomplete" \
  || fail_check "review can skip declaring its phase and still read complete"

# Review asserts the mechanism and prior-art records rather than writing them, so an earlier
# phase's copy is what it should find.
[ "$(printf '%s' "$RV" | jq -r '.records[]|select(.name=="_internal-prior-art.json")|.requirement')" = "required" ] \
  && pass_check "review requires the prior-art record it asserts" \
  || fail_check "review can pass without the prior-art search having been recorded"

# --- a record only one phase writes is attributed by its name --------------------------
# _review.json cannot be anyone's but review's, and these payloads never carried a phase field.
# Demanding one would invent a requirement rather than check one.
# shellcheck disable=SC2086
IMPL_BY_NAME=$(bash "$K" "$(mk rimplicit $REVIEW_REQ)" --phase review)
[ "$(printf '%s' "$IMPL_BY_NAME" | jq -r '.records[]|select(.name=="_review.json")|.status')" = "present" ] \
  && pass_check "a record only one phase writes needs no phase field" \
  || fail_check "_review.json was penalised for a field its payload never had"

# The exemption is per record, not blanket: a record that DOES carry a phase must still match.
[ "$(printf '%s' "$IMPL_BY_NAME" | jq -r '.records[]|select(.name=="_phase-active.json")|.status')" = "unattributed" ] \
  && pass_check "the by-name exemption does not leak to records that carry a phase" \
  || fail_check "every record became exempt, so attribution stopped meaning anything"

# Neither phase may report complete on an empty task folder.
for ph in design implement; do
  [ "$(bash "$K" "$(mk "empty-$ph")" --phase "$ph" | jq -r .verdict)" = "incomplete" ] \
    && pass_check "an empty task folder is incomplete for $ph" \
    || fail_check "an empty task folder reported something other than incomplete for $ph"
done

# --- defensive posture ----------------------------------------------------------
bash "$K" "$T/nope" --phase research | jq empty >/dev/null 2>&1 \
  && pass_check "a missing task folder still emits valid JSON" \
  || fail_check "must always emit valid JSON"
[ "$(bash "$K" "$T/nope" --phase research | jq -r .verdict)" = "unknown" ] \
  && pass_check "a missing task folder is unknown, not complete" \
  || fail_check "a missing folder must not report complete"

if [ "$FAIL" -ne 0 ]; then
  printf '\nSome invariants FAILED for scripts/phase-records-check.sh.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/phase-records-check.sh.\n'
exit 0
