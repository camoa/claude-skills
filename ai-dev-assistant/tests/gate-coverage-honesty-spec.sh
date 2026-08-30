#!/usr/bin/env bash
# gate-coverage-honesty-spec.sh — the WIRING half: that the mapping is delegated to the
# script that owns it, and that /review still consumes what that script emits.
#
# The mapping itself is asserted in gate-verdict-resolve-spec.sh, by running it against
# fixture reports and by checking every field path against the gate script that emits it.
# That split is the point of this round. Earlier versions of THIS file carried 89
# assertions about the mapping, and every one of them compared AIDA prose to AIDA prose:
# not one opened `security-check.sh`. Four field paths that do not exist survived, including
# a `.status` on security-report.json that made a project with a CRITICAL finding go green.
# Prose assertions could not have caught that, however many of them there were.
#
# So what is left here is what a script cannot check about itself:
#
#   1. the four wrappers DELEGATE — they call the resolver and no longer decide anything,
#      so there is no second copy of the mapping to drift;
#   2. no wrapper has a decision table left, so the "ordered; first match wins" trap that
#      made a coverage row unreachable behind `Explicit "PASS"` cannot come back;
#   3. `/review` still reads both markers out of `messages[]` — delete either consumer and
#      every producer becomes decorative while all of their own assertions stay green;
#   4. rule 4 keys on the partial-coverage MARKER and never on `verdict: "warning"`, which
#      is a fully measured run with a mildly bad number and has never blocked.
#
# Exit 0 on all-pass; 1 on any fail.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TDD="${PLUGIN_ROOT}/commands/validate-tdd.md"
SOLID="${PLUGIN_ROOT}/commands/validate-solid.md"
DRY="${PLUGIN_ROOT}/commands/validate-dry.md"
SEC="${PLUGIN_ROOT}/commands/validate-security.md"
REVIEW="${PLUGIN_ROOT}/commands/review.md"
CONTRACT="${PLUGIN_ROOT}/references/validation-gate-result.md"
RESOLVER="${PLUGIN_ROOT}/scripts/gate-verdict-resolve.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$TDD" "$SOLID" "$DRY" "$SEC" "$REVIEW" "$CONTRACT" "$RESOLVER"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done

MARK='unresolved: true'
PMARK='coverage_partial: true'

# ==================================================== 1. the wrappers delegate, not decide
for pair in "tdd:$TDD" "dry:$DRY" "solid:$SOLID" "security:$SEC"; do
  gate="${pair%%:*}"; file="${pair#*:}"

  if grep -qF 'gate-verdict-resolve.sh' "$file"; then
    pass_check "$gate wrapper calls gate-verdict-resolve.sh"
  else
    fail_check "$gate wrapper does not call the resolver — the mapping has been re-inlined as prose"
  fi
  # It must pass its OWN gate name, or two wrappers resolve as one.
  if grep -qE "gate-verdict-resolve\.sh\" ?$gate|gate-verdict-resolve\.sh $gate" "$file"; then
    pass_check "$gate wrapper passes its own gate name to the resolver"
  else
    fail_check "$gate wrapper never passes '$gate' to the resolver"
  fi
  # NO decision table. The tables were "ordered; first match wins" and their first row
  # matched `Explicit "PASS"`, which two of these gates print while measuring nothing — so
  # a coverage row below it was unreachable. The fix is not a better ordering assertion,
  # it is having no table: the safest table is the one that decides nothing.
  if grep -qE '^\| *(Explicit "PASS"|Warnings-but-not-fatal|Skip indicators|Ambiguous or empty)' "$file"; then
    fail_check "$gate wrapper still carries a console-text decision table — the first-match-wins trap is back"
  else
    pass_check "$gate wrapper carries no console-text decision table"
  fi
  if grep -qE '`\.reports/[a-z]+\.json`' "$file"; then
    fail_check "$gate wrapper points at a hardcoded .reports/ path"
  else
    pass_check "$gate wrapper does not hardcode a .reports/ path"
  fi
  if grep -qF 'v1 uses heuristics because no stable JSON surface exists yet upstream' "$file"; then
    fail_check "$gate wrapper still asserts there is no JSON surface — there is, and the resolver reads it"
  else
    pass_check "$gate wrapper no longer asserts there is no JSON surface"
  fi
  # The markers travel in messages[]. A wrapper that summarises or trims them drops the
  # only thing /review reads.
  if grep -qiE 'do not edit, reorder or drop|pass .*messages.*through unedited|pass those messages through unchanged' "$file"; then
    pass_check "$gate wrapper is told to pass messages[] through without editing"
  else
    fail_check "$gate wrapper does not forbid editing messages[] — a trimmed marker is a green review"
  fi
