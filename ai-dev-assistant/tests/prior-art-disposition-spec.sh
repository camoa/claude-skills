#!/usr/bin/env bash
# Behavioral spec for scripts/prior-art-disposition.sh — the deterministic verdict router.
#
# Two jobs, both of which MUST be deterministic, because a rejection an LLM performs on itself is
# not a rejection:
#
#   (a) THE MATRIX. verdict {none,reuse,extend,supersede} × mode {attended,unattended}
#       → {action, blocks, decided_by}. Exhaustive: 8 cells.
#       Load-bearing cells:
#         - any attended hit          → surface + blocks (the human decides; nothing is auto-applied)
#         - unattended supersede      → downgrade to extend + defer (a supersede widens scope and
#                                       creates a migration task; never commit that with no human)
#         - none                      → proceed, never blocks
#
#   (b) THE CITATION FLOOR. The contract says three things must be REJECTED, not warned about:
#       a verdict naming no cost dimension; an uncited supersede; a supersede resting only on build
#       cost or only on judgment. Plus the absorb rule: a supersede whose replacement cannot absorb
#       the superseded use case is not a supersede, it is a second implementation with better
#       opinions, and it downgrades to extend.
#
# Cost classes: build (paid once) / carry, agent, risk (paid forever). A supersede must win on the
# RECURRING classes — "I would have written it differently" is a build-cost preference.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/prior-art-disposition.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }
[ -f "$K" ] || { echo "FAIL: $K does not exist"; echo "1 failed"; exit 1; }

# exp <verdict> <mode> <extra-args...> -- expects action/blocks/decided_by via globals EA/EB/ED
run(){ "$K" "$@" 2>/dev/null; }
cell(){ # cell <verdict> <mode> <exp_action> <exp_blocks> <exp_decided_by> [extra args...]
  local v="$1" m="$2" ea="$3" eb="$4" ed="$5"; shift 5
  local out a b d
  out="$(run --verdict "$v" --mode "$m" "$@")"
  a="$(jq -r '.action'     <<<"$out")"
  b="$(jq -r '.blocks'     <<<"$out")"
  d="$(jq -r '.decided_by' <<<"$out")"
  if [ "$a" = "$ea" ] && [ "$b" = "$eb" ] && [ "$d" = "$ed" ]; then ok
  else no "$v/$m $* => {$a,$b,$d} expected {$ea,$eb,$ed}"; fi
}

# A supersede that satisfies the floor: names a recurring dimension AND cites a measured value.
GOOD_SUPERSEDE=(--dimensions "carry:change-amplification,agent:context-to-load,risk:security-surface"
                --measured "agent:context-to-load=11000 tokens across two implementations"
                --absorbs true)

# =====================================================================================
# 1. THE MATRIX — all 8 cells.
# =====================================================================================
cell none      attended   proceed false auto
cell none      unattended proceed false auto
cell reuse     attended   surface true  human
cell extend    attended   surface true  human
cell supersede attended   surface true  human "${GOOD_SUPERSEDE[@]}"
cell reuse     unattended confirm false agent
cell extend    unattended confirm false agent
# The one place the design refuses to follow the pattern mechanically.
cell supersede unattended downgrade_defer false deferred "${GOOD_SUPERSEDE[@]}"

# An unattended supersede must actually come back as `extend`, not merely be labelled deferred.
OUT="$(run --verdict supersede --mode unattended "${GOOD_SUPERSEDE[@]}")"
[ "$(jq -r '.effective_verdict' <<<"$OUT")" = "extend" ] && ok \
  || no "unattended supersede must downgrade to extend, got $(jq -r '.effective_verdict' <<<"$OUT")"
[ "$(jq -r '.resurface_next_attended' <<<"$OUT")" = "true" ] && ok \
  || no "a deferred supersede must be flagged to re-surface on the next attended run"

