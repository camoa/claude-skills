#!/usr/bin/env bash
# build-critique-wiring-spec.sh — the Phase 3 build got an outside eye, and the wiring for it
# has to be real in the three places a run actually touches: the writer, the command body, and
# the record contract.
#
# THE DEFECT THIS DEFENDS AGAINST. Adversarial review existed twice in this plugin and neither
# copy could reach an in-session build. `wo-critic` fires only inside `/run-work-orders` and the
# work-order loop skills; `spec-axis-reviewer` fires only in Phase 4. A task that declined the
# work-order offer therefore had no outside eye on its build at all, from the first line written
# to the Phase 4 gate — and the offer itself never said so, selling isolation and parallelism
# while quietly also declining the only critic on the path. What `/implement` did activate,
# `tdd-companion` and `code-pattern-checker`, are skills the builder runs on itself in its own
# context. A builder holding its own reasoning cannot be surprised by it, which is the entire
# value a critic supplies.
#
# The rung closes it by REUSING that stack per architecture component rather than growing a
# second one, plus one end-of-phase alignment pass. Three things can silently un-wire it:
#
#   1. the writer stops accepting `build-critique`, or its required-key list quietly shrinks so
#      a payload can omit the counts that make a partial run legible;
#   2. the command body loses the instruction — the checkpoint capture/clear, the fresh (never
#      forked) critic, reading the verdict off disk rather than off a Task return, the blocking
#      posture — and the rung becomes a name in a changelog;
#   3. the contract, the schema and the writer drift apart, so the record a run writes and the
#      record a consumer reads are different records.
#
# So the required-key comparison below is DERIVED from both files rather than hardcoded: it is
# meant to keep holding when the contract changes, and to fail the day the two sides disagree.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"
CONTRACT="${PLUGIN_ROOT}/references/build-critique.md"
SCHEMA="${PLUGIN_ROOT}/references/gate-audit-schema.md"
CMD="${PLUGIN_ROOT}/commands/implement.md"
PRC="${PLUGIN_ROOT}/scripts/phase-records-check.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$W" "$CONTRACT" "$SCHEMA" "$CMD" "$PRC"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# A payload that satisfies every key the schema's build-critique table marks required.
GOOD='{"phase":"implement","verdict":"pass",
 "components":[{"component":"main","runtime":"executed","risk_tier":"low","lenses":["skeptic"],"verdict":"pass",
   "blocking":false,"findings_count":0,"checkpoint_before":"aaa","checkpoint_after":"bbb",
   "critique_ref":"/x/build-critique/main.critique.json"}],
 "components_declared":1,"components_critiqued":1,"uncritiqued":[],
 "tdd":{"red_observed":1,"passed_first_run":0,"unobserved":[]},
 "contract":{"baseline":"captured","changed":[]},
 "integration":{"ran":false,"reason":"single-component fixture"},
 "alignment":{"verdict":"pass","missing_requirements":[],"scope_creep":[],"spec_ref":null}}'

# ------------------------------------------------------------------ 1. the gate type is wired

mkdir -p "$T/ok"
if bash "$W" "$T/ok" build-critique "$GOOD" >"$T/ok.out" 2>"$T/ok.err"; then
  pass_check "gate-audit-write accepts build-critique as a gate_type"
else
  fail_check "gate-audit-write rejected build-critique (exit $?) — the rung cannot write its record"
fi

REC="$T/ok/_build-critique.json"
if [ -f "$REC" ]; then
  pass_check "it writes _build-critique.json into the task folder"
else
  fail_check "no _build-critique.json written — the filename the contract and phase-records-check name does not appear"
fi

if [ -f "$REC" ]; then
  SV=$(jq -r '.schema_version // empty' "$REC")
  [ "$SV" = "1.9" ] \
    && pass_check "a bare payload defaults to schema_version 1.9" \
    || fail_check "build-critique defaulted to schema_version \"$SV\", not 1.9"

  GT=$(jq -r '.gate_type // empty' "$REC")
  [ "$GT" = "build-critique" ] \
    && pass_check "the envelope's gate_type is build-critique" \
    || fail_check "envelope gate_type is \"$GT\""

  REAL_VERSION=$(jq -r '.version' "${PLUGIN_ROOT}/.claude-plugin/plugin.json")
  PV=$(jq -r '.plugin_version // empty' "$REC")
  [ "$PV" = "$REAL_VERSION" ] \
    && pass_check "the envelope carries plugin_version ($REAL_VERSION) — the record can say which build critiqued" \
    || fail_check "plugin_version is \"$PV\", expected $REAL_VERSION"
fi