done

# The three report-writing gates locate the report the one supported way; tdd has none.
for pair in "dry:$DRY" "solid:$SOLID" "security:$SEC"; do
  gate="${pair%%:*}"; file="${pair#*:}"
  if grep -qF 'report-dir.sh --latest' "$file"; then
    pass_check "$gate wrapper locates its report with report-dir.sh --latest"
  else
    fail_check "$gate wrapper does not use report-dir.sh --latest"
  fi
  if grep -qF -- '--not-before' "$file"; then
    pass_check "$gate wrapper passes a freshness baseline, so a stale report cannot read as this run's"
  else
    fail_check "$gate wrapper passes no --not-before — a previous run's green can be read as this run's"
  fi
done
if grep -qiE 'writes no JSON report' "$TDD"; then
  pass_check "tdd wrapper states it has no report, and why that is not a defect"
else
  fail_check "tdd wrapper does not state why it is exempt from report-first"
fi

# ============================================== 2. /review still consumes both markers
RULE2=$(grep -nE '^ +2\. `fail` if any hard-block gate is' "$REVIEW" | cut -d: -f1 || true)
if [ -z "$RULE2" ]; then
  fail_check "review.md step 8 has no rule 2 — the unresolved consumer is gone"
else
  R2=$(sed -n "${RULE2}p" "$REVIEW")
  # The load-bearing half is the PATH. Rule 2 has always described writing the marker into
  # its own gates_run[] entry for a parse error, so a check for the marker plus messages[]
  # stays green on a rule 2 that no longer opens a wrapper's file at all.
  if printf '%s' "$R2" | grep -qF 'validations/latest/' \
     && printf '%s' "$R2" | grep -qF "$MARK" && printf '%s' "$R2" | grep -qF 'messages[]'; then
    pass_check "review.md rule 2 reads '$MARK' out of a wrapper envelope at validations/latest/"
  else
    fail_check "review.md rule 2 no longer reads the marker out of a wrapper's envelope — producers emit into nothing"
  fi
  if printf '%s' "$R2" | grep -qiE 'propagate'; then
    pass_check "review.md rule 2 propagates a wrapper's unresolved into gates_run[]"
  else
    fail_check "review.md rule 2 does not propagate a wrapper's unresolved into gates_run[]"
  fi
  if printf '%s' "$R2" | grep -qiE 'fail-closed|fail closed'; then
    pass_check "review.md rule 2 keeps its fail-closed posture"
  else
    fail_check "review.md rule 2 dropped its fail-closed wording"
  fi
fi

# DIRECTION 2, checked FIRST and unconditionally: no step-8 rule may resolve on the bare
# value `warning`. Kept outside the marker rule's branch on purpose — the mutation this
# defends against is the one that removes that branch, and an assertion nested inside it
# cannot fail in the one case it names.
if grep -qE '^ +[0-9]+\. `[a-z]+` if any hard-block gate has `verdict: "warning"`' "$REVIEW"; then
  fail_check "DIRECTION 2 FAILED: a step-8 rule keys on the bare verdict: \"warning\" — an ordinary fully measured warning (6% duplication, 11 SOLID warnings) now fails the review"
else
  pass_check "DIRECTION 2: no step-8 rule keys on the bare verdict: \"warning\""
fi

COV_RULE=$(grep -nE '^ +[0-9]+\. `[a-z]+` if any hard-block gate carries the literal `coverage_partial: true`' "$REVIEW" || true)
if [ -z "$COV_RULE" ]; then
  fail_check "review.md step 8 has no rule keyed on '$PMARK' — a partially covered gate reaches green"
else
  WN="${COV_RULE%%:*}"; WTEXT="${COV_RULE#*:}"
  RESOLVES=$(printf '%s' "$WTEXT" | sed -n 's/^ *[0-9]*\. `\([a-z]*\)` if any hard-block.*/\1/p')
  case "$RESOLVES" in
    pass) fail_check "review.md resolves a partial-coverage gate to pass — it goes green having measured half its ground" ;;
    fail|bypassed) pass_check "DIRECTION 1: a partial-coverage gate resolves to $RESOLVES, not pass" ;;
    *) fail_check "review.md's coverage rule resolves to '$RESOLVES', not a legal overall_verdict" ;;
  esac
  if printf '%s' "$WTEXT" | grep -qiE 'never on `?verdict: "warning"|Keyed on the marker'; then
    pass_check "review.md's rule 4 says explicitly that it keys on the marker, not the verdict"
  else
    fail_check "review.md's rule 4 does not state that it keys on the marker rather than the verdict"
  fi
  PASSRULE=$(grep -nE '^ +[0-9]+\. `pass` if (every|\*\*all\*\*) hard-block gate' "$REVIEW" | cut -d: -f1 || true)
  if [ -n "$PASSRULE" ] && [ "$WN" -lt "$PASSRULE" ]; then
    pass_check "review.md's coverage rule is ranked before the pass rule"
  else
    fail_check "review.md's coverage rule is not ranked before the pass rule (coverage=$WN pass=$PASSRULE)"
  fi
