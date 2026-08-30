#!/usr/bin/env bash
# command-body-lengths-spec.sh — runs the phase-command body ratchet, and
# proves it can fail.
#
# scripts/command-body-lengths.sh was added in v4.0.2 and called by nothing —
# not the Makefile, not a test, not CI — until v5.35.7. Over those four months
# three of its five budgets went stale, one of them by 3x, and no run said so.
# This spec is what makes it a check: `make test` discovers */tests/*.sh, and
# `make ci` runs `make test`.
#
# Wiring it in is only half the job. A check nothing proves can fail is the
# same defect one layer up, so the mutations below seed each failure mode
# against a COPY of commands/ and assert red. The real tree is never mutated:
# every mutation runs against a temp fixture via COMMAND_BODY_LENGTHS_DIR.
#
# Exit 0 on all-pass; 1 on any fail.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/command-body-lengths.sh"
COMMANDS="${PLUGIN_ROOT}/commands"
REVIEW_SPEC="${PLUGIN_ROOT}/tests/review-command-spec.sh"

FAIL=0
RED_COUNT=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

if [ ! -f "$SCRIPT" ]; then
  printf 'FAIL: %s not found\n' "$SCRIPT" >&2
  exit 1
fi

# Runs the ratchet against a directory and reports rc + output.
# Never aborts the spec on a non-zero rc; that is what half these cases expect.
run_ratchet() {
  local dir="$1"; shift
  local rc=0 out=""
  set +e
  out=$(COMMAND_BODY_LENGTHS_DIR="$dir" bash "$SCRIPT" "$@" 2>&1)
  rc=$?
  set -e
  RUN_OUT="$out"
  RUN_RC="$rc"
}

# Asserts a mutation produced red, and counts it. A mutation that comes back
# green is the finding, so it is a failure of this spec and not a skip.
expect_red() {
  local label="$1" needle="$2"
  if [ "$RUN_RC" -eq 0 ]; then
    fail_check "mutation did not fail the check: $label (exit 0)"
    return
  fi
  if ! printf '%s' "$RUN_OUT" | grep -qF -- "$needle"; then
    fail_check "mutation failed but for the wrong reason: $label (no '$needle' in output)"
    return
  fi
  RED_COUNT=$((RED_COUNT + 1))
  pass_check "mutation red: $label (exit $RUN_RC, reported '$needle')"
}

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ── 1. The real tree is within budget ────────────────────────────────────────
run_ratchet "$COMMANDS"
if [ "$RUN_RC" -eq 0 ]; then
  pass_check "commands/ within budget"
else
  fail_check "commands/ over budget:"$'\n'"$RUN_OUT"
fi

# Every phase reported, none missing. Guards against a green produced by the
# loop silently skipping a file.
for phase in research design implement complete review; do
  if printf '%s' "$RUN_OUT" | grep -qE "^${phase} +[0-9]+ / +[0-9]+ lines  ok$"; then
    pass_check "measured phase: $phase"
  else
    fail_check "phase not measured: $phase"
  fi
done

# ── 2. Mutation: a body over its budget ──────────────────────────────────────
# One line past the ratchet is the case the whole script exists for, so the
# seeded overrun is deliberately minimal: budget + 1, not budget + 200.
FIX="${TMP}/over"
cp -R "$COMMANDS" "$FIX"
printf '\nseeded overrun line\n' >> "${FIX}/implement.md"
run_ratchet "$FIX"
expect_red "implement.md one line over budget" "over"

# The same mutation on a different command, so the red is not a property of
# one file's frontmatter shape.
FIX2="${TMP}/over2"
cp -R "$COMMANDS" "$FIX2"
printf '\nseeded overrun line\n' >> "${FIX2}/complete.md"
run_ratchet "$FIX2"
expect_red "complete.md one line over budget" "over"

# ── 3. Mutation: a named command is missing ──────────────────────────────────
FIX3="${TMP}/missing"
cp -R "$COMMANDS" "$FIX3"
rm -f "${FIX3}/research.md"
run_ratchet "$FIX3"
expect_red "research.md absent" "MISSING"

# ── 4. Mutation: nothing to check at all ─────────────────────────────────────
# The repo rule is that a check which found nothing has not passed.
FIX4="${TMP}/empty"
mkdir -p "$FIX4"
run_ratchet "$FIX4"
expect_red "no command files present" "measured no command bodies"