# 1.9 must be in the ACCEPTED-version list, not merely produced as a default. Asserted on a
# gate whose own default is 1.2, so only the accepted list can let it through.
mkdir -p "$T/sv"
if bash "$W" "$T/sv" review \
  '{"schema_version":"1.9","gate_type":"review","task_folder":"/x","gate_specific":{"verdict":"pass"}}' \
  >/dev/null 2>&1; then
  pass_check "schema_version 1.9 is in the accepted-version list"
else
  fail_check "an explicit schema_version 1.9 was rejected — the version list did not learn 1.9"
fi

# The allowlist must not have become permissive on the way to accepting one more member.
mkdir -p "$T/bad"
set +e
bash "$W" "$T/bad" build-critiquez "$GOOD" >/dev/null 2>&1
RC=$?
set -e
[ "$RC" = "2" ] \
  && pass_check "an unknown gate_type is still rejected exit 2 (the allowlist is still a list)" \
  || fail_check "unknown gate_type exited $RC, expected 2 — the allowlist went permissive"

# ------------------------------------------------- 2. every required key is checked on its own
#
# Tested key by key, and deliberately NOT derived from the writer: a list derived from the thing
# under test cannot notice the list shrinking. Each key is dropped from an otherwise complete
# payload and the warning must name exactly that key.

mkdir -p "$T/keys"
for K in phase verdict components components_declared components_critiqued alignment tdd contract; do
  PAY=$(printf '%s' "$GOOD" | jq -c --arg k "$K" 'del(.[$k])')
  set +e
  bash "$W" "$T/keys" build-critique "$PAY" >/dev/null 2>"$T/keys/$K.err"
  KRC=$?
  set -e
  if [ "$KRC" != "0" ]; then
    fail_check "dropping \"$K\" made the writer exit $KRC; the payload posture is warn-and-write, not reject"
    continue
  fi
  if grep -qE "missing documented key\(s\): *${K}\$" "$T/keys/$K.err"; then
    pass_check "a payload with no \"$K\" is warned about, naming $K"
  else
    fail_check "no warning naming \"$K\" — build-critique's required-key list no longer covers it"
  fi
done

# The complement: a fully conformant payload must warn about nothing, or the warning above
# carries no information.
if grep -q "missing documented key" "$T/ok.err"; then
  fail_check "a complete payload still warned: $(cat "$T/ok.err")"
else
  pass_check "a payload carrying every documented key writes clean"
fi

# ------------------------------------------- 3. the contract, the schema and the writer agree
#
# Both sides derived from the files so this survives the contract changing.

# Anchor on the heading TEXT, not its number. The section numbers in this schema are
# hand-maintained and have already collided once (two ### 5.17 headings existed at the same
# time), so a spec pinned to a number breaks on a renumber that changed nothing it tests.
SCHEMA_SEC=$(awk '/^### [0-9.]+ `build-critique`/{f=1;next} f&&/^### /{exit} f' "$SCHEMA")
if [ -n "$SCHEMA_SEC" ]; then
  pass_check "the schema carries a build-critique section"
else
  fail_check "no '### <n> \`build-critique\`' section in gate-audit-schema.md"
fi

SCHEMA_REQ=$(printf '%s\n' "$SCHEMA_SEC" \
  | grep -E '^\| *`[a-z_]+(\[\])?` *\| *yes *\|' \
  | sed -E 's/^\| *`([a-z_]+)(\[\])?` *\|.*/\1/' | sort -u || true)
WRITER_REQ=$(grep -E '^ *build-critique\).*REQUIRED_KEYS=' "$W" \
  | sed -E 's/.*REQUIRED_KEYS="([^"]*)".*/\1/' | tr ' ' '\n' | grep -v '^$' | sort -u || true)

if [ -n "$SCHEMA_REQ" ] && [ -n "$WRITER_REQ" ]; then
  pass_check "both required-key lists were derivable from their own files"
else
  fail_check "could not derive one of the required-key lists (schema:[$SCHEMA_REQ] writer:[$WRITER_REQ])"
fi

UNCHECKED=$(comm -23 <(printf '%s\n' "$SCHEMA_REQ") <(printf '%s\n' "$WRITER_REQ") | tr '\n' ' ' | sed 's/ *$//')
if [ -z "$UNCHECKED" ]; then
  pass_check "every gate_specific key the schema marks required is in the writer's REQUIRED_KEYS"
else
  fail_check "schema marks these required and the writer never checks for them: $UNCHECKED"
fi

UNDOCUMENTED=$(comm -13 <(printf '%s\n' "$SCHEMA_REQ") <(printf '%s\n' "$WRITER_REQ") | tr '\n' ' ' | sed 's/ *$//')
if [ -z "$UNDOCUMENTED" ]; then
  pass_check "the writer demands nothing the schema does not mark required"
else
  fail_check "writer requires keys the schema does not mark required: $UNDOCUMENTED"
fi

