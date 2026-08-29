#!/usr/bin/env bash
# build-critique-gate-spec.sh — the build-critique rung is enforced, and the enforcement can
# fail.
#
# THE DEFECT THIS DEFENDS AGAINST. v5.33.0 shipped the rung with three things that looked
# like enforcement and not one that could fail:
#
#   1. `phase-records-check.sh` carried a `_build-critique.json` row marked `conditional`,
#      and that script counts conditional rows for visibility only. A phase that skipped the
#      rung entirely returned `{"verdict":"complete","missing_required":0}`.
#   2. The condition the row named — "when the build ran in-session rather than through
#      /run-work-orders" — was prose. Nothing evaluated it, although the discriminator was
#      on disk the whole time: `work-orders/wo-NN._critique.json`.
#   3. No downstream command read the record. `/review`, `/complete` and `/audit-status`
#      never named it, so a record saying `verdict: "critical"` had no effect on whether the
#      task shipped.
#
# Every assertion below is executed against a real fixture task folder, not read off prose,
# except the four wiring checks at the end that pin the command bodies which invoke it. The
# rule the fixtures exist to hold: there is no path from "no evidence" to `pass`. A build
# that was never challenged, a challenge that came back blocking, and a challenge that could
# not determine anything all fail, and a work-order build that was challenged the other way
# passes on the record it actually owes.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="${PLUGIN_ROOT}/scripts/build-critique-assert.sh"
K="${PLUGIN_ROOT}/scripts/phase-records-check.sh"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"
REVIEW="${PLUGIN_ROOT}/commands/review.md"
AUDIT="${PLUGIN_ROOT}/commands/audit-status.md"
IMPL="${PLUGIN_ROOT}/commands/implement.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$G" "$K" "$W" "$REVIEW" "$AUDIT" "$IMPL"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# A payload satisfying every key the schema marks required for build-critique.
GOOD='{"phase":"implement","verdict":"pass",
 "components":[{"component":"main","risk_tier":"low","lenses":["skeptic"],"verdict":"pass",
   "blocking":false,"findings_count":0,"checkpoint_before":"aaa","checkpoint_after":"bbb",
   "critique_ref":"/x/build-critique/main.critique.json"}],
 "components_declared":1,"components_critiqued":1,"uncritiqued":[],
 "tdd":{"red_observed":1,"passed_first_run":0,"unobserved":[]},
 "contract":{"baseline":"captured","changed":[]},
 "integration":{"ran":false,"reason":"single-component fixture"},
 "alignment":{"verdict":"pass","missing_requirements":[],"scope_creep":[],"spec_ref":null}}'

mktask() { d="$T/$1"; mkdir -p "$d" >/dev/null 2>&1; printf '%s' "$d"; }

# write_record <folder> <jq filter over GOOD>
write_record() {
  bash "$W" "$1" build-critique "$(printf '%s' "$GOOD" | jq -c "$2")" >/dev/null 2>&1
}

# run <folder> [flags...] -> sets OUT (json) and RC
run() {
  d="$1"; shift
  set +e
  OUT=$(bash "$G" "$d" "$@" 2>/dev/null); RC=$?
  set -e
}

verdict_is() { # verdict_is <expected> <label>
  V=$(printf '%s' "$OUT" | jq -r '.verdict')
  if [ "$V" = "$1" ]; then pass_check "$2"; else fail_check "$2 (got verdict=$V, rc=$RC)"; fi
}

# ---------------------------------------------------- 1. a build nobody challenged fails

D=$(mktask nothing)
run "$D"
verdict_is fail "a task with no build-critique record and no work-order critique fails"
[ "$(printf '%s' "$OUT" | jq -r '.unresolved')" = "true" ] \
  && pass_check "no record at all is unresolved, so /review rule 2 fail-closes on it" \
  || fail_check "no record at all was reported as a resolved state"
[ "$RC" = "1" ] \
  && pass_check "the script exits non-zero when the build was never challenged" \
  || fail_check "the script exited $RC on a build nobody challenged"
[ "$(printf '%s' "$OUT" | jq -r '.build_path')" = "none" ] \
  && pass_check "the verdict says which build path it found: none" \
  || fail_check "the verdict does not report the build path it resolved"

# ------------------------------------------------- 2. the in-session record is evaluated

D=$(mktask clean); write_record "$D" '.'
run "$D"
verdict_is pass "a clean in-session record passes"
[ "$RC" = "0" ] && pass_check "a clean record exits 0" || fail_check "a clean record exited $RC"
[ "$(printf '%s' "$OUT" | jq -r '.build_path')" = "in-session" ] \
  && pass_check "a _build-critique.json record resolves the in-session build path" \
  || fail_check "the in-session build path was not recognised"

D=$(mktask critical); write_record "$D" '.verdict="critical"'
run "$D"
verdict_is fail "a record carrying verdict critical fails the gate"
[ "$RC" = "1" ] && pass_check "a critical record exits non-zero" || fail_check "a critical record exited $RC"

