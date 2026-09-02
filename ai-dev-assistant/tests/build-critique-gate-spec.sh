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
GOOD='{"build_identity":{"head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files_digest":"da885006a736ed9ce06e3736845717d7f70d58abf15995f8977f551bbfafbf1f","files":["src/A.php"]},"phase":"implement","verdict":"pass",
 "components":[{"component":"main","runtime":"executed","risk_tier":"low","lenses":["correctness"],"verdict":"pass",
   "blocking":false,"findings_count":0,"checkpoint_before":"aaa","checkpoint_after":"bbb",
   "critique_ref":"build-critique/main.critique.json"}],
 "components_declared":1,"components_critiqued":1,"uncritiqued":[],
 "closing_fixes":{"applied":0},
 "tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[]},
 "contract":{"baseline":"captured","changed":[]},
 "integration":{"ran":false,"reason":"single-component fixture"},
 "alignment":{"verdict":"pass","missing_requirements":[],"scope_creep":[],"criteria_unverifiable":[],"spec_ref":null}}'

mktask() { d="$T/$1"; mkdir -p "$d" >/dev/null 2>&1; printf '%s' "$d"; }

# The critique envelope every record's `critique_ref` points at. It has to EXIST and it has to be
# shaped the way `wo-critique-aggregate.sh` writes one -- findings under `.critics[].findings`, not
# at the top level. The fixture shipped pointing at `/x/build-critique/main.critique.json`, a path
# that is not there, so the scope block below read an empty finding-site set and answered
# `cannot_judge` on every single case: none of its assertions reached a comparison. An inert
# fixture is the quietest way to have a spec that cannot fail.
CRITIQUE='{"wo":"main","overall":"pass","blocking":false,"critics":[{"lens":"correctness","verdict":"pass","findings":[
  {"severity":"critical","text":"f1","where":[{"file":"src/A.php"}]},
  {"severity":"note","text":"f2","where":[{"file":"src/NOTE.php"}]}]}]}'

# write_record <folder> <jq filter over GOOD>
write_record() {
  mkdir -p "$1/build-critique" >/dev/null 2>&1
  printf '%s' "$CRITIQUE" > "$1/build-critique/main.critique.json"
  bash "$W" "$1" build-critique "$(printf '%s' "$GOOD" | jq -c "$2")" >/dev/null 2>&1
}

# run <folder> [flags...] -> sets OUT (json) and RC
# The build-critique gate compares the record's build_identity against the change set the caller
# resolved. This spec is about a different block, so it hands the gate a change set that agrees
# with GOOD's identity and keeps the subject of each case the thing it is named for.
CSF="$(mktemp)"
printf '%s' '{"schema_version":"1.0","base":"main","merge_base":"abc","head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files":["src/A.php"],"untracked":[],"empty_reason":null,"warnings":[]}' > "$CSF"

run() {
  d="$1"; shift
  set +e
  OUT=$(bash "$G" "$d" --change-set-file "$CSF" "$@" 2>/dev/null); RC=$?
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
# The run record joined this fixture in v5.48.0, when the delegated path started owing a tdd
# block. The assertion is unchanged: this cell is about resolving the build path from disk with
# no _build-critique.json present, and it still is.
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is pass "a /run-work-orders build passes on its per-work-order critiques with no _build-critique.json"
# --- the delegated build path owes a TDD record too ---------------------------------------
# THE DEFECT THIS DEFENDS AGAINST. `tdd` is demanded of the in-session record and of nothing
# else. A /run-work-orders build satisfied this gate on its critique files alone and owed no
# statement about whether any test was watched failing before the code existed. So the rung
# that enforces test-first was reachable only on the path where the main context does the
# building, while the orchestration rules route real builds to delegated agents. Measured on a
# live build: three components built, reviewed and merged with no TDD record of any kind, and
# every downstream check satisfied, because each one reads a record nobody was asked to write.
#
# Absence is the failure, not a skip. A work-order that recorded no TDD block is `unresolved`,
# the same answer an in-session record with no `tdd` key gets, and for the same reason: nobody
# looked is not the same answer as nothing was wrong.

D=$(mktask wo_no_tdd); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '# wo\n' > "$D/work-orders/wo-01.md"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true}' > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is fail "a work-order build whose run record carries no tdd block fails"
[ "$(printf '%s' "$OUT" | jq -r '.unresolved')" = "true" ] \
  && pass_check "a missing work-order tdd block is a could-not-tell, not a clean pass" \
  || fail_check "a work-order build with no tdd record was resolved rather than left unresolved"
printf '%s' "$OUT" | jq -r '.messages|join(" ")' | grep -q 'wo-01' \
  && pass_check "the message names the work-order that owes the record" \
  || fail_check "the message does not say which work-order is missing its tdd block"

D=$(mktask wo_with_tdd); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '# wo\n' > "$D/work-orders/wo-01.md"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":2,"passed_first_run":0,"ratified":1,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is pass "a work-order build that recorded its tdd block passes"

D=$(mktask wo_partial_tdd); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '# wo\n' > "$D/work-orders/wo-01.md"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":2}}' > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is fail "a work-order tdd block missing a sibling count fails like the in-session one"