# The two documents must offer the same verdict vocabulary, or a run writes a verdict its
# reader does not recognise.
CONTRACT_VERDICTS=$(grep -E '^\| *`verdict` *\| *enum' "$CONTRACT" \
  | sed -E 's/^\| *`verdict` *\| *enum *\| *//' \
  | grep -oE '`[a-z]+`' | tr -d '`' | sort -u | tr '\n' ' ' | sed 's/ *$//' || true)
SCHEMA_VERDICTS=$(printf '%s\n' "$SCHEMA_SEC" \
  | awk '/^```json/{f=1;next} f&&/^```/{exit} f' \
  | jq -r '.verdict' 2>/dev/null | tr '|' '\n' | tr -d ' ' | grep -v '^$' | sort -u \
  | tr '\n' ' ' | sed 's/ *$//' || true)

if [ -n "$CONTRACT_VERDICTS" ] && [ "$CONTRACT_VERDICTS" = "$SCHEMA_VERDICTS" ]; then
  pass_check "contract and schema agree on the verdict enum ($CONTRACT_VERDICTS)"
else
  fail_check "verdict enums disagree — contract:[$CONTRACT_VERDICTS] schema:[$SCHEMA_VERDICTS]"
fi

# The record has to be owed by the phase that writes it, or nothing notices its absence.
IMPL_CONTRACT=$(sed -n "/^  implement) CONTRACT='/,/' ;;/p" "$PRC")
if printf '%s\n' "$IMPL_CONTRACT" | grep -q '_build-critique\.json'; then
  pass_check "phase-records-check's implement contract lists _build-critique.json"
else
  fail_check "the implement record contract does not owe _build-critique.json — a phase that skipped the rung still reads complete"
fi
# It is `required-unless-work-orders`, and the distance from a plain `conditional` is the
# finding that produced this row. The work-order build path writes per-work-order
# `_critique.json` and never `_build-critique.json`, so an unconditional row would fail the
# records contract for a phase that was in fact critiqued, just by the other path. But
# `conditional` rows are never counted against the verdict at all, so the row excused the
# record's absence unconditionally while its stated condition sat in prose nothing read: a
# phase that skipped the rung entirely returned `complete` with `missing_required: 0`. The
# token is resolved against disk instead, and the row still has to name the other path.
if printf '%s\n' "$IMPL_CONTRACT" | grep -qE '_build-critique\.json\|required-unless-work-orders\|'; then
  pass_check "it is required unless disk shows the work-order path took the build"
else
  fail_check "_build-critique.json is not required-unless-work-orders in the implement contract"
fi
if printf '%s\n' "$IMPL_CONTRACT" | grep -E '_build-critique\.json\|required-unless-work-orders\|' | grep -q 'run-work-orders'; then
  pass_check "the row names the build path that writes a different record instead"
else
  fail_check "the row does not say when the record is legitimately absent"
fi

# --------------------------------------------------- 4. the command actually instructs it

# The boundary problem: an in-session build has no rev range, so the checkpoint is what makes
# a diff addressable at all. Capture without clear leaves refs in someone's repository.
grep -q 'build-checkpoint\.sh capture' "$CMD" \
  && pass_check "/implement names build-checkpoint.sh capture" \
  || fail_check "/implement never names 'build-checkpoint.sh capture' — the critic has no rev range to read"
grep -q 'build-checkpoint\.sh clear' "$CMD" \
  && pass_check "/implement names build-checkpoint.sh clear" \
  || fail_check "/implement never names 'build-checkpoint.sh clear' — the refs stay in the code repository"

# Reuse, not a second critique stack.
for TOK in 'wo-critic' 'wo-risk-classify\.sh' 'wo-critique-aggregate\.sh' 'spec-axis-reviewer'; do
  NAME=$(printf '%s' "$TOK" | tr -d '\\')
  grep -q "$TOK" "$CMD" \
    && pass_check "/implement reuses the existing stack: $NAME" \
    || fail_check "/implement never names $NAME — the rung reimplemented instead of reusing"
done

# The prose assertions run against a flattened body: these sentences are hard-wrapped in the
# source and a line-anchored grep would be testing the wrap width rather than the instruction.
CMD_FLAT=$(tr '\n' ' ' < "$CMD" | tr -s ' ')

# A forked critic inherits the reasoning it exists to challenge.
if printf '%s' "$CMD_FLAT" | grep -qi 'never a fork'; then
  pass_check "/implement says the critic is never a fork"
else
  fail_check "/implement does not forbid forking the critic"
fi
if printf '%s' "$CMD_FLAT" | grep -qiE 'fresh and independent|fresh, independent|fresh-context'; then
  pass_check "/implement says the critic is dispatched fresh and independent"
else
  fail_check "/implement does not say the critic is dispatched fresh/independent"
fi

