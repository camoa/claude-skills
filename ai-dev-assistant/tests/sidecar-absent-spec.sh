#!/usr/bin/env bash
# An absent agent sidecar must reach every consumer as no_return, and must never be the value a
# silent default would produce.
#
# WHAT THIS CAN AND CANNOT DO, stated first because the gap matters.
#
# The consumers are command PROSE that an orchestrator follows, not code this spec can execute. So
# this cannot delete a file and observe a verdict. What it checks is that each consumer's
# instruction names the absent case and names a consequence that is not the passing one, and that
# the consequences DIFFER between consumers, because a single shared consequence would be evidence
# somebody flattened a distinction the framework keeps on purpose.
#
# HOW IT USED TO PASS ON NOTHING. Every check was a bare `grep` over the WHOLE file. `no_return`
# appears in commands/research.md six times, only three of them at an agent-dispatch site. Measured:
# wiping `no_return` and `insufficient_info` from all three dispatch sites — the pre-analysis
# sidecar, the post-research epic check and the prior-art record — left this spec reporting 20
# passing assertions and exit 0, because three unrelated mentions elsewhere in the file answered
# every search. Against a full pre-change export of the same file, three assertions passed on the
# unfixed tree, including one satisfied by `keep_flat / insufficient_info -> silent, proceed`, which
# is the exact default the assertion claims to refuse.
#
# Each check is now ANCHORED to the sidecar filename it is about and looks for its token within two
# lines of that filename. A missing anchor fails outright: a rule whose subject left the file has
# not passed, it has stopped being checkable. Two lines is the measured slack — every dispatch site
# in the tree carries its consequence on the anchor line itself except the surface selector, which
# wraps across three.
#
# One half IS executable and is checked by running it: the normalizer that guards the analysis-agent
# path returns a distinct code for an empty input rather than exit 0 and silence.
#
# THE DEFECT THIS EXISTS FOR. Three consumers folded an absent or empty agent result into a passing
# one. An empty surface selection became `verdict: skipped` and stopped. Empty guide matches became
# zero coverage gaps and a clean pass. An absent tier-3 prior-art result resolved as "no native
# pattern found" and a build proceeded on an unchallenged mechanism. In each case an agent that
# errored and an agent that honestly found nothing produced the identical green.
#
# What it still cannot check is that the LIST of consumers is right. A consumer added tomorrow that
# branches on an agent return and appears here nowhere is invisible, the same limit
# tests/sidecar-contract-spec.sh states about its own set.
#
# Exit: 0 = every consumer names the absent case with a non-passing consequence; 1 = a gap.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."
fail=0
checked=0
WINDOW=2

near() { # near <file> <anchor-ERE> <token-ERE> <what it proves>
  local rel="$1" anchor="$2" token="$3" what="$4"
  local f="$ROOT/$rel"
  if [ ! -f "$f" ]; then
    echo "FAIL: consumer not found: $rel"
    fail=1
    return
  fi
  checked=$((checked + 1))
  local anchors n lo hi
  anchors=$(grep -nE -- "$anchor" "$f" | cut -d: -f1)
  if [ -z "$anchors" ]; then
    echo "FAIL: $rel no longer names the sidecar this rule is about, so the rule checks nothing"
    echo "      (anchor: $anchor)"
    fail=1
    return
  fi
  for n in $anchors; do
    lo=$((n - WINDOW)); [ "$lo" -lt 1 ] && lo=1
    hi=$((n + WINDOW))
    if sed -n "${lo},${hi}p" "$f" | grep -qE -- "$token"; then
      echo "PASS: $rel:$n — $what"
      return
    fi
  done
  echo "FAIL: $rel names the sidecar but does not $what within $WINDOW lines of it"
  echo "      (anchor: $anchor | looked for: $token | anchor lines: $(echo $anchors | tr '\n' ' '))"
  fail=1
}

# --- every dispatch site names the absent case, beside the sidecar it is about ---
near commands/research.md      '_analysis-description\.json'          'no_return'         'name the absent pre-analysis sidecar'
near commands/research.md      '_analysis-folder\.json'               'no_return'         'name the absent post-research sidecar'
near commands/research.md      '_prior-art-<aspect>\.json'            'no_return'         'name the absent prior-art record'
near commands/design.md        '_analysis-folder\.json'               'no_return'         'name the absent post-design sidecar'
near commands/implement.md     '_analysis-folder\.json'               'no_return'         'name the absent post-plan sidecar'
near commands/complete.md      '_analysis-play_candidates\.json'      'no_return'         'name the absent candidate-play sidecar'
near commands/propose-epics.md '_analysis-folder\.json'               'no_return'         'name the absent per-candidate sidecar'
near commands/validate-guides.md '_guides-match-validation\.json'     'no_return'         'name the absent match set'
near commands/validate-visual-regression.md '_test-selection-visual_regression\.json' 'no_return' 'name the absent selection'