# =====================================================================================
# 2. CITATION FLOOR — a verdict naming NO dimension is rejected. Applies to every
#    non-`none` verdict, not just supersede: "reuse this" with no reasoning is a guess.
# =====================================================================================
for v in reuse extend supersede; do
  OUT="$(run --verdict "$v" --mode attended)"
  [ "$(jq -r '.admissible' <<<"$OUT")" = "false" ] && ok || no "$v with no dimensions should be inadmissible"
  jq -e '.rejection_reason | test("dimension"; "i")' >/dev/null <<<"$OUT" && ok \
    || no "$v with no dimensions must say WHY it was rejected"
done

# `none` needs no dimensions — there is nothing to justify.
OUT="$(run --verdict none --mode attended)"
[ "$(jq -r '.admissible' <<<"$OUT")" = "true" ] && ok || no "verdict=none should not require dimensions"

# =====================================================================================
# 3. CITATION FLOOR — an UNCITED supersede is rejected and downgraded to extend.
#    Dimensions named but nothing measured = an assertion wearing a citation's clothes.
# =====================================================================================
OUT="$(run --verdict supersede --mode attended \
        --dimensions "carry:change-amplification,agent:context-to-load" --absorbs true)"
[ "$(jq -r '.admissible' <<<"$OUT")" = "false" ] && ok || no "uncited supersede should be inadmissible"
[ "$(jq -r '.effective_verdict' <<<"$OUT")" = "extend" ] && ok \
  || no "an inadmissible supersede must downgrade to extend, got $(jq -r '.effective_verdict' <<<"$OUT")"
jq -e '.rejection_reason | test("cite|measur"; "i")' >/dev/null <<<"$OUT" && ok \
  || no "uncited supersede must name citation as the reason"

# =====================================================================================
# 4. CITATION FLOOR — a supersede resting ONLY on build cost is rejected. Build cost is
#    paid once; carry, agent and risk are paid forever. "I'd have written it differently"
#    is a build-cost preference and does not clear the bar.
# =====================================================================================
OUT="$(run --verdict supersede --mode attended \
        --dimensions "build:implementation-effort" \
        --measured "build:implementation-effort=2 days" --absorbs true)"
[ "$(jq -r '.admissible' <<<"$OUT")" = "false" ] && ok || no "build-only supersede should be inadmissible"
[ "$(jq -r '.effective_verdict' <<<"$OUT")" = "extend" ] && ok || no "build-only supersede must downgrade"
jq -e '.rejection_reason | test("recurring|build"; "i")' >/dev/null <<<"$OUT" && ok \
  || no "build-only rejection must explain the recurring-cost rule"

# =====================================================================================
# 5. CITATION FLOOR — a supersede whose dimensions are ALL judgment (nothing measurable
#    cited) is rejected. Judgment is allowed IN a verdict; it cannot BE the whole verdict.
# =====================================================================================
OUT="$(run --verdict supersede --mode attended \
        --dimensions "carry:comprehension,risk:reversibility" --absorbs true)"
[ "$(jq -r '.admissible' <<<"$OUT")" = "false" ] && ok || no "judgment-only supersede should be inadmissible"

# =====================================================================================
# 6. THE ABSORB RULE — a supersede whose replacement cannot absorb the superseded use
#    case downgrades to extend. Otherwise the verdict CREATES the duplication this whole
#    feature exists to prevent: judge the new thing better, defer the migration, and now
#    two implementations live side by side forever.
# =====================================================================================
OUT="$(run --verdict supersede --mode attended \
        --dimensions "carry:change-amplification,agent:context-to-load" \
        --measured "carry:change-amplification=7 call sites" --absorbs false)"
[ "$(jq -r '.effective_verdict' <<<"$OUT")" = "extend" ] && ok \
  || no "a non-absorbing supersede must become extend, got $(jq -r '.effective_verdict' <<<"$OUT")"
