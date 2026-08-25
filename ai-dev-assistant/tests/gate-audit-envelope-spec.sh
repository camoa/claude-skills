#!/usr/bin/env bash
# gate-audit-envelope-spec.sh — the envelope a caller cannot be trusted to write.
#
# Two failures observed on the same live run, one cause. The writer took only a complete
# envelope, and the call site said "write the audit via gate-audit-write.sh" without ever
# showing what an envelope looks like, so the run passed the gate_specific object on its
# own, got "schema_version must be one of ... (got \"\")", and had to open the script to
# recover. That is a round-trip per gate, per run.
#
# The second failure is the one that cost real time. Because the envelope was authored by
# hand on every call, `fired_at` was authored by hand too — and a model has no clock. Every
# gate audit this framework had ever written said midnight. When a task folder was later
# reset half-way, a genuine coverage pass was left standing beside a research.md that no
# longer existed, and the timestamps that would have separated "stale" from "fabricated"
# all read 00:00:00Z. A correct session accused itself of forging its own audit trail.
#
# So: the clock belongs to the script, and a caller-supplied fired_at is discarded.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
[ -f "$W" ] || { printf 'FAIL: %s missing\n' "$W" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# ---------------------------------------------------------------- bare payload accepted

# The exact shape the live run reached for and had rejected.
if bash "$W" "$T" pre-analysis \
   '{"decision":"keep_flat","confidence":"high","code_read":true,"user_choice":"y"}' >/dev/null 2>&1; then
  pass_check "a bare gate_specific object is accepted"
else
  fail_check "a bare gate_specific object was rejected — the call site's natural shape must work"
fi

A="$T/_pre-analysis.json"
if [ -f "$A" ]; then
  [ "$(jq -r '.gate_type' "$A")" = "pre-analysis" ] \
    && pass_check "wrapped payload carries gate_type" \
    || fail_check "wrapped payload lost gate_type"
  [ "$(jq -r '.schema_version' "$A")" = "1.0" ] \
    && pass_check "schema_version derived from gate_type" \
    || fail_check "schema_version not derived (got $(jq -r '.schema_version' "$A"))"
  [ "$(jq -r '.task_folder' "$A")" = "$T" ] \
    && pass_check "task_folder filled from the argument" \
    || fail_check "task_folder not filled"
  [ "$(jq -r '.gate_specific.decision' "$A")" = "keep_flat" ] \
    && pass_check "the bare object became gate_specific" \
    || fail_check "gate_specific did not receive the bare object"

  # Envelope-level per gate-audit-schema.md section 4. Buried inside gate_specific it is
  # invisible to every consumer that reads the envelope, which is how a coverage audit
  # came to record its user_choice where nothing looks for it.
  [ "$(jq -r '.user_choice' "$A")" = "y" ] \
    && pass_check "user_choice hoisted to the envelope" \
    || fail_check "user_choice not hoisted"
  [ "$(jq -r '.gate_specific.user_choice // "absent"' "$A")" = "absent" ] \
    && pass_check "user_choice removed from gate_specific once hoisted" \
    || fail_check "user_choice left duplicated inside gate_specific"
  [ "$(jq -r '.bypass_reason' "$A")" = "null" ] \
    && pass_check "bypass_reason defaults to null" \
    || fail_check "bypass_reason not defaulted"
else
  fail_check "no audit file written for the bare payload"
fi

# ------------------------------------------------------------------- the clock is here

# A caller-supplied fired_at is discarded in the full-envelope path too. This is the
# assertion that would have failed on every version of this script before v5.30.0.
bash "$W" "$T" spec "$(jq -nc --arg tf "$T" '{schema_version:"1.0", gate_type:"spec",
  fired_at:"2026-07-09T00:00:00Z", task_folder:$tf, user_choice:null, bypass_reason:null,
  gate_specific:{verdict:"pass"}}')" >/dev/null 2>&1 || fail_check "full envelope stopped working"
: # keep going even when the write above failed — later checks still carry information

S="$T/_spec.json"
if [ -f "$S" ]; then
  GOT=$(jq -r '.fired_at' "$S")
  [ "$GOT" != "2026-07-09T00:00:00Z" ] \
    && pass_check "a caller-supplied fired_at is discarded" \
    || fail_check "caller-supplied fired_at survived — the clock is still the caller's"
  # Not merely different: a real UTC instant, and never midnight-by-default.
  printf '%s' "$GOT" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
    && pass_check "fired_at is ISO-8601 UTC with the Z suffix" \
    || fail_check "fired_at is not ISO-8601 UTC (got $GOT)"
  [ "$(jq -r '.gate_specific.verdict' "$S")" = "pass" ] \
    && pass_check "full-envelope gate_specific passes through untouched" \
    || fail_check "full-envelope gate_specific was mangled"
