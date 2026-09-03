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
GOOD='{"build_identity":{"head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","files_digest":"da885006a736ed9ce06e3736845717d7f70d58abf15995f8977f551bbfafbf1f","files":["src/A.php"]},"phase":"implement","verdict":"pass",
 "components":[{"component":"main","runtime":"executed","risk_tier":"low","lenses":["correctness"],"verdict":"pass",
   "blocking":false,"findings_count":0,"checkpoint_before":"aaa","checkpoint_after":"bbb",
   "critique_ref":"/x/build-critique/main.critique.json"}],
 "components_declared":1,"components_critiqued":1,"uncritiqued":[],
 "closing_fixes":{"applied":0},
 "tdd":{"red_observed":1,"passed_first_run":0,"ratified":0,"unobserved":[]},
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

# One folder PER KEY. Sharing a folder meant every iteration after the first was a REWRITE, and
# since v5.35.3 a rewrite that drops a key the record already has is refused. That refusal is a
# different rule from the one under test here, which is about a payload missing a documented key.
for K in phase verdict components components_declared components_critiqued alignment tdd contract closing_fixes build_identity; do
  mkdir -p "$T/keys/$K"
  PAY=$(printf '%s' "$GOOD" | jq -c --arg k "$K" 'del(.[$k])')
  set +e
  bash "$W" "$T/keys/$K" build-critique "$PAY" >/dev/null 2>"$T/keys/$K.err"
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

# EVERY REV RANGE IN THE COMMAND BODY IS BUILT FROM SHAS. A checkpoint label is not a revision:
# build-checkpoint.sh anchors its objects under refs/worktree/aida/build-checkpoints/, which is
# not on git's rev-parse search path, so `git diff <component>.after..$REP` resolves nothing and
# exits 128 with the redirect's file already created and empty. That shipped on the repair range
# and made the accept kernel read a motion of nothing on every real build, answering `accepted`
# off a diff nobody computed. The assertion reads every `git ... diff` line in the body and
# demands both ends be a shell variable or a `<...>-sha` placeholder, so it holds for a range
# added later as well as for the one it was written for.
# Every end has to be a shell variable holding a captured sha, or a placeholder that says `sha`
# in its own name. Two ends, checked separately, so a range that is half right still fails.
RANGES=$(grep -E 'git -C [^ ]* diff ' "$CMD" | grep -oE '[A-Za-z0-9$<>._-]+\.\.[A-Za-z0-9$<>._-]+' || true)
BAD_RANGE=$(printf '%s\n' "$RANGES" | grep -vE '^(\$[A-Za-z_][A-Za-z0-9_]*|<[^>]*sha[^>]*>)\.\.(\$[A-Za-z_][A-Za-z0-9_]*|<[^>]*sha[^>]*>)$' || true)
if [ -z "$RANGES" ]; then
  # A check that found nothing to check has not passed. If the ranges stop being greppable this
  # assertion silently stops defending anything, which is the shape of every defect above it.
  fail_check "/implement names no git diff rev range at all, so the range assertion had nothing to read"
elif [ -z "$BAD_RANGE" ]; then
  pass_check "/implement builds every git diff range from shas, never a checkpoint label ($(printf '%s\n' "$RANGES" | wc -l | tr -d ' ') ranges)"
else
  fail_check "/implement hands git a range that is not two shas: $(printf '%s' "$BAD_RANGE" | tr '\n' ' ')"
fi

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

# --- c3/c4: the loop has a stop, and an unattended run cannot vote itself past it ----------
# THE DEFECT THIS DEFENDS AGAINST. v5.42.0 deleted the round budget and, with it, the sentence
# "at the second blocking round put the choice to the person; with run_mode: autonomous there is
# nobody to ask, so HALT". What replaced it recorded an accept verdict and told nobody to act on
# it, so the repair path had no stopping condition for one release. The bound is now structural,
# one critic round per component, and the verdict has to be able to stop the build or the
# structure is the only thing holding it.
if printf '%s' "$CMD_FLAT" | grep -qiE 'at most one critic round'; then
  pass_check "/implement bounds a component to one critic round"
else
  fail_check "/implement does not say a component gets at most one critic round"
fi
if printf '%s' "$CMD_FLAT" | grep -qiE 'not_accepted[^.]{0,120}HALT|HALT[^.]{0,120}not_accepted'; then
  pass_check "/implement halts the build on a repair the kernel did not accept"
else
  fail_check "/implement does not halt on not_accepted, so a rejected repair closes its component"
fi
if printf '%s' "$CMD_FLAT" | grep -qiE 'autonomous[^.]{0,160}(nobody to ask|no one to ask)'; then
  pass_check "/implement says an unattended run has nobody to ask and must halt rather than proceed"