# ── 5. Restore: the unmutated copy is green again ────────────────────────────
# Proves the red above came from the mutation and not from the fixture copy.
FIX5="${TMP}/clean"
cp -R "$COMMANDS" "$FIX5"
run_ratchet "$FIX5"
if [ "$RUN_RC" -eq 0 ]; then
  pass_check "unmutated copy of commands/ is green"
else
  fail_check "unmutated copy is red, so the mutations above prove nothing:"$'\n'"$RUN_OUT"
fi

# ── 7. --budget is a real interface, so the review budget has one home ───────
BUDGET_RC=0
set +e
REVIEW_BUDGET=$(bash "$SCRIPT" --budget review 2>&1); BUDGET_RC=$?
set -e
if [ "$BUDGET_RC" -eq 0 ] && printf '%s' "$REVIEW_BUDGET" | grep -qE '^[0-9]+$'; then
  pass_check "--budget review printed $REVIEW_BUDGET"
else
  fail_check "--budget review did not print a number (exit $BUDGET_RC): $REVIEW_BUDGET"
fi

set +e
bash "$SCRIPT" --budget nosuchphase >/dev/null 2>&1; UNKNOWN_RC=$?
set -e
if [ "$UNKNOWN_RC" -ne 0 ]; then
  pass_check "--budget on an unknown phase exits $UNKNOWN_RC"
else
  fail_check "--budget on an unknown phase exited 0"
fi

# review-command-spec.sh must READ that number rather than mirror it. A budget
# recorded in two files is one edit away from the two disagreeing, which is
# what happened at v5.35.5: the spec enforced 131 while this script still said
# 129, and nothing noticed because nothing ran this script.
#
# Two conditions, because either alone passes the wrong file: it must call
# --budget, AND it must no longer compare BODY_LINES against a literal. A spec
# that does both still has a mirror.
derives_budget() {
  local f="$1"
  grep -qF -- 'command-body-lengths.sh' "$f" || return 1
  grep -qF -- '--budget review' "$f" || return 1
  grep -qE '"\$BODY_LINES" -le [0-9]+' "$f" && return 1
  return 0
}

if [ ! -f "$REVIEW_SPEC" ]; then
  fail_check "review-command-spec.sh not found at $REVIEW_SPEC"
elif derives_budget "$REVIEW_SPEC"; then
  pass_check "review-command-spec.sh derives its budget from the script"
else
  fail_check "review-command-spec.sh does not derive its budget; the number is mirrored again"
fi

# The anti-mirror assertion above is a grep, so prove the grep can say no:
# reintroduce a mirrored literal in a COPY and require it to reject that copy.
MIRRORED="${TMP}/review-command-spec-mirrored.sh"
sed 's/"\$BODY_LINES" -le "\$BUDGET"/"$BODY_LINES" -le 135/' "$REVIEW_SPEC" > "$MIRRORED"
if ! grep -qE '"\$BODY_LINES" -le [0-9]+' "$MIRRORED"; then
  fail_check "could not seed a mirrored budget, so the anti-mirror check is unproven"
elif derives_budget "$MIRRORED"; then
  fail_check "anti-mirror check accepted a spec with a mirrored literal budget"
else
  RED_COUNT=$((RED_COUNT + 1))
  pass_check "mutation red: mirrored literal budget rejected"
fi

# ── 8. --json stays machine-readable ─────────────────────────────────────────
run_ratchet "$COMMANDS" --json
if printf '%s' "$RUN_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if len(d)==5 and all("lines" in e and "budget" in e for e in d) else 1)'; then
  pass_check "--json emits 5 well-formed entries"
else
  fail_check "--json output is not 5 well-formed entries: $RUN_OUT"
fi

# ── 9. Asserted red count ────────────────────────────────────────────────────
# Written out, not derived from the loop that produced it: a count that counts
# whatever happened cannot tell you a mutation stopped landing.
EXPECTED_RED=5
if [ "$RED_COUNT" -eq "$EXPECTED_RED" ]; then
  pass_check "mutation red count $RED_COUNT of $EXPECTED_RED"
else
  fail_check "mutation red count $RED_COUNT, expected $EXPECTED_RED"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\ncommand body length ratchet spec failed.\n' >&2
  exit 1
fi

printf '\nAll checks pass; %d of %d mutations confirmed red.\n' "$RED_COUNT" "$EXPECTED_RED"
exit 0