# Disk is truth: an agent that died mid-response returns text that reads like an answer.
if printf '%s' "$CMD_FLAT" | grep -qiE 'never from (its|the) Task return|not from (its|the) Task return'; then
  pass_check "/implement says to read the verdict from the critic's file, not its Task return"
else
  fail_check "/implement does not forbid taking the verdict from the critic's Task return"
fi

# Posture. Without these two the rung is decoration.
if printf '%s' "$CMD_FLAT" | grep -qF '`unresolved` is not a pass'; then
  pass_check "/implement states that unresolved is not a pass"
else
  fail_check "/implement does not state that an unresolved critique is not a pass"
fi
if printf '%s' "$CMD_FLAT" | grep -qiE 'critical.{0,20}halts that component'; then
  pass_check "/implement states that a critical halts the component"
else
  fail_check "/implement does not state that a critical halts the component"
fi

# --------------------------------------------------- 5. step 2b stops selling isolation alone

NUDGE=$(sed -n '/^2b\./,/^3\. /p' "$CMD")
if [ -n "$NUDGE" ]; then
  pass_check "step 2b's work-order offer is present"
else
  fail_check "could not locate step 2b in /implement"
fi
if printf '%s\n' "$NUDGE" | grep -qF '`[n]`'; then
  pass_check "step 2b still spells out the [n] branch"
else
  fail_check "step 2b no longer names the [n] branch"
fi
if printf '%s\n' "$NUDGE" | grep -q 'build-critique'; then
  pass_check "step 2b says the [n] path gets the build-critique rung, so declining is not declining review"
else
  fail_check "step 2b offers [n] without saying what that path includes — the defect this rung closed"
fi
if printf '%s\n' "$NUDGE" | grep -q 'wo-critic'; then
  pass_check "step 2b records that [n] used to decline wo-critic outright"
else
  fail_check "step 2b does not record what declining removed before v5.33.0"
fi

# --------------------------------------------------- 6. the Output section declares both writes

OUT=$(awk '/^## Output/{f=1;next} f&&/^## /{exit} f' "$CMD")
if printf '%s\n' "$OUT" | grep -q '_build-critique\.json'; then
  pass_check "the Output section names _build-critique.json"
else
  fail_check "the Output section does not name _build-critique.json"
fi
if printf '%s\n' "$OUT" | grep -q 'refs/worktree/aida/build-checkpoints/'; then
  pass_check "the Output section names the refs/worktree/aida/build-checkpoints/ refs written into the code repository"
else
  fail_check "the Output section is silent about writing refs into the user's code repository"
fi

# --------------------------------------------------- 7. the honesty properties of the record
#
# These are the point of the rung. A record that can report only what it looked at is the
# failure shape this framework keeps rediscovering in itself.

for F in "$CONTRACT" "$SCHEMA"; do
  B=$(basename "$F")
  if grep -qE 'critiqued three of seven components' "$F"; then
    pass_check "$B states why a partial run must not read as a complete one"
  else
    fail_check "$B does not explain the partial-run failure the two counts exist to prevent"
  fi
done

if grep -qF '{component, reason}' "$CONTRACT" && grep -qF '{component, reason}' "$SCHEMA"; then
  pass_check "uncritiqued[] is documented in both files as carrying a reason per gap"
else
  fail_check "uncritiqued[] is not documented as {component, reason} in both files — a gap could be recorded with no reason"
fi

for F in "$CONTRACT" "$SCHEMA"; do
  B=$(basename "$F")
  PARA=$(grep -A3 -F 'legitimate in exactly two cases' "$F" | tr '\n' ' ' || true)
  if [ -z "$PARA" ]; then
    fail_check "$B does not restrict verdict:skipped to exactly two cases"
    continue
  fi
  # Match on the shape of the claim rather than one wording of it: the first case is "the
  # phase produced no change", which the contract states as an empty checkpoint range and the
  # schema as an empty change set. Pinning either literal makes this assertion fail on a
  # rewording that changed nothing it is defending.
  if printf '%s' "$PARA" | grep -qE 'empty|no change' && printf '%s' "$PARA" | grep -q 'architecture file'; then
    pass_check "$B names both legitimate skips: nothing changed, and no architecture file"
  else
    fail_check "$B restricts skipped to two cases without naming both of them"
  fi
  if printf '%s' "$PARA" | grep -qF 'the answer to "the critics did not run"'; then
    pass_check "$B rules skipped out as the answer to \"the critics did not run\""
  else
    fail_check "$B does not rule skipped out as the answer to \"the critics did not run\""
  fi
done

if [ "$FAIL" = "0" ]; then
  printf '\nbuild-critique-wiring-spec: all checks passed\n'
else
  printf '\nbuild-critique-wiring-spec: FAILURES\n' >&2
fi
exit "$FAIL"