# The rung's own posture is that `blocking` is the verdict, not the exit code and not the
# summary line. A record whose overall verdict reads pass while a component blocked is the
# shape that would otherwise ship.
D=$(mktask blocking); write_record "$D" '.components[0].blocking=true'
run "$D"
verdict_is fail "a blocking component fails even when the overall verdict says pass"

D=$(mktask unresolved); write_record "$D" '.verdict="unresolved"'
run "$D"
verdict_is fail "an unresolved critique fails, because nothing was cleared"
[ "$(printf '%s' "$OUT" | jq -r '.unresolved')" = "true" ] \
  && pass_check "an unresolved critique is marked unresolved for rule 2" \
  || fail_check "an unresolved critique was not marked unresolved"

# The counts are what make a partial run legible. Without them three green rows out of seven
# components read exactly like a complete pass.
D=$(mktask nocounts); write_record "$D" 'del(.components_declared,.components_critiqued,.uncritiqued)'
run "$D"
verdict_is fail "a record without the declared/critiqued/uncritiqued counts fails"

D=$(mktask nonecrit); write_record "$D" '.components=[]|.components_critiqued=0|.components_declared=3|.uncritiqued=[{"component":"a","reason":"skipped"},{"component":"b","reason":"skipped"},{"component":"c","reason":"skipped"}]'
run "$D"
verdict_is fail "3 components declared and 0 critiqued is a build that was not challenged"

D=$(mktask partial); write_record "$D" '.components_declared=3|.components_critiqued=1|.uncritiqued=[{"component":"b","reason":"deferred"},{"component":"c","reason":"deferred"}]'
run "$D"
verdict_is pass "a partial run passes with the gap surfaced, since the record names what it missed"
printf '%s' "$OUT" | jq -r '.messages|join(" ")' | grep -q 'uncritiqued' \
  && pass_check "the partial run's uncritiqued count is surfaced in the messages" \
  || fail_check "a partial run passed without saying what it did not look at"

# `skipped` is legitimate for an empty phase range or a task with no architecture file, and
# each of those carries its reason. Without one it is indistinguishable from "the critics did
# not run", which the contract calls unresolved.
D=$(mktask skipnoreason); write_record "$D" '.verdict="skipped"|.components=[]|.components_declared=0|.components_critiqued=0'
run "$D"
verdict_is fail "verdict skipped with no reason recorded fails"

D=$(mktask skipreason); write_record "$D" '.verdict="skipped"|.reason="no architecture file: task has no design phase"|.components=[]|.components_declared=0|.components_critiqued=0'
run "$D"
verdict_is skipped "verdict skipped with its reason recorded is a benign skip"
[ "$(printf '%s' "$OUT" | jq -r '.unresolved')" = "false" ] \
  && pass_check "a documented skip is not unresolved, so it does not fail-close" \
  || fail_check "a documented skip was marked unresolved"

# The one way past a blocking record, and it is on disk where an auditor reads who took it.
D=$(mktask bypass); write_record "$D" '.verdict="critical"|.bypass_reason="operator override: shipping the hotfix"'
run "$D"
verdict_is bypassed "a recorded bypass_reason turns a blocking record into bypassed, not pass"
printf '%s' "$OUT" | jq -r '.bypass_reason' | grep -q 'operator override' \
  && pass_check "the bypass reason is surfaced rather than silently accepted" \
  || fail_check "the bypass reason was swallowed"
[ "$(printf '%s' "$OUT" | jq -r '.verdict')" != "pass" ] \
  && pass_check "a bypass never reads as a pass" \
  || fail_check "a bypass was reported as a pass"

D=$(mktask emptyfile); : > "$D/_build-critique.json"
run "$D"
verdict_is fail "an empty _build-critique.json is not a record"

D=$(mktask garbage); printf 'not json' > "$D/_build-critique.json"
run "$D"
verdict_is fail "an unparseable _build-critique.json fails rather than being ignored"

# ------------------------------------------- 3. the work-order build path, resolved on disk

D=$(mktask wo_clean); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '# wo\n' > "$D/work-orders/wo-01.md"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
run "$D"
verdict_is pass "a /run-work-orders build passes on its per-work-order critiques with no _build-critique.json"
[ "$(printf '%s' "$OUT" | jq -r '.build_path')" = "work-orders" ] \
  && pass_check "the work-order build path is resolved from disk, not from prose" \
  || fail_check "the work-order build path was not resolved from the files on disk"

D=$(mktask wo_uncritiqued); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '# wo\n' > "$D/work-orders/wo-01.md"
run "$D"
verdict_is fail "compiled work-orders with no critique for any of them is a build nobody challenged"

D=$(mktask wo_blocking); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '{"blocking":true}' > "$D/work-orders/wo-01._critique.json"
run "$D"
verdict_is fail "a blocking work-order critique fails the gate"

D=$(mktask wo_halt); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
: > "$D/work-orders/wo-01.HALT"
run "$D"
verdict_is fail "an unresolved HALT marker fails the gate"

# critique-envelope.md treats an absent or not_evaluated `blocking` as blocking. A critique
# that did not evaluate cleared nothing.
D=$(mktask wo_noeval); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '{"overall":"pass"}' > "$D/work-orders/wo-01._critique.json"
run "$D"
verdict_is fail "a work-order critique with no evaluated blocking field fails closed"

