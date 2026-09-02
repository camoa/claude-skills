#!/usr/bin/env bash
# build-identity-spec.sh — is the critique record about the code being reviewed?
#
# Every check in build-critique-assert.sh asked whether the record was internally consistent:
# counts agree, gaps carry reasons, no component blocking, the contract re-derived from disk.
# All of them are questions about the record. None was a question about the tree.
#
# `/review`'s remediate branch turns that from a risk into a certainty. `[r]` means exit, fix,
# re-run — fixing is the entire point — so every remediation produces a build the record predates.
# Observed live: three hard-block gates failed, the operator chose [r], eleven files changed
# including a deleted branch and a new test fixture, and the re-run would have read the same
# record and passed. The gate whose question is "was this build challenged by something other than
# the context that built it?" would have answered yes about the previous build.
#
# The record already carried checkpoint shas. They sat in `components[].range` as free-text prose
# that nothing parsed, which is the recurring shape: the fact was present and no code read it.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="${PLUGIN_ROOT}/scripts/build-critique-assert.sh"
CS="${PLUGIN_ROOT}/scripts/review-change-set.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
for f in "$A" "$CS"; do [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }; done
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { printf 'FAIL: sha256sum required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

digest() { # digest <file...> — the same computation the record and the gate both make
  printf '%s' "$(printf '%s\n' "$@" | sort)" | sha256sum | cut -d' ' -f1
}

# A record that passes every OTHER check in the script, so anything red here is this check.
mkrec() { # mkrec <dir> <head> <files_digest_json_array_or_null> <files json>
  local d="$1" head="$2" dg="$3" files="$4"
  mkdir -p "$d"
  local bi='null'
  if [ "$head" != "NONE" ]; then
    bi=$(jq -nc --arg h "$head" --arg d "$dg" --argjson f "$files" \
      '{head:$h, files_digest:$d, files:$f}')
  fi
  jq -n --argjson bi "$bi" '{
    schema_version:"1.9", gate_type:"build-critique",
    fired_at:"2026-08-29T00:00:00Z", plugin_version:"5.35.5",
    task_folder:"/x", user_choice:null, bypass_reason:null,
    gate_specific:{
      phase:"implement", verdict:"pass",
      components_declared:1, components_critiqued:1, uncritiqued:[],
      components:[{component:"c1", verdict:"pass", blocking:false, runtime:"executed"}],
      alignment:{ran:true, verdict:"pass", criteria_unverifiable:[]},
      tdd:{red_observed:1, passed_first_run:0, ratified:0, unobserved:[]},
      contract:{baseline:"captured", changed:[], reason:null},
      closing_fixes:{applied:0},
      build_identity:$bi
    }}' > "$d/_build-critique.json"
}

mkcs() { # mkcs <path> <head> <file...>
  local p="$1" head="$2"; shift 2
  jq -n --arg h "$head" --args '{schema_version:"1.0", base:"main", merge_base:"abc",
    head:(if $h=="" then null else $h end), files:$ARGS.positional,
    untracked:[], empty_reason:null, warnings:[]}' "$@" > "$p"
}

HEAD_A=1111111111111111111111111111111111111111
HEAD_B=2222222222222222222222222222222222222222
F1="src/A.php"; F2="src/B.php"; F3="src/C.php"

# --- review-change-set.sh reports the head it resolved ---------------------------
# The gate compares against this, so the field has to exist and be a real commit.
R=$(cd "$PLUGIN_ROOT" && bash "$CS" --base main --repo "$PLUGIN_ROOT" 2>/dev/null) || R='{}'
jq -e 'has("head")' <<<"$R" >/dev/null 2>&1 \
  && pass_check "review-change-set.sh reports a head" \
  || fail_check "review-change-set.sh must report the head its change set was resolved against"
jq -e '(.head // "") | test("^[0-9a-f]{40}$")' <<<"$R" >/dev/null 2>&1 \
  && pass_check "the reported head is a real commit sha" \
  || fail_check "head must be a 40-char sha inside a git repository"

# --- the matching case passes ----------------------------------------------------
D="$T/match"; mkrec "$D" "$HEAD_A" "$(digest "$F1" "$F2")" "$(jq -nc --args '$ARGS.positional' "$F1" "$F2")"
mkcs "$T/cs-match.json" "$HEAD_A" "$F1" "$F2"
RC=0; OUT=$(bash "$A" "$D" --change-set-file "$T/cs-match.json" 2>&1) || RC=$?
[ "$RC" = "0" ] && [ "$(jq -r .verdict <<<"$OUT")" = "pass" ] \
  && pass_check "a record describing this exact build passes" \
  || fail_check "the matching case must pass, got rc=$RC verdict=$(jq -r .verdict <<<"$OUT" 2>/dev/null)"
[ "$(jq -r '.evidence.build_identity' <<<"$OUT")" = "matches" ] \
  && pass_check "the evidence records that the identity matched" \
  || fail_check "a matching identity must be recorded as evidence"

# --- file order does not matter --------------------------------------------------
# The digest is over a sorted list, so a change set that lists the same files differently is the
# same build. Getting this wrong would fail every review for a reason nobody could act on.
mkcs "$T/cs-order.json" "$HEAD_A" "$F2" "$F1"
RC=0; bash "$A" "$D" --change-set-file "$T/cs-order.json" >/dev/null 2>&1 || RC=$?
[ "$RC" = "0" ] \
  && pass_check "the same files in a different order are the same build" \
  || fail_check "the digest must be order-independent, got rc=$RC"