[ "$(printf '%s' "$OUT" | jq -r '.build_path')" = "work-orders" ] \
  && pass_check "the work-order build path is resolved from disk, not from prose" \
  || fail_check "the work-order build path was not resolved from the files on disk"

# --- one cell per required key, each omitting EXACTLY that one key -------------------------
# WHY ONE CELL PER KEY. The fixture above (`wo_partial_tdd`) omits three keys at once, so it
# cannot say which of them is load-bearing. Measured before these cells existed: deleting
# `has("unobserved")` from the gate, and separately deleting `has("passed_first_run")`, changed
# the gate's behaviour and NO cell in either spec noticed. A single fixture missing everything
# ratifies the check rather than constraining it.

# mkwo <folder> <wo id> <status> — a compiled work-order with frontmatter the subject rule reads.
mkwo() {
  mkdir -p "$1/work-orders" >/dev/null 2>&1
  printf -- '---\nid: %s\nstatus: %s\n---\n# wo\n' "$2" "$3" > "$1/work-orders/$2.md"
}

for key in red_observed passed_first_run ratified unobserved; do
  D=$(mktask "wo_omit_$key"); mkwo "$D" wo-01 "done"
  printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
  printf '%s' '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":2,"passed_first_run":0,"ratified":1,"unobserved":[],"reason":null}}' \
    | jq -c --arg k "$key" 'del(.tdd[$k])' > "$D/work-orders/wo-01.run.json"
  run "$D"
  verdict_is fail "a work-order tdd block omitting only $key fails"
  printf '%s' "$OUT" | jq -r '.evidence.work_orders_bad_tdd[0].problems | join(" ")' | grep -q "$key" \
    && pass_check "the gate names $key specifically as the problem, not a generic omission" \
    || fail_check "the gate failed without naming $key (evidence: $(printf '%s' "$OUT" | jq -c '.evidence.work_orders_bad_tdd'))"
done

# --- the two VALUE judgements, which are what C1 was about ---------------------------------
# THE DEFECT THESE DEFEND AGAINST. The delegated branch called has() on four keys and stopped,
# under a comment claiming it demanded exactly what the in-session branch demands. The
# in-session branch additionally BLOCKS on two value judgements, so this exact block --
# {"red_observed":0,"passed_first_run":5,"ratified":0,"unobserved":["A","B","C"],"reason":null}
# -- returned pass on the delegated path and fail on the in-session one. Both paths now call
# one function, so a record satisfies both or neither.

# The MESSAGE has to name the problems too, not just the evidence object. Replacing this message
# with a generic "a work-order tdd block was refused" survived a mutation sweep: every naming
# assertion here read `.evidence`, and a person reading /review output reads the message.
D=$(mktask wo_firstrun_no_reason); mkwo "$D" wo-01 "done"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":0,"passed_first_run":5,"ratified":0,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is fail "a work-order recording passed_first_run > 0 with no reason fails, as the in-session path does"
printf '%s' "$OUT" | jq -r '.evidence.work_orders_bad_tdd[0].problems | join(" ")' | grep -q 'passed_first_run > 0' \
  && pass_check "the delegated path says the reason is what is missing, not the count" \
  || fail_check "the delegated path failed without naming the unreasoned passed_first_run"
printf '%s' "$OUT" | jq -r '.messages | join(" | ")' | grep -q 'wo-01 (passed_first_run > 0' \
  && pass_check "the message names the work-order AND the problem, not just that something was refused" \
  || fail_check "the message does not carry the problem names ($(printf '%s' "$OUT" | jq -c '.messages'))"

D=$(mktask wo_firstrun_with_reason); mkwo "$D" wo-01 "done"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":0,"passed_first_run":5,"ratified":0,"unobserved":[],"reason":"characterization tests written against existing code"}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is pass "a work-order recording passed_first_run > 0 WITH a reason passes, so the honest answer is not the expensive one"

D=$(mktask wo_unobs_no_reason); mkwo "$D" wo-01 "done"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":["A","B"],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is fail "a work-order recording unobserved criteria with no reason fails, as the in-session path does"
printf '%s' "$OUT" | jq -r '.evidence.work_orders_bad_tdd[0].problems | join(" ")' | grep -q 'unobserved' \
  && pass_check "the delegated path names the unexplained unobserved[] entries" \
  || fail_check "the delegated path failed without naming the unexplained unobserved[]"

D=$(mktask wo_unobs_with_reason); mkwo "$D" wo-01 "done"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":["A","B"],"reason":"both need a live payment gateway"}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is pass "a work-order recording unobserved criteria WITH a reason passes"

# --- the subject set is the work-orders, not the critique files ----------------------------
# THE DEFECT THIS DEFENDS AGAINST. The block iterated the critique files, so a compiled
# work-order carrying no `wo-NN._critique.json` was never examined. Measured on three compiled
# work-orders, one with a critique and a TDD record and two with nothing at all: `verdict: pass`,
# `work_orders_without_tdd: []`, while the record's own evidence said `work_orders: 3`.