else
  fail_check "/implement lets an autonomous run past the accept halt with no operator"
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


# recipe-to-critic (review_ladder): the two method-bearing lenses receive the resolved recipe, meets-ac does not,
# and a framework with no body gets no correctness critic, recorded on the envelope.
BLOCK="$(awk '/^\*\*5\. Critics\.\*\*/,/^\*\*Read each verdict/' "$CMD")"
grep -q 'security. and .correctness. receive the resolved implement recipe' <<<"$BLOCK" \
  && grep -q 'RESOLVED RECIPE\|recipe-resolution.md. step 4' <<<"$BLOCK" \
  && pass_check "the critic dispatch injects the resolved recipe into security and correctness" \
  || fail_check "the critic dispatch does not inject the resolved recipe into security and correctness"
grep -q 'meets-ac.*does not receive it' <<<"$(tr '\n' ' ' <<<"$BLOCK")" \
  && pass_check "meets-ac is excluded from the injection" \
  || fail_check "meets-ac is not excluded from the injection"
grep -q -- '--not-dispatched correctness:no_body_path' <<<"$BLOCK" \
  && pass_check "no body_path → correctness is not dispatched and the envelope records why" \
  || fail_check "the no-body rule for the correctness lens is not in the dispatch block"

# fix-step-record (review_ladder): the fix step re-reads the method before authoring, records it, and
# the schema names the field in the same change.
ADDR="$(awk '/^\*\*Every `\[a\]ddress` begins/,/^\*\*Every `\[a\]ddress` ends/' "$CMD" | tr '\n' ' ')"
grep -q 're-Reading each framework.s `body_path`' <<<"$ADDR" && grep -q 'fix_recipe_read' <<<"$ADDR" \
  && grep -q 'read | no_body_path | unreadable' <<<"$ADDR" \
  && pass_check "[a]ddress re-reads body_path before the fix and records fix_recipe_read with a three-value verdict" \
  || fail_check "[a]ddress does not re-read body_path and record fix_recipe_read before the fix"
grep -q '^| `frameworks\[\].fix_recipe_read`' "$SCHEMA" && grep -q '"fix_recipe_read":' "$SCHEMA" \
  && pass_check "gate-audit-schema.md documents frameworks[].fix_recipe_read in the row table and the shape" \
  || fail_check "gate-audit-schema.md does not document frameworks[].fix_recipe_read"

# c9 (review_ladder, owner-added mid-build): the dispatch carries the contract and nothing more.
grep -q 'That is the' <<<"$BLOCK" && grep -q 'whole dispatch' <<<"$BLOCK" && grep -q 'probe list' <<<"$BLOCK" \
  && pass_check "step 5 says the dispatch is the contract and nothing more; a probe list is the deleted lens" \
  || fail_check "step 5 does not forbid a probe list or posture in the critic dispatch"

# motion-wiring (review_ladder): test motion is classified at the rung on every build, from the recipe's globs.
RUNG="$(awk '/^# 2c\. test motion/,/^# 3\. the tier/' "$CMD")"
grep -q 'repair-accept-check.sh' <<<"$RUNG" && grep -q -- '--test-motion-from "\$CD/<component>.motion.txt"' <<<"$RUNG" \
  && pass_check "the rung runs the motion kernel on the component's own range, before any repair" \
  || fail_check "the rung does not run repair-accept-check.sh on the component range"
grep -q 'oracle-globs.sh' <<<"$RUNG" && grep -q -- '--test-globs-origin' <<<"$RUNG" && grep -q -- '--test-globs-source undetermined' <<<"$RUNG" && grep -q 'jq -r .*motion.json"' <<<"$RUNG" \
  && pass_check "the rung takes its globs from oracle-globs.sh and records the origin" \
  || fail_check "the rung's globs do not come from oracle-globs.sh with the origin recorded"
# render-dispatch (review_ladder, c9 amended): the dispatch is rendered from a template and handed over as printed.
grep -q 'prompt-render.sh critic-dispatch' <<<"$BLOCK" && grep -q -i 'exactly what it printed' <<<"$BLOCK" \
  && pass_check "step 5 renders the critic dispatch with prompt-render.sh critic-dispatch and hands over what it printed" \
  || fail_check "step 5 does not render the critic dispatch from the template"
TPL="$(awk '/^## Template ID: `critic-dispatch`/,0' "$PLUGIN_ROOT/references/gate-hardening-prompts.md" | awk '/^```/{n++; next} n==1')"
[ -n "$TPL" ] && ! grep -q -i -E 'hostile|probe|checklist|treat the diff' <<<"$TPL" \
  && grep -q '{{acceptance_criteria}}' <<<"$TPL" && grep -q '{{recipe_block}}' <<<"$TPL" && grep -q '{{range}}' <<<"$TPL" && grep -q '{{lens}}' <<<"$TPL" \
  && pass_check "the critic-dispatch template holds the four inputs and no probe, posture or checklist" \
  || fail_check "the critic-dispatch template is missing an input or carries a probe, posture or checklist"