fi

# Two writes seconds apart must be orderable — the property the midnight stamps destroyed.
bash "$W" "$T" playbook-load '{"playbook_sets_loaded":[]}' >/dev/null 2>&1 || true
if [ -f "$T/_playbook-load.json" ]; then
  F1=$(jq -r '.fired_at' "$T/_playbook-load.json")
  [ "$F1" != "$(date -u +%Y-%m-%dT00:00:00Z)" ] \
    && pass_check "a deterministic gate does not stamp midnight" \
    || fail_check "still stamping midnight"
else
  fail_check "a deterministic gate wrote no audit at all"
fi

# ------------------------------------------------------------------ rejections intact

# `set -e` would abort on these deliberate non-zero exits, so capture rather than test $?.
rc() { local r=0; bash "$W" "$@" >/dev/null 2>&1 || r=$?; printf '%s' "$r"; }

[ "$(rc "$T" pre-analysis 'not json')" = 2 ] \
  && pass_check "unparseable payload still exits 2" || fail_check "unparseable payload no longer rejected"

[ "$(rc "$T" bogus-gate '{"a":1}')" = 2 ] \
  && pass_check "unknown gate_type still exits 2" || fail_check "unknown gate_type no longer rejected"

# A JSON scalar is not an object and must not be wrapped into a nonsense envelope.
[ "$(rc "$T" pre-analysis '"just a string"')" = 2 ] \
  && pass_check "a non-object payload exits 2" || fail_check "a non-object payload was wrapped"

# A full envelope whose gate_type disagrees with the argument is still a caller bug.
MISMATCH=$(jq -nc --arg tf "$T" '{schema_version:"1.0", gate_type:"review",
  fired_at:"x", task_folder:$tf, gate_specific:{}}')
[ "$(rc "$T" pre-analysis "$MISMATCH")" = 2 ] \
  && pass_check "mismatched gate_type still exits 2" || fail_check "mismatched gate_type no longer rejected"

# ------------------------------------------------------------------- the call site says so

# The defect was half in the script and half in the instruction. A caller told only to
# "write the audit via gate-audit-write.sh" guesses the shape, which is what happened.
if grep -q 'gate_specific object on its own' "$W"; then
  pass_check "the writer's usage header states the accepted shapes"
else
  fail_check "the usage header still does not say a bare gate_specific object is accepted"
fi

# ------------------------------------------------- the record is written after the answer

# Observed live: /research step 1 wrote _pre-analysis.json, THEN displayed the prompt and
# blocked. The audit was on disk before a choice existed, and nothing told the run to update
# it afterwards — so it patched the file by hand, putting user_choice inside gate_specific
# (section 4 says envelope) with the value "proceed_flat" (the enum is y/n/s/bypassed). The
# atomic writer was right there and the run edited around it, because the step's own ordering
# left nowhere to put the answer.
STEP1=$(sed -n '/^1\. \*\*Pre-analysis gate/,/^2\. /p' "$PLUGIN_ROOT/commands/research.md")
# Step 1 is a single markdown line, so compare character offsets, not line numbers.
BLOCK_AT=$(printf '%s' "$STEP1" | awk '{i=index($0,"Block on choice"); if(i){print NR"."i; exit}}')
WRITE_AT=$(printf '%s' "$STEP1" | awk '{i=index($0,"gate-audit-write.sh"); if(i){print NR"."i; exit}}')
if [ -n "$BLOCK_AT" ] && [ -n "$WRITE_AT" ]; then
  # "<line>.<column>" sorts correctly as a version string.
  [ "$(printf '%s\n%s\n' "$BLOCK_AT" "$WRITE_AT" | sort -V | head -1)" = "$BLOCK_AT" ] \
    && pass_check "step 1 blocks on the choice before writing the audit" \
    || fail_check "step 1 still writes the audit before blocking — the record cannot hold the choice"
else
  fail_check "step 1 no longer names both the block and the writer"
fi

printf '%s' "$STEP1" | grep -q 'never patch the audit file after the writer has run' \
  && pass_check "step 1 forbids hand-patching the audit" \
  || fail_check "step 1 does not forbid hand-patching the audit"

printf '%s' "$STEP1" | grep -q '`y` / `n` / `s` / `bypassed`' \
  && pass_check "step 1 names the user_choice enum" \
  || fail_check "step 1 does not name the user_choice enum, so a paraphrase gets recorded"

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'gate-audit-envelope-spec: all checks passed\n'; exit 0; }
printf 'gate-audit-envelope-spec: FAILURES\n' >&2; exit 1