# wo-02 is `pending` on purpose, so ONLY the run-record disjunct makes it a subject: no critique
# file, not marked done. Measured before this line said `pending`: deleting the run-record
# disjunct from the subject rule turned NOTHING red, because every fixture carrying a run record
# also carried a critique or a `done` status. A disjunct no cell can kill is not being tested.
# The shape is real -- the loop dispatched wo-02 and wrote its run record, and no critic has run
# on it and nothing has marked it finished.
D=$(mktask wo_no_critique_still_judged); mkwo "$D" wo-01 "done"; mkwo "$D" wo-02 pending
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
printf '{"wo":"wo-02","build_returned":true}' > "$D/work-orders/wo-02.run.json"
run "$D"
verdict_is fail "a dispatched work-order with a run record and NO critique file is still judged for its tdd block"
printf '%s' "$OUT" | jq -r '.evidence.work_orders_without_tdd | join(" ")' | grep -q 'wo-02' \
  && pass_check "the work-order with no critique file of its own is named as owing a record" \
  || fail_check "the uncritiqued work-order was never examined (without_tdd: $(printf '%s' "$OUT" | jq -c '.evidence.work_orders_without_tdd'))"
[ "$(printf '%s' "$OUT" | jq -r '.evidence.work_orders_owing_tdd')" = "2" ] \
  && pass_check "the subject count is the work-orders that owe a record, not the critique files" \
  || fail_check "the subject count did not follow the work-orders (got $(printf '%s' "$OUT" | jq -r '.evidence.work_orders_owing_tdd'))"

D=$(mktask wo_never_dispatched); mkwo "$D" wo-01 "done"; mkwo "$D" wo-02 ready
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is pass "a compiled work-order with neither a run record nor status: done is not a subject: it built nothing"
[ "$(printf '%s' "$OUT" | jq -r '.evidence.work_orders_owing_tdd')" = "1" ] \
  && pass_check "the never-dispatched work-order is excluded from the subject count, and the count says so" \
  || fail_check "the never-dispatched work-order was counted as owing a record"

# `ready` and `blocked` are the ONLY two statuses reachable without a dispatch, so the exclusion
# names those two rather than listing the three that owe. An unrecognised status is not evidence
# that nothing happened: it fails closed and is named, which is what keeps the exclusion from
# becoming a way to opt out by writing something the enum does not contain.
D=$(mktask wo_unknown_status); mkwo "$D" wo-01 "done"; mkwo "$D" wo-02 banana
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is fail "a work-order carrying a status outside the enum owes a record rather than being skipped"
printf '%s' "$OUT" | jq -r '.evidence.work_orders_without_tdd | join(" ")' | grep -q 'wo-02' \
  && pass_check "the unrecognised-status work-order is named, not silently excluded" \
  || fail_check "an unrecognised status excluded the work-order in silence"

# `done` with no run record is the lost-record half of the union, and it must not pass.
D=$(mktask wo_done_no_run); mkwo "$D" wo-01 "done"; mkwo "$D" wo-02 "done"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is fail "a work-order marked done with no run record at all fails rather than passing silently"
printf '%s' "$OUT" | jq -r '.evidence.work_orders_without_tdd | join(" ")' | grep -q 'wo-02' \
  && pass_check "the done-but-recordless work-order is named" \
  || fail_check "the done-but-recordless work-order was not named"

# A critique is BUILD EVIDENCE: `wo-critic` reads a diff and the gate envelopes, so it cannot have
# run over something nobody built. wo-02 below is `pending` with no run record, so ONLY the
# critique disjunct makes it a subject. The first cut of the subject rule omitted that disjunct and
# this shape passed.
D=$(mktask wo_critique_no_run); mkwo "$D" wo-01 "done"; mkwo "$D" wo-02 pending
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
printf '{"blocking":false}' > "$D/work-orders/wo-02._critique.json"
run "$D"
verdict_is fail "a critiqued work-order with no run record fails: it was built, and its record is lost"
printf '%s' "$OUT" | jq -r '.evidence.work_orders_without_tdd | join(" ")' | grep -q 'wo-02' \
  && pass_check "the critiqued-but-recordless work-order is named" \
  || fail_check "the critiqued-but-recordless work-order was not named"
[ "$(printf '%s' "$OUT" | jq -r '.evidence.work_orders_owing_tdd')" = "2" ] \
  && pass_check "a critique alone makes a work-order a subject" \
  || fail_check "the critique disjunct did not make it a subject (count $(printf '%s' "$OUT" | jq -r '.evidence.work_orders_owing_tdd'))"

# THE MIRROR OF THE ORIGINAL DEFECT. Iterating `wo-*.md` fixes "a work-order with no critique was
# never examined" and opens "a critique whose .md is gone is never examined". Before the id set
# became a union of all three globs this returned pass, with the record's own evidence saying one
# critic ran and zero work-orders owed anything.
D=$(mktask wo_critique_no_md); mkdir -p "$D/work-orders" >/dev/null 2>&1
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
run "$D"
verdict_is fail "a critique whose work-order .md is gone is still a subject: the critic ran on something"
[ "$(printf '%s' "$OUT" | jq -r '.evidence.work_orders_owing_tdd')" = "1" ] \
  && pass_check "the subject set survives the deletion of the .md it was drawn from" \
  || fail_check "a deleted .md emptied the subject set (owing $(printf '%s' "$OUT" | jq -r '.evidence.work_orders_owing_tdd'))"