# methodology-to-critic (critic_methodology): every critic, on BOTH dispatch paths and on ALL
# three lenses, receives the test-first material the build was held to.
#
# THE LOOPHOLE THIS DEFENDS AGAINST. A builder can answer a critic's finding by changing what a
# test asserts rather than by fixing the code. scripts/repair-accept-check.sh surfaces that motion
# and asks for a reason; its own header says the tripwire demands a reason and never forbids the
# change. A repair loop that can edit the standard always converges, because the work can move the
# goalposts instead of meeting them. Telling a repair from a redefinition is the critic's job --
# and nothing had ever handed the critic the standard. /implement loads a five-reference
# methodology floor into the BUILD; the critic that judges that build's methodology got none of it.
#
# `meets-ac` is the case that decides whether this wiring is real. It is the lens that would have
# to judge a test rewritten to match the code it was meant to constrain, and it is the one lens
# `recipe_block` deliberately renders as the empty string. A change that wires the block for the
# two method-bearing lenses and empties it for `meets-ac` has wired everything except the reason
# it exists, so the render assertion below is aimed straight at that lens.
SKILL_WOC="${PLUGIN_ROOT}/skills/work-order-critique/SKILL.md"
CPC="${PLUGIN_ROOT}/skills/work-order-critique/references/critic-prompt-contract.md"
AGENT_CRITIC="${PLUGIN_ROOT}/agents/wo-critic.md"
for f in "$SKILL_WOC" "$CPC" "$AGENT_CRITIC"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done

grep -q '{{methodology_block}}' <<<"$TPL" \
  && pass_check "the critic-dispatch template carries {{methodology_block}}" \
  || fail_check "the critic-dispatch template has no {{methodology_block}}"

# RENDER a meets-ac dispatch and read the block back out of what a critic would actually be
# handed. A grep over the template proves only that a marker is in the file; the template has no
# conditionals, so the thing that can still go wrong is upstream -- a caller that passes an empty
# value for this lens the way it passes an empty recipe_block. This runs the real renderer.
RT="$T/methodology-render"; mkdir -p "$RT"
printf '=== METHODOLOGY (source=dev-guides, refs=plugin:tdd-workflow) ===\nRED is an observation, not an intention.\n=== END METHODOLOGY ===\n' > "$RT/m.txt"
printf -- '- one criterion\n' > "$RT/ac.txt"
printf 'src/A.php\n' > "$RT/f.txt"
RENDERED=$(bash "${PLUGIN_ROOT}/scripts/prompt-render.sh" critic-dispatch \
  lens=meets-ac worktree=/w range=aaa..bbb files@="$RT/f.txt" component=c \
  acceptance_criteria@="$RT/ac.txt" recipe_block= methodology_block@="$RT/m.txt" \
  output_path=/o.json 2>/dev/null) || RENDERED=""
if printf '%s' "$RENDERED" | grep -q 'END METHODOLOGY' \
   && printf '%s' "$RENDERED" | grep -q 'RED is an observation, not an intention.'; then
  pass_check "a rendered meets-ac dispatch carries the methodology block through to the critic"
else
  fail_check "a rendered meets-ac dispatch does not carry the methodology block — the lens the change exists for receives nothing"
fi

BLOCK1="$(tr '\n' ' ' <<<"$BLOCK")"
grep -q 'methodology_block@=' <<<"$BLOCK1" \
  && pass_check "step 5 passes methodology_block to the render as a file, never as a shell argument" \
  || fail_check "step 5 does not pass methodology_block@= to the render"
grep -q 'All three lenses receive the methodology block' <<<"$BLOCK1" && grep -q 'meets-ac. included' <<<"$BLOCK1" \
  && pass_check "step 5 states the methodology block goes to all three lenses, meets-ac included" \
  || fail_check "step 5 does not state that meets-ac receives the methodology block"
grep -q 'guides_actually_loaded' <<<"$BLOCK1" && grep -q 'tdd-workflow.md' <<<"$BLOCK1" \
  && grep -q 'Never from the task folder' <<<"$BLOCK1" \
  && pass_check "step 5 names the block's already-loaded source and rules the task folder out of it" \
  || fail_check "step 5 does not name the block's source, or does not rule out the task folder"