# ----------------------------------------------------------- 4. the two benign exceptions

D=$(mktask emptychange)
run "$D" --change-set-empty
verdict_is skipped "an empty change set skips benignly, since there was nothing to critique"
[ "$RC" = "0" ] && pass_check "the empty-change-set skip exits 0" || fail_check "the empty-change-set skip exited $RC"

# ...and the caller's finding never overrides a record that IS there and blocking.
D=$(mktask emptychange_but_critical); write_record "$D" '.verdict="critical"'
run "$D" --change-set-empty
verdict_is fail "--change-set-empty does not excuse a blocking record that exists"

set +e
OUT=$(bash "$G" "$T/does-not-exist" 2>/dev/null); RC=$?
set -e
[ "$RC" = "2" ] && pass_check "a task folder that is not a directory is a usage error, exit 2" \
  || fail_check "a missing task folder exited $RC instead of 2"
[ "$(printf '%s' "$OUT" | jq -r '.verdict')" != "pass" ] \
  && pass_check "a task folder it could not read never reads as a pass" \
  || fail_check "an unreadable task folder passed the gate"

# ------------------------------ 5. the phase-3 records check evaluates the same condition

IMPL_REQ="_phase-active.json _dev-guides-load.json _playbook-load.json implementation.md _mechanism-challenge.json"
seed_phase() { for f in $2; do printf '{"gate_specific":{"phase":"implement"}}' > "$1/$f"; done; }

D=$(mktask prc_missing); seed_phase "$D" "$IMPL_REQ"
PRC=$(bash "$K" "$D" --phase implement)
[ "$(printf '%s' "$PRC" | jq -r '.records[]|select(.name=="_build-critique.json")|.requirement')" = "required" ] \
  && pass_check "with no work-order critiques on disk the row resolves to required" \
  || fail_check "the row stayed conditional, so a skipped rung is never counted"
[ "$(printf '%s' "$PRC" | jq -r '.verdict')" = "incomplete" ] \
  && pass_check "an implement phase that skipped the rung reports incomplete" \
  || fail_check "a phase that skipped the rung still reports complete"
[ "$(printf '%s' "$PRC" | jq -r '.missing_required')" -ge 1 ] \
  && pass_check "the missing record is counted in missing_required" \
  || fail_check "missing_required is 0 while the record is missing"

D=$(mktask prc_present); seed_phase "$D" "$IMPL_REQ"; write_record "$D" '.'
[ "$(bash "$K" "$D" --phase implement | jq -r '.verdict')" = "complete" ] \
  && pass_check "an implement phase that ran the rung reports complete" \
  || fail_check "a phase that ran the rung does not report complete"

D=$(mktask prc_wo); seed_phase "$D" "$IMPL_REQ"; mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
PRC=$(bash "$K" "$D" --phase implement)
[ "$(printf '%s' "$PRC" | jq -r '.records[]|select(.name=="_build-critique.json")|.requirement')" = "conditional" ] \
  && pass_check "per-work-order critiques on disk downgrade the row to conditional" \
  || fail_check "the work-order build path is still penalised for a record it does not owe"
[ "$(printf '%s' "$PRC" | jq -r '.verdict')" = "complete" ] \
  && pass_check "a work-order-built phase is complete without _build-critique.json" \
  || fail_check "a build challenged by the other path was reported incomplete"
[ "$(printf '%s' "$PRC" | jq -r '.warnings|index("build_critique_satisfied_by_work_order_critiques")')" != "null" ] \
  && pass_check "the downgrade says which record satisfied the row" \
  || fail_check "the row was downgraded silently, so the reason is unreadable"

# ------------------------------------------------- 6. the wiring the fixtures cannot reach

grep -q 'build-critique-assert\.sh' "$REVIEW" \
  && pass_check "/review invokes build-critique-assert.sh" \
  || fail_check "/review does not invoke the gate, so the record has no consumer again"
grep -q 'name: "build-critique"' "$REVIEW" \
  && pass_check "/review adds a named gates_run[] entry, so it reaches overall_verdict" \
  || fail_check "/review reads the record without folding it into gates_run[]"
grep -qE 'build-critique.*hard-block|hard-block.*build-critique' "$REVIEW" \
  && pass_check "the entry is hard-block, not advisory" \
  || fail_check "the build-critique entry is not declared hard-block"
grep -q '_build-critique\.json' "$AUDIT" \
  && pass_check "/audit-status scans _build-critique.json like the other audit files" \
  || fail_check "/audit-status still does not scan the record"
grep -q 'required-unless-work-orders' "$IMPL" \
  && pass_check "/implement's records-check step states the requirement it actually enforces" \
  || fail_check "/implement still describes an enforcement its records check does not perform"

if [ "$FAIL" = "0" ]; then
  printf '\nbuild-critique-gate-spec: all checks passed\n'
else
  printf '\nbuild-critique-gate-spec: FAILURES\n' >&2
fi
exit "$FAIL"