printf '%s' "$OUT" | jq -r '.evidence.work_orders_without_tdd | join(" ")' | grep -q 'wo-01' \
  && pass_check "the orphaned critique's work-order is named as owing a record" \
  || fail_check "the orphaned critique's work-order was not named"

# A `tdd` THAT IS NOT AN OBJECT is the JQ_ERR path, and it is reachable rather than defensive:
# the key is present, so the has("tdd") check passes, and every reading below it errors. Both
# branches treat that as could-not-read, never as nothing-wrong. Without these two cells the
# JQ_ERR handling on both paths survived a mutation that deleted it.
D=$(mktask wo_tdd_not_object); mkwo "$D" wo-01 "done"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":5}' > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is fail "a work-order whose tdd block is not an object fails rather than reading as sound"
printf '%s' "$OUT" | jq -r '.evidence.work_orders_bad_tdd[0].problems | join(" ")' | grep -q 'could not be read' \
  && pass_check "an unreadable work-order tdd block says it could not be read" \
  || fail_check "an unreadable work-order tdd block was reported as some other problem"

D=$(mktask tdd_not_object); write_record "$D" '.tdd=5'
run "$D"
verdict_is fail "an in-session tdd block that is not an object fails"
[ "$(printf '%s' "$OUT" | jq -r '.unresolved')" = "true" ] \
  && pass_check "an unreadable in-session tdd block is unresolved, not a settled violation" \
  || fail_check "an unreadable in-session tdd block was reported as resolved"
printf '%s' "$OUT" | jq -r '.messages | join(" | ")' | grep -q 'could not be read' \
  && pass_check "the in-session path says the block could not be read" \
  || fail_check "the in-session path failed without saying the block was unreadable"

# An evidence key that appears only on failure cannot be read as "checked and clean".
D=$(mktask wo_evidence_on_pass); mkwo "$D" wo-01 "done"
printf '{"blocking":false}' > "$D/work-orders/wo-01._critique.json"
printf '{"wo":"wo-01","build_returned":true,"tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[],"reason":null}}' \
  > "$D/work-orders/wo-01.run.json"
run "$D"
verdict_is pass "a delegated build with a sound tdd record passes"
[ "$(printf '%s' "$OUT" | jq -r '.evidence | has("work_orders_bad_tdd")')" = "true" ] \
  && pass_check "work_orders_bad_tdd is present on a pass, so an empty list means checked-and-clean" \
  || fail_check "work_orders_bad_tdd only appears on failure, so its absence cannot be read"

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
OUT=$(bash "$G" "$T/does-not-exist" --change-set-file "$CSF" 2>/dev/null); RC=$?
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

# --------------------------------- 5b. scope compliance: the caller's half of the D6 kernel
#
# THE DEFECT THESE DEFEND AGAINST. `scripts/repair-scope-check.sh` is a correct set-comparison
# kernel whose header says, in as many words, that a caller who could not establish what a repair
# touched must pass `--touched-files-source undetermined` and must NEVER pass `[]` to mean "I could
# not tell". Its only caller passed exactly that. A change-set object with no `files` key satisfied
# `type == "object"`, so the source was stamped `determined` while `(.files // [])` yielded `[]`,
# and the kernel answered `in_scope` with the message "every touched file is named by a finding"
# over a comparison nobody made. Measured, not theorised.
#
# And the subject was the wrong set: `review-change-set.sh`'s `.files` is the WHOLE task change
# set, not the repair's own diff, while the rung already writes `build-critique/<component>.repair.txt`
# per `[a]ddress` and it never reached this check.

scope_of() { printf '%s' "$OUT" | jq -r ".evidence.scope_compliance.$1 // \"absent\""; }
scope_subject() { printf '%s' "$OUT" | jq -r '.evidence.scope_subject // "absent"'; }

# run_cs <folder> <change-set json> — the same gate, with a change set this case controls.
run_cs() {
  d="$1"; CS2="$T/cs-case.json"; printf '%s' "$2" > "$CS2"
  set +e
  OUT=$(bash "$G" "$d" --change-set-file "$CS2" 2>/dev/null); RC=$?
  set -e
}

CS_OK='{"schema_version":"1.0","base":"main","merge_base":"abc","head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files":["src/A.php"],"untracked":[],"empty_reason":null,"warnings":[]}'
CS_NOKEY='{"schema_version":"1.0","base":"main","merge_base":"abc","head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","untracked":[],"empty_reason":null,"warnings":[]}'
CS_EMPTY='{"schema_version":"1.0","base":"main","merge_base":"abc","head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files":[],"untracked":[],"empty_reason":null,"warnings":[]}'
CS_WRONGTYPE='{"schema_version":"1.0","base":"main","merge_base":"abc","head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files":"src/A.php","untracked":[],"empty_reason":null,"warnings":[]}'
CS_NONSTRING='{"schema_version":"1.0","base":"main","merge_base":"abc","head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files":[1,2],"untracked":[],"empty_reason":null,"warnings":[]}'