# --- and names a consequence that is NOT the passing one, beside the same sidecar ---
# These differ deliberately. A missing surface selection is not a missing epic verdict.
near commands/research.md      '_analysis-description\.json'          'insufficient_info' 'refuse keep_flat on an absent pre-analysis verdict'
near commands/research.md      '_analysis-folder\.json'               'insufficient_info' 'refuse keep_flat on an absent post-research verdict'
near commands/design.md        '_analysis-folder\.json'               'insufficient_info' 'refuse keep_flat on an absent post-design verdict'
near commands/implement.md     '_analysis-folder\.json'               'insufficient_info' 'refuse keep_flat on an absent post-plan verdict'
near commands/propose-epics.md '_analysis-folder\.json'               'insufficient_info' 'refuse keep_flat on an absent per-candidate verdict'
near commands/validate-guides.md 'domain_coverage_gaps'               'unresolved'        'refuse zero coverage gaps on an absent match set'
near commands/validate-visual-regression.md '_test-selection-visual_regression\.json' 'unresolved' 'refuse a clean skip on an absent selection'

# --- the consequences must not all be the same string ---
# A single shared consequence would mean somebody flattened distinctions the framework keeps.
DISTINCT=$(grep -ho -E 'unresolved|insufficient_info|not_searched' \
  "$ROOT/commands/validate-visual-regression.md" "$ROOT/commands/validate-guides.md" \
  "$ROOT/commands/implement.md" "$ROOT/commands/propose-epics.md" 2>/dev/null | sort -u | wc -l)
checked=$((checked + 1))
if [ "$DISTINCT" -ge 2 ]; then
  echo "PASS: consumers record $DISTINCT distinct consequences, not one flattened value"
else
  echo "FAIL: every consumer records the same consequence, which flattens events the framework separates"
  fail=1
fi

# --- the executable half: an empty input is a distinct, non-zero outcome ---
NORM="$ROOT/scripts/analysis-agent-normalize.sh"
if [ -x "$NORM" ] || [ -f "$NORM" ]; then
  # This asserted 2 until the values were split. 2 now means a payload arrived and is not an
  # answer; an empty input means nothing arrived, which is a different fact and gets 3.
  checked=$((checked + 1))
  printf '' | bash "$NORM" - >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 3 ]; then
    echo "PASS: an empty payload exits 3, the nothing-arrived value"
  else
    echo "FAIL: an empty payload exits $rc; before v5.37.0 it exited 0 with empty output, which is"
    echo "      indistinguishable from a run that legitimately filtered everything out, and 2 now"
    echo "      means something arrived that cannot be used"
    fail=1
  fi
  checked=$((checked + 1))
  printf '{"decision":"keep_flat","notes":[]}' | bash "$NORM" - >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "PASS: a payload missing required keys exits 2 rather than passing through unchecked"
  else
    echo "FAIL: a payload missing code_read and confidence exits $rc; the clamp cannot fire without"
    echo "      code_read, so this would read as an answer that had already been checked"
    fail=1
  fi
  # A verdict is an OBJECT. null, a list, a string, a number and a boolean are all valid JSON and
  # none of them is an answer. The first version of the empty-input check missed this: `null`
  # reached the clamp, `.code_read` on null is null, null is not false, so the clamp did not fire
  # and `null` came out on stdout with exit 0 — the silent default this release exists to remove,
  # rebuilt inside the fix for it. A string or number made the key check throw, and the fallback
  # read the throw as "nothing missing", which is the same pattern removed from
  # build-critique-assert.sh the day before.
  for bad in 'null' '[]' '"a string"' '42' 'true'; do
    checked=$((checked + 1))
    printf '%s' "$bad" | bash "$NORM" - >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "PASS: a payload of $bad is rejected as not an object"
    else
      echo "FAIL: a payload of $bad exits $rc; valid JSON that is not an object is not an answer"
      fail=1
    fi
  done

  # A file path that is not there is the absent sidecar itself, the case every file-path caller
  # hits. It has its own value, so a caller can route "the agent wrote nothing" away from "the
  # agent wrote something unusable" instead of seeing one number for both.
  checked=$((checked + 1))
  bash "$NORM" "$ROOT/does-not-exist-$$.json" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 3 ]; then
    echo "PASS: an absent sidecar path exits 3, its own value, not the one malformed input uses"
    checked=$((checked + 1))
    printf 'not json' > "$ROOT/.absent-spec-probe-$$.json"
    bash "$NORM" "$ROOT/.absent-spec-probe-$$.json" >/dev/null 2>&1; rc2=$?
    rm -f "$ROOT/.absent-spec-probe-$$.json"
    if [ "$rc2" -eq 1 ]; then
      echo "PASS: a file that exists and holds junk still exits 1, so absence did not swallow it"
    else
      echo "FAIL: a file holding junk exits $rc2; the absent value has absorbed malformed input,"
      echo "      and a caller can no longer tell an agent that wrote nothing from one that wrote junk"
      fail=1
    fi
  else
    echo "FAIL: an absent sidecar path exits $rc, not 3; nothing-arrived has no value of its own"
    fail=1
    checked=$((checked + 1))
  fi

  checked=$((checked + 1))
  printf '{"decision":"keep_flat","confidence":"high","code_read":true}' | bash "$NORM" - >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "PASS: a well-formed payload still exits 0"
  else
    echo "FAIL: a well-formed payload exits $rc; the new checks reject a good input"
    fail=1
  fi
else
  echo "FAIL: normalizer not found at scripts/analysis-agent-normalize.sh"
  fail=1
fi

# An exact count, not a floor: a cell that stops running is a cell that stopped checking, and a
# floor cannot tell that from a cell that was deliberately removed.
if [ "$checked" -ne 27 ]; then
  echo "FAIL: $checked assertions ran; this spec expects 27"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "OK   absent sidecar: $checked assertions across 7 consumers and the normalizer"
exit "$fail"