fi

PASS_RULE=$(grep -E '^ +[0-9]+\. `pass` if (every|\*\*all\*\*) hard-block gate' "$REVIEW" || true)
if [ -z "$PASS_RULE" ]; then
  fail_check "review.md step 8 has no pass rule"
else
  BENIGN=$(printf '%s' "$PASS_RULE" | sed -n 's/.*[Bb]enign non-blocking state[s]* (\([^)]*\)).*/\1/p')
  if [ -z "$BENIGN" ]; then
    fail_check "review.md's pass rule has no parenthesised benign-state list to check"
  elif printf '%s' "$BENIGN" | grep -qiE 'tool|analyz'; then
    fail_check "review.md's pass rule still names a tool-availability state as benign: ${BENIGN}"
  else
    pass_check "review.md's pass rule names no tool-availability state as benign"
  fi
  if printf '%s' "$PASS_RULE" | grep -qiE 'ordinary `?warning`?.{0,80}(fully measured|measured gate)|fully measured.{0,80}`?warning`?'; then
    pass_check "DIRECTION 2: review.md's pass rule names an ordinary measured warning as benign"
  else
    fail_check "DIRECTION 2 FAILED: review.md's pass rule does not say an ordinary measured warning stays non-blocking"
  fi
  if printf '%s' "$PASS_RULE" | grep -qF "$PMARK"; then
    pass_check "review.md's pass rule excludes the partial-coverage marker from benign"
  else
    fail_check "review.md's pass rule does not exclude '$PMARK' from its benign states"
  fi
fi

# ==================================================== 3. the contract records the mechanism
if grep -qF "$MARK" "$CONTRACT" && grep -qF 'messages[]' "$CONTRACT"; then
  pass_check "contract states the unresolved marker and that it goes in messages[]"
else
  fail_check "contract does not state the literal '$MARK' inside messages[]"
fi
if grep -qE '^### `coverage_partial`' "$CONTRACT" && grep -qF "$PMARK" "$CONTRACT"; then
  pass_check "contract has a section documenting the '$PMARK' marker"
else
  fail_check "contract has no coverage_partial section — the mechanism rule 4 depends on is undocumented"
fi
if grep -qiE 'nothing.{0,40}measured.{0,120}part|`unresolved` means \*\*nothing\*\*' "$CONTRACT"; then
  pass_check "contract distinguishes unresolved (nothing measured) from coverage_partial (part measured)"
else
  fail_check "contract does not distinguish the two markers"
fi
if grep -qiE 'NEVER on `?verdict: "warning"|never on `verdict' "$CONTRACT"; then
  pass_check "contract records that rule 4 keys on the marker, not on verdict: warning"
else
  fail_check "contract does not record why rule 4 avoids keying on verdict: warning"
fi
if grep -qF 'gate-verdict-resolve.sh' "$CONTRACT"; then
  pass_check "contract names the resolver as the thing that produces both markers"
else
  fail_check "contract does not name gate-verdict-resolve.sh — a reader cannot find what emits the markers"
fi
if grep -qiE 'stale|freshness' "$CONTRACT"; then
  pass_check "contract addresses report freshness rather than leaving it undecided"
else
  fail_check "contract says nothing about a stale report being read as this run's result"
fi

SKIPPED_ROW=$(grep -E '^\| `skipped` \|' "$CONTRACT" || true)
if [ -z "$SKIPPED_ROW" ]; then
  fail_check "contract has no skipped row in its verdict-semantics table"
elif printf '%s' "$SKIPPED_ROW" | grep -qiE 'tool is unavailable|tool unavailable'; then
  fail_check "contract's skipped row still folds tool-unavailability into a benign skip"
else
  pass_check "contract's skipped row no longer folds tool-unavailability into a benign skip"
fi

if [ "$FAIL" = "0" ]; then
  printf '\ngate-coverage-honesty-spec: all checks passed\n'
else
  printf '\ngate-coverage-honesty-spec: FAILURES\n' >&2
fi
exit "$FAIL"