# The finding sites are read off the aggregate envelope, which keeps them under
# `.critics[].findings`. Reading only a top-level `.findings` — how this shipped — found nothing on
# every real record, so the comparison below could never happen.
D=$(mktask scope_sites); write_record "$D" '.'
run_cs "$D" "$CS_OK"
[ "$(scope_of action)" = "in_scope" ] \
  && pass_check "finding sites are read from .critics[].findings, so a real envelope is compared" \
  || fail_check "the aggregate envelope's findings were not read (action=$(scope_of action))"
[ "$(scope_of decided_by)" = "sets" ] \
  && pass_check "a comparison was actually made, not abstained from" \
  || fail_check "no comparison was made on a record that names a site (decided_by=$(scope_of decided_by))"

# THE FALSE CLEAN. No `files` key at all: `determined` is not earned, so the honest answer is
# cannot_judge. `in_scope` here is the defect, and it is asserted against by name.
D=$(mktask scope_nokey); write_record "$D" '.'
run_cs "$D" "$CS_NOKEY"
[ "$(scope_of action)" = "cannot_judge" ] \
  && pass_check "a change set with no files key is cannot_judge, not a clean scope" \
  || fail_check "a change set with no files key returned $(scope_of action)"
[ "$(scope_of action)" != "in_scope" ] \
  && pass_check "the absent-key case never reads as in_scope" \
  || fail_check "an absent files key was reported as in_scope over an empty comparison"
printf '%s' "$OUT" | jq -r '.messages|join(" ")' | grep -q 'could not be determined' \
  && pass_check "the message says the touched-file set could not be determined" \
  || fail_check "the absent-key case said nothing about why it could not judge"

# --- c4: a named site the repair never touched, surfaced by name -------------------------
# Written from the criterion before the message existed. Under one critic round per component
# nothing re-reads the repair, so "the repair did LESS than the remedy" lost its only reader.
# The kernel's `unaddressed` set is the deterministic replacement, and a set nobody prints is
# the `out_of_range[]` defect this epic already found once.
CRITIQUE_SAVE="$CRITIQUE"
CRITIQUE='{"wo":"main","overall":"pass","blocking":false,"critics":[{"lens":"correctness","verdict":"pass","findings":[
  {"severity":"critical","text":"f1","where":[{"file":"src/A.php"},{"file":"src/B.php"}]}]}]}'
D=$(mktask scope_unaddressed); write_record "$D" '.'
run_cs "$D" "$CS_OK"
UNADDR=$(printf '%s' "$OUT" | jq -c '.evidence.scope_compliance.unaddressed // "absent"')
[ "$UNADDR" = '["src/B.php"]' ] \
  && pass_check "a named site the repair never touched lands in the unaddressed evidence" \
  || fail_check "unaddressed evidence was $UNADDR, expected [\"src/B.php\"]"
printf '%s' "$OUT" | jq -r '.messages|join(" ")' | grep -q 'src/B.php' \
  && pass_check "the unaddressed site is named in a message, not left in evidence nobody reads" \
  || fail_check "no message named the site the repair never touched"
CRITIQUE="$CRITIQUE_SAVE"

# ...and the case that is NOT the same fact. A change set that genuinely recorded zero files is a
# real, determined answer, and collapsing it into the absent-key case would be the mirror defect.
D=$(mktask scope_empty); write_record "$D" '.'
run_cs "$D" "$CS_EMPTY"
[ "$(scope_of action)" = "in_scope" ] \
  && pass_check "files present but empty is determined, and an empty touched set is in_scope" \
  || fail_check "a genuinely empty change set returned $(scope_of action) instead of in_scope"
[ "$(scope_of decided_by)" = "sets" ] \
  && pass_check "the empty-but-present case was decided by a comparison" \
  || fail_check "the empty-but-present case abstained (decided_by=$(scope_of decided_by))"

D=$(mktask scope_wrongtype); write_record "$D" '.'
run_cs "$D" "$CS_WRONGTYPE"
[ "$(scope_of action)" = "cannot_judge" ] \
  && pass_check "a files key of the wrong type is cannot_judge" \
  || fail_check "files as a string returned $(scope_of action)"

D=$(mktask scope_nonstring); write_record "$D" '.'
run_cs "$D" "$CS_NONSTRING"
[ "$(scope_of action)" = "cannot_judge" ] \
  && pass_check "a files array of non-strings is cannot_judge, not a kernel usage error" \
  || fail_check "files as an array of numbers returned $(scope_of action)"

# THE SUBJECT. With a repair diff on disk the check judges the REPAIR's own touched files. The
# change set here names only src/A.php, which the finding names; the repair diff names a file it
# does not. Reading the change set would report in_scope, so this case fails if the subject is wrong.
D=$(mktask scope_repair); write_record "$D" '.'
printf 'M\tsrc/A.php\nA\tsrc/STRAY.php\n' > "$D/build-critique/main.repair.txt"
run_cs "$D" "$CS_OK"
[ "$(scope_subject)" = "repair_diff" ] \
  && pass_check "the repair's own diff is the subject when the rung wrote one" \
  || fail_check "the subject was $(scope_subject), not the repair diff"
[ "$(scope_of action)" = "out_of_scope" ] \
  && pass_check "a file only the repair diff names is caught, which the task change set would have missed" \
  || fail_check "the repair diff's stray file was not caught (action=$(scope_of action))"