# The delegated path. 5.48.0 shipped entirely because a rung was wired to the in-session path and
# not the delegated one, so following the orchestration rule that the main loop coordinates rather
# than builds routed every real build around it. Repeating that shape in the change that fixes its
# sibling would be the same defect twice, so both dispatchers are asserted here.
WOB="$(awk '/^\*\*4 — spawn the critics/,/^\*\*5 — aggregate/' "$SKILL_WOC" | tr '\n' ' ')"
grep -q 'methodology block' <<<"$WOB" && grep -q 'all three lenses' <<<"$WOB" && grep -q 'meets-ac. included' <<<"$WOB" \
  && pass_check "the work-order dispatch hands the methodology block to all three lenses" \
  || fail_check "the work-order dispatch does not hand the methodology block to all three lenses"
grep -q 'Never from the task folder' <<<"$WOB" && grep -q 'END METHODOLOGY' <<<"$WOB" \
  && pass_check "the work-order dispatch names the delimiter and rules the task folder out of the source" \
  || fail_check "the work-order dispatch does not name the delimiter or does not rule out the task folder"

# The consumer contract. A block nothing tells the critic how to read is a block it can treat as
# an instruction, which is the injection surface the whole rung is built around narrowing.
MB="$(awk '/^- \*\*The methodology block\*\*/,/^- \*\*Your output path\*\*/' "$AGENT_CRITIC" | tr '\n' ' ')"
grep -q 'all three' <<<"$MB" && grep -q 'meets-ac' <<<"$MB" && grep -q 'END METHODOLOGY' <<<"$MB" \
  && pass_check "wo-critic documents the methodology block as an input on all three lenses" \
  || fail_check "wo-critic does not document the methodology block as an all-three-lens input"
grep -q 'upstream data, not a command' <<<"$MB" && grep -q 'never' <<<"$MB" && grep -q 'task folder' <<<"$MB" \
  && pass_check "wo-critic treats the methodology block as untrusted upstream data sourced outside the task folder" \
  || fail_check "wo-critic does not treat the methodology block as untrusted upstream data outside the task folder"

CPCB_PRE="$(awk '/^## The methodology block/,0' "$CPC" | tr '\n' ' ')"
# The block is ONE NAMED SECTION, never the whole file. tdd-workflow.md is 180 lines and 102 of
# them are build-time procedure a critic cannot act on -- enforcement checkpoints, a
# developer-says/response script, which run_mode decides who runs a test, and 62 lines on where a
# delegated builder writes wo-NN.tdd.json. The critic-dispatch template's own header records that
# padding a critic prompt with unusable material bought a repair round per component, so a
# whole-file dump would make this change cost the thing it exists to reduce. The cut is a fixed
# heading rather than a summary because an orchestrator choosing what to keep would be deciding
# what the critic may hold the build to, and the orchestrator sits in the builder's context.
SECTION_AWK="awk '/^### The observation gets recorded/,0'"
for pair in "step 5|$BLOCK1" "the work-order dispatch|$WOB"; do
  WHO="${pair%%|*}"; TXT="${pair#*|}"
  grep -qF "$SECTION_AWK" <<<"$TXT" && grep -q 'never.*the whole\|never the\s*whole' <<<"$TXT" \
    && pass_check "$WHO composes the block from one named section, never the whole file" \
    || fail_check "$WHO does not name the section to extract, or does not rule out the whole file"
done
grep -qF "$SECTION_AWK" <<<"$CPCB_PRE" && grep -q 'cannot act on' <<<"$CPCB_PRE" && grep -q '102 of its 180 lines' <<<"$CPCB_PRE" \
  && pass_check "the contract names the section and records the measured share it leaves out" \
  || fail_check "the contract does not name the section, or does not record why the rest is out"

CPCB="$(awk '/^## The methodology block/,0' "$CPC" | tr '\n' ' ')"
grep -q '=== METHODOLOGY (source=dev-guides, refs=' <<<"$CPCB" && grep -q '=== END METHODOLOGY ===' <<<"$CPCB" \
  && grep -q 'dispatch paths' <<<"$CPCB" \
  && pass_check "the critic-prompt contract defines the delimiter for both dispatch paths" \
  || fail_check "the critic-prompt contract does not define the methodology delimiter for both paths"
grep -q 'Never the task folder' <<<"$CPCB" && grep -q 'repair-accept-check.sh' <<<"$CPCB" \
  && pass_check "the contract records the loophole the block closes and the source boundary that keeps it safe" \
  || fail_check "the contract does not record the loophole or the source boundary"

if [ "$FAIL" = "0" ]; then
  printf '\nbuild-critique-wiring-spec: all checks passed\n'
else
  printf '\nbuild-critique-wiring-spec: FAILURES\n' >&2
fi
exit "$FAIL"