jq -e '.rejection_reason | test("absorb"; "i")' >/dev/null <<<"$OUT" && ok \
  || no "the absorb rejection must name the absorb rule"

# An admissible supersede survives intact when attended.
OUT="$(run --verdict supersede --mode attended "${GOOD_SUPERSEDE[@]}")"
[ "$(jq -r '.admissible' <<<"$OUT")" = "true" ] && ok || no "a well-formed supersede should be admissible"
[ "$(jq -r '.effective_verdict' <<<"$OUT")" = "supersede" ] && ok || no "a good supersede must not be downgraded"
[ "$(jq -r '.migration_required' <<<"$OUT")" = "true" ] && ok \
  || no "an admissible supersede must flag that a migration is owed"

# =====================================================================================
# 7. Reuse and extend do NOT require a measured value — the bar rises with the cost of
#    being wrong, and only supersede rewrites existing code.
# =====================================================================================
OUT="$(run --verdict reuse --mode attended --dimensions "carry:change-amplification")"
[ "$(jq -r '.admissible' <<<"$OUT")" = "true" ] && ok || no "reuse with a named dimension should be admissible"
[ "$(jq -r '.migration_required' <<<"$OUT")" = "false" ] && ok || no "reuse owes no migration"

# =====================================================================================
# 8. Unknown / malformed input is inadmissible, never silently coerced into a verdict.
# =====================================================================================
for bad in "--verdict banana --mode attended" "--verdict supersede --mode sideways" "--mode attended" ""; do
  # shellcheck disable=SC2086
  OUT="$(run $bad)"; RC=$?
  [ "$RC" -eq 0 ] && ok || no "malformed [$bad]: exit $RC, expected 0"
  jq -e . >/dev/null 2>&1 <<<"$OUT" && ok || no "malformed [$bad]: invalid JSON"
  [ "$(jq -r '.admissible' <<<"$OUT")" = "false" ] && ok || no "malformed [$bad] should be inadmissible"
done

# An unrecognised class fails the floor for EVERY verdict, not only supersede — otherwise
# "reuse, because vibes:it-feels-cleaner" is admissible and the cost model means nothing.
for v in reuse extend; do
  OUT="$(run --verdict "$v" --mode attended --dimensions "vibes:it-feels-cleaner")"
  [ "$(jq -r '.admissible' <<<"$OUT")" = "false" ] && ok \
    || no "$v citing only an unknown cost class should be inadmissible"
done
# ...and a recognised class alone IS enough for reuse/extend (the bar rises only for supersede).
OUT="$(run --verdict extend --mode attended --dimensions "agent:ambiguity-tax")"
[ "$(jq -r '.admissible' <<<"$OUT")" = "true" ] && ok || no "extend citing a known class should be admissible"

# An unrecognised dimension class must not quietly count as recurring.
OUT="$(run --verdict supersede --mode attended --dimensions "vibes:it-feels-cleaner" \
        --measured "vibes:it-feels-cleaner=9/10" --absorbs true)"
[ "$(jq -r '.admissible' <<<"$OUT")" = "false" ] && ok || no "an unknown cost class must not satisfy the floor"

# =====================================================================================
# 9. Determinism — the same inputs give byte-identical output. The gate re-asserts this
#    downstream, so drift here is drift everywhere.
# =====================================================================================
A="$(run --verdict supersede --mode attended "${GOOD_SUPERSEDE[@]}")"
B="$(run --verdict supersede --mode attended "${GOOD_SUPERSEDE[@]}")"
[ "$A" = "$B" ] && ok || no "output is not deterministic"

# =====================================================================================
# 10. Untrusted input: a dimension string carrying shell metacharacters is inert data.
# =====================================================================================
SENTINEL="$(mktemp -u)"
run --verdict reuse --mode attended --dimensions "carry:\$(touch $SENTINEL)" >/dev/null 2>&1
[ ! -f "$SENTINEL" ] && ok || no "SECURITY: a dimension string was shell-evaluated"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