printf '%s' "$OUT" | jq -r '.evidence.scope_compliance.unnamed|join(" ")' | grep -q 'src/STRAY.php' \
  && pass_check "the unnamed file comes from the repair range" \
  || fail_check "unnamed did not carry the repair's stray file"

# Both ends of a rename are files the repair touched.
D=$(mktask scope_rename); write_record "$D" '.'
printf 'R100\tsrc/OLD.php\tsrc/A.php\n' > "$D/build-critique/main.repair.txt"
run_cs "$D" "$CS_OK"
printf '%s' "$OUT" | jq -r '.evidence.scope_compliance.unnamed|join(" ")' | grep -q 'src/OLD.php' \
  && pass_check "a rename's source path counts as touched" \
  || fail_check "a rename's source path was dropped from the touched set"

# A 0-BYTE repair diff is not a repair that touched nothing. git writes its error to stderr after
# the redirect has already made the file, which is how the sibling accept kernel got handed one on
# every real build.
D=$(mktask scope_zerobyte); write_record "$D" '.'
: > "$D/build-critique/main.repair.txt"
run_cs "$D" "$CS_OK"
[ "$(scope_of action)" = "cannot_judge" ] \
  && pass_check "a 0-byte repair diff abstains rather than reading as a clean repair" \
  || fail_check "a 0-byte repair diff returned $(scope_of action)"
[ "$(scope_subject)" = "repair_diff" ] \
  && pass_check "the abstention still says which subject it could not read" \
  || fail_check "the 0-byte case did not name its subject"

# ...and with no repair diff at all the fallback is honest and named.
D=$(mktask scope_fallback); write_record "$D" '.'
run_cs "$D" "$CS_OK"
[ "$(scope_subject)" = "task_change_set" ] \
  && pass_check "with no repair diff the subject falls back to the task change set and says so" \
  || fail_check "the fallback subject was $(scope_subject)"

# The kernel surfaces; it never halts. A stray file must not turn the gate red.
D=$(mktask scope_nonblocking); write_record "$D" '.'
printf 'A\tsrc/STRAY.php\n' > "$D/build-critique/main.repair.txt"
run_cs "$D" "$CS_OK"
verdict_is pass "an out_of_scope repair surfaces without failing the gate"

# ------------------------- 5b. an out-of-range finding reaches /review, or nothing does
#
# THE DEFECT THIS DEFENDS AGAINST. `wo-critique-aggregate.sh` suppresses a finding whose every site
# falls outside the component's own range -- it opens no repair round -- and collects it into the
# envelope's top-level `out_of_range[]`. `references/gate-audit-schema.md` states in bold that that
# array is "the channel by which such a finding reaches /review; a consumer that does not read it
# will see the finding vanish rather than move." Nothing on the review side read it: not this gate,
# not `references/build-critique.md`, not `commands/review.md`. The array was written, documented as
# a channel, and had no consumer -- a kernel with no caller, shipped in the same change whose own
# ratchet comment names that as the defect it had just fixed one component earlier.
#
# The cells below run the gate against an envelope that carries one, so the channel is asserted end
# to end rather than grepped for.

CRITIQUE_OOR='{"wo":"main","overall":"pass","blocking":false,
 "range_check":{"status":"ran","decided_by":"sets","reason":null},
 "out_of_range":[{"severity":"critical","text":"f9","id":"f9","where":[{"file":"other/Z.php","line":9}]}],
 "critics":[{"lens":"correctness","verdict":"pass","findings":[
   {"severity":"critical","text":"f1","where":[{"file":"src/A.php"}]}]}]}'

ev_of() { printf '%s' "$OUT" | jq -r ".evidence.$1 // \"absent\""; }

D=$(mktask oor_read); write_record "$D" '.'
printf '%s' "$CRITIQUE_OOR" > "$D/build-critique/main.critique.json"
run_cs "$D" "$CS_OK"
[ "$(ev_of out_of_range_findings)" = "1" ] \
  && pass_check "a finding suppressed as out of range reaches /review as evidence" \
  || fail_check "the gate read no out-of-range finding off the critique_ref (got $(ev_of out_of_range_findings))"
printf '%s' "$OUT" | jq -r '.evidence.out_of_range_sites | join(" ")' 2>/dev/null | grep -q 'other/Z.php' \
  && pass_check "carrying the site it named, so the reviewer can act on it" \
  || fail_check "the out-of-range finding's site was not surfaced"
printf '%s' "$OUT" | jq -r '.messages|join(" ")' | grep -q 'out of the component' \
  && pass_check "and it is said in the messages, not only in evidence" \
  || fail_check "no message says a finding was suppressed as out of range"
verdict_is pass "an out-of-range finding is surfaced without failing the gate"

# AN UNREADABLE REF IS NOT ZERO SUPPRESSED FINDINGS. The refs are walked exactly as FINDING_SITES
# walks them, and one that does not resolve to a readable JSON object contributes nothing to the
# count -- so the count alone would read as "nothing was suppressed" on a record whose pointers are
# all broken. That is the false all-clear the kernel's own `range_check.status:"not_run"` exists to
# refuse, and this end of the channel has to refuse it the same way.
D=$(mktask oor_unreadable); write_record "$D" '.'
printf 'not json' > "$D/build-critique/main.critique.json"
run_cs "$D" "$CS_OK"
[ "$(ev_of out_of_range_unreadable_refs)" = "1" ] \
  && pass_check "a critique_ref that cannot be read is counted as unread" \
  || fail_check "an unreadable critique_ref was not counted (got $(ev_of out_of_range_unreadable_refs))"