# --- a file the critics never saw is caught --------------------------------------
# The live case: remediation after [r] adds files, and the record predates all of them.
mkcs "$T/cs-extra.json" "$HEAD_A" "$F1" "$F2" "$F3"
RC=0; OUT=$(bash "$A" "$D" --change-set-file "$T/cs-extra.json" 2>&1) || RC=$?
[ "$RC" != "0" ] && [ "$(jq -r .verdict <<<"$OUT")" = "fail" ] \
  && pass_check "a change set containing a file no critic saw fails" \
  || fail_check "an unseen file must fail the gate, got rc=$RC"
[ "$(jq -r '.unresolved' <<<"$OUT")" = "true" ] \
  && pass_check "the failure is unresolved — the gate could not tell, it did not find a defect" \
  || fail_check "a stale record is an unresolved state, not a substantive finding"
jq -r '.messages[]' <<<"$OUT" | grep -q "$F3" \
  && pass_check "the message names the file no critic saw" \
  || fail_check "the operator must be told WHICH file was never critiqued"

# --- a moved head is caught even when the file set is identical ------------------
# Same files, amended content: a commit after the critique with no new paths. The digest cannot
# see this, which is exactly why head is compared too.
mkcs "$T/cs-head.json" "$HEAD_B" "$F1" "$F2"
RC=0; OUT=$(bash "$A" "$D" --change-set-file "$T/cs-head.json" 2>&1) || RC=$?
[ "$RC" != "0" ] \
  && pass_check "the same file set at a different head is a different build" \
  || fail_check "a moved head must fail even when no file was added"
jq -r '.messages[]' <<<"$OUT" | grep -q "$HEAD_B" \
  && pass_check "the message names both heads" \
  || fail_check "the operator must be told which head the record has and which one is under review"

# --- a record with no build identity cannot answer, and does not pass ------------
# Deliberately no grandfather clause. A record written before this field existed is a record that
# cannot say which build it describes, and its age does not make it able to answer.
D2="$T/noid"; mkrec "$D2" NONE "" '[]'
RC=0; OUT=$(bash "$A" "$D2" --change-set-file "$T/cs-match.json" 2>&1) || RC=$?
[ "$RC" != "0" ] && [ "$(jq -r .unresolved <<<"$OUT")" = "true" ] \
  && pass_check "a record with no build_identity is unresolved, never a pass" \
  || fail_check "an absent build_identity must be fail-closed, got rc=$RC"
[ "$(jq -r '.evidence.build_identity' <<<"$OUT")" = "absent" ] \
  && pass_check "the evidence says the identity was absent rather than wrong" \
  || fail_check "absent and mismatched must be distinguishable in the evidence"

# --- a half-filled identity identifies nothing -----------------------------------
D3="$T/partial"; mkrec "$D3" "$HEAD_A" "" "$(jq -nc --args '$ARGS.positional' "$F1")"
RC=0; OUT=$(bash "$A" "$D3" --change-set-file "$T/cs-match.json" 2>&1) || RC=$?
[ "$RC" != "0" ] && [ "$(jq -r '.evidence.build_identity' <<<"$OUT")" = "incomplete" ] \
  && pass_check "an identity missing files_digest is incomplete, not silently trusted" \
  || fail_check "a half-filled build_identity must fail as incomplete"

# --- the gate refuses to answer when it was handed no change set -----------------
# The failure mode that would quietly restore the old behaviour: a caller that drops the flag
# gets a gate which cannot compare anything. That must not read as a pass.
RC=0; OUT=$(bash "$A" "$D" 2>&1) || RC=$?
[ "$RC" != "0" ] && [ "$(jq -r '.evidence.build_identity' <<<"$OUT")" = "uncompared" ] \
  && pass_check "no change set means the gate cannot tell, and says so" \
  || fail_check "a missing --change-set-file must be unresolved, got rc=$RC"

RC=0; OUT=$(bash "$A" "$D" --change-set-file "$T/nope.json" 2>&1) || RC=$?
[ "$RC" != "0" ] \
  && pass_check "an unreadable change set file is unresolved, not a pass" \
  || fail_check "a missing change set file must fail closed"

# --- the writer requires the field ------------------------------------------------
grep -q 'build-critique).*build_identity' "$PLUGIN_ROOT/scripts/gate-audit-write.sh" \
  && pass_check "gate-audit-write.sh lists build_identity among the documented keys" \
  || fail_check "build_identity must be in the build-critique REQUIRED_KEYS"

# --- both halves of the contract are documented -----------------------------------
# The defect fixed alongside this one was a command calling a script with an argument the script
# rejected, for five releases, because nothing compared the caller against the callee.
grep -q -- '--change-set-file' "$PLUGIN_ROOT/commands/review.md" \
  && pass_check "commands/review.md passes the change set to the gate" \
  || fail_check "review.md must call build-critique-assert.sh with --change-set-file"
grep -q 'build_identity' "$PLUGIN_ROOT/commands/implement.md" \
  && pass_check "commands/implement.md tells the rung to record build_identity" \
  || fail_check "implement.md must document the build_identity the review gate requires"
grep -q 'build_identity' "$PLUGIN_ROOT/references/gate-audit-schema.md" \
  && pass_check "the schema documents build_identity" \
  || fail_check "gate-audit-schema.md must document build_identity"

if [ "$FAIL" = "0" ]; then
  printf '\nAll invariants pass for build identity.\n'
else
  printf '\nbuild-identity-spec: FAILURES\n' >&2
  exit 1
fi