[ "$(ev_of out_of_range_findings)" = "absent" ] \
  && pass_check "and no out-of-range count is claimed over a ref nobody could read" \
  || fail_check "an unreadable ref yielded an out-of-range count of $(ev_of out_of_range_findings)"
printf '%s' "$OUT" | jq -r '.messages|join(" ")' | grep -q 'unknown, not zero' \
  && pass_check "the message says the answer is unknown rather than zero" \
  || fail_check "the unreadable-ref case said nothing about what could not be read"

# An envelope with no `out_of_range` key at all -- every record written before the field existed --
# claims nothing and surfaces nothing. Absence of the key is not a count of zero, and it is not an
# unreadable ref either.
D=$(mktask oor_absent); write_record "$D" '.'
run_cs "$D" "$CS_OK"
[ "$(ev_of out_of_range_findings)" = "absent" ] \
  && pass_check "an envelope carrying no out_of_range[] adds no count" \
  || fail_check "a record with no out_of_range[] reported $(ev_of out_of_range_findings)"
[ "$(ev_of out_of_range_unreadable_refs)" = "absent" ] \
  && pass_check "and a readable envelope is never counted as an unreadable ref" \
  || fail_check "a readable envelope was counted as an unreadable ref"

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

# The [a]ddress path's scope invocation is EXECUTED, not grepped for. A spec that greps the body
# for a script name passes a broken invocation: the same body shipped a repair-accept step that
# redirected its diff into $(mktemp) and discarded the name, and reached main. So the lines are
# lifted out of the body verbatim, given only the two substitutions a reader makes by hand
# (`<component>` and the shell variables the surrounding block already sets), and run.
LIT="$T/scope-literal.sh"
awk 'index($0, "/scripts/repair-scope-check.sh") { s=1 }
     s { print; if ($0 !~ /\\[[:space:]]*$/) exit }' "$IMPL" \
  | sed 's/<component>/main/g' > "$LIT"
if [ ! -s "$LIT" ]; then
  fail_check "commands/implement.md carries no repair-scope-check.sh invocation to run"
else
  pass_check "the [a]ddress path carries a repair-scope-check.sh invocation"
  L=$(mktask literal); mkdir -p "$L/build-critique" >/dev/null 2>&1
  printf '%s' "$CRITIQUE" > "$L/build-critique/main.critique.json"
  printf 'M\tsrc/A.php\nA\tsrc/STRAY.php\n' > "$L/build-critique/main.repair.txt"
  set +e
  ( CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CD="$L/build-critique" bash "$LIT" ) >/dev/null 2>&1
  LRC=$?
  set -e
  [ "$LRC" = "0" ] \
    && pass_check "the invocation runs verbatim, exit 0" \
    || fail_check "the invocation as written in the body exited $LRC"
  [ -s "$L/build-critique/main.scope.json" ] \
    && pass_check "it writes the record the body says it writes" \
    || fail_check "the invocation left no readable scope record"
  [ "$(jq -r '.action' "$L/build-critique/main.scope.json" 2>/dev/null)" = "out_of_scope" ] \
    && pass_check "and the verdict is a real comparison, not an abstention" \
    || fail_check "the literal produced $(jq -r '.action // "nothing"' "$L/build-critique/main.scope.json" 2>/dev/null)"
  # The same literal, over the 0-byte diff git leaves when the range is wrong.
  : > "$L/build-critique/main.repair.txt"
  set +e
  ( CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CD="$L/build-critique" bash "$LIT" ) >/dev/null 2>&1
  set -e
  [ "$(jq -r '.action' "$L/build-critique/main.scope.json" 2>/dev/null)" = "cannot_judge" ] \
    && pass_check "and it abstains on a 0-byte repair diff rather than reporting a clean scope" \
    || fail_check "the literal read a 0-byte repair diff as $(jq -r '.action' "$L/build-critique/main.scope.json" 2>/dev/null)"
fi

# --------------------------------- 5c. the aggregate invocation's range wiring, EXECUTED
#
# THE DEFECT THIS DEFENDS AGAINST. `--component-files-from` is what makes the range check run at
# all: absent, the kernel stamps `range_check.status:"not_run"` and suppresses nothing, and the
# envelope is honest but unenforced. So the rung's own invocation is the whole enforcement, and
# nothing read it. Worse, the flag can be present and WRONG: pointed at `<component>.repair.txt`
# (the repair's own name-status range, which the rung also writes into the same folder) it still
# names a real file, still exits 0, and still stamps `ran` -- over a range the critics were never
# handed. A range file that disagrees with the one the critics were given is worse than none,
# because `ran` reads as "somebody compared".
#
# A spec that greps this body for `--component-files-from` passes both of those defects. Grepping
# is what let a `/design` step ship redirecting into `$(mktemp)` and discarding the name. So the
# invocation is lifted out of the body verbatim, given only the substitutions a reader makes by
# hand, and RUN against a fixture whose finding sits outside the range.

AGG="$T/aggregate-literal.sh"
awk 'index($0, "/scripts/wo-critique-aggregate.sh") { s=1 }
     s { print; if ($0 !~ /\\[[:space:]]*$/) exit }' "$IMPL" \
  | sed -e 's/<component>/main/g' -e 's/<risk_tier>/high/g' \
        -e 's/<number of lenses dispatched>/1/g' -e 's/\[--diff-empty\]//g' > "$AGG"

# The range the aggregator is handed must be the range the critics were handed: the file step 2
# writes and step 3 already reads for tiering. Both paths are read off the body and COMPARED, so a
# rewiring to any other file fails here even before the fixture runs.
CLS="$T/classify-literal.sh"
awk 'index($0, "/scripts/wo-risk-classify.sh") { s=1 }
     s { print; if ($0 !~ /\\[[:space:]]*$/) exit }' "$IMPL" \
  | sed 's/<component>/main/g' > "$CLS"
AGG_RANGE=$(grep -o -- '--component-files-from "[^"]*"' "$AGG" | head -1 | sed 's/.*"\(.*\)"/\1/')
CLS_RANGE=$(grep -o -- '--files-from "[^"]*"' "$CLS" | head -1 | sed 's/.*"\(.*\)"/\1/')

if [ ! -s "$AGG" ]; then
  fail_check "commands/implement.md carries no wo-critique-aggregate.sh invocation to run"
else
  pass_check "the build-critique rung carries a wo-critique-aggregate.sh invocation"
  [ -n "$AGG_RANGE" ] \
    && pass_check "it passes --component-files-from a path" \
    || fail_check "the aggregate invocation passes no --component-files-from range"
  [ -n "$CLS_RANGE" ] && [ "$AGG_RANGE" = "$CLS_RANGE" ] \
    && pass_check "and it is the same file step 3 tiers on, not a second range" \
    || fail_check "aggregate reads '$AGG_RANGE', the tiering step reads '$CLS_RANGE'"

  # The fixture: one critic, one critical finding, sited in a file the range does NOT contain.
  # `main.repair.txt` is a decoy carrying the finding's site, so an invocation rewired to it reads
  # a range that CONTAINS the site and goes blocking -- the mutation a name-grep cannot see.
  A=$(mktask agglit); CDA="$A/build-critique"; mkdir -p "$CDA/main.critics" >/dev/null 2>&1
  printf '%s' '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
    {"severity":"critical","text":"x","remedy":"fix","id":"f1","where":[{"file":"other/Z.php","line":9}]}]}' \
    > "$CDA/main.critics/main.critic-correctness.json"
  printf 'src/A.php\n'   > "$CDA/main.files.txt"
  printf 'other/Z.php\n' > "$CDA/main.repair.txt"

  set +e
  ( CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CD="$CDA" bash "$AGG" ) >/dev/null 2>&1
  ARC=$?
  set -e
  [ "$ARC" = "0" ] \
    && pass_check "the aggregate invocation runs verbatim, exit 0" \
    || fail_check "the aggregate invocation as written in the body exited $ARC"
  [ -s "$CDA/main.critique.json" ] \
    && pass_check "it writes the envelope the body says it writes" \
    || fail_check "the aggregate invocation left no readable critique envelope"
  [ "$(jq -r '.range_check.status' "$CDA/main.critique.json" 2>/dev/null)" = "ran" ] \
    && pass_check "the wiring actually reaches the range check, which ran" \
    || fail_check "range_check is $(jq -r '.range_check.status // "absent"' "$CDA/main.critique.json" 2>/dev/null): the flag never reached the kernel"
  [ "$(jq -r '.blocking' "$CDA/main.critique.json" 2>/dev/null)" = "false" ] \
    && pass_check "a critical sited outside the component's range opens no round" \
    || fail_check "the out-of-range critical still blocked: the range the critics were handed is not being applied"
  [ "$(jq -r '.out_of_range[0].id // "absent"' "$CDA/main.critique.json" 2>/dev/null)" = "f1" ] \
    && pass_check "and it is carried to /review in out_of_range[] rather than dropped" \
    || fail_check "the suppressed finding was discarded, not handed on"

  # The same literal, the same finding, the range now containing its site. Only the file's content
  # differs, so a mechanism that suppressed on anything other than the comparison fails here.
  printf 'other/Z.php\n' > "$CDA/main.files.txt"
  set +e
  ( CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CD="$CDA" bash "$AGG" ) >/dev/null 2>&1
  set -e
  [ "$(jq -r '.blocking' "$CDA/main.critique.json" 2>/dev/null)" = "true" ] \
    && pass_check "the same finding, in range, blocks" \
    || fail_check "an in-range critical did not block: the range is suppressing indiscriminately"
  [ "$(jq -r '.out_of_range | length' "$CDA/main.critique.json" 2>/dev/null)" = "0" ] \
    && pass_check "and nothing is handed to review when nothing was out of range" \
    || fail_check "an in-range finding was still reported out of range"
fi

if [ "$FAIL" = "0" ]; then
  printf '\nbuild-critique-gate-spec: all checks passed\n'
else
  printf '\nbuild-critique-gate-spec: FAILURES\n' >&2
fi
exit "$FAIL"
