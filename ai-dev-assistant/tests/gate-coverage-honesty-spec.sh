#!/usr/bin/env bash
# gate-coverage-honesty-spec.sh — a gate that could not measure anything must not
# report the answer a clean tree would have given.
#
# THE DEFECT THIS DEFENDS AGAINST, and it has two layers.
#
# The surface one: on a machine without phpcpd, `dry-check.sh` is honest —
# `status:"skipped"`, `skip_reason:"tool_absent"`, `tools_absent:["phpcpd"]`, exit 0. phpcpd
# is the DRY gate's ONLY analyzer, so duplication was never measured. The wrapper mapped
# that to a plain `skipped` and `/review` step 8 rule 4 listed "a tool-unavailable soft
# skip" among the benign states that do not prevent a pass.
#
# The deeper one, found only after the first fix was written: the wrappers resolved their
# verdict by pattern-matching CONSOLE PROSE, through a table whose contract is "ordered;
# first match wins" and whose first row matches `Explicit "PASS" / "✓"`. `solid-check.sh`
# prints `[PASS] SOLID compliance acceptable` with phpstan AND phpmd both absent, because
# `tools_absent[]` deliberately does not move its own verdict. `security-check.sh` prints
# `✓ Security audit passed` with gitleaks, semgrep, trivy and psalm all absent. So a
# coverage row added at position 4 of that table NEVER EVALUATES — the first fix was
# decorative for two of the three gates it claimed to fix, and a spec that asserted the
# rows existed passed on a table where they were unreachable.
#
# The real fix is to stop reading prose. `dry-report.json`, `solid-report.json` and
# `security-report.json` are written on every path including the absent and unmeasured
# ones, and carry `status`, `measured`, `skip_reason`, `tools_absent[]`, `tools_failed[]`,
# `tools_unmeasured[]`. The claim "no stable JSON surface exists yet upstream", which sat
# in three of these files, was false when it was written.
#
# WHAT THIS SPEC THEREFORE ASSERTS is the DECISION and its ORDER, not the presence of
# words. Order is the load-bearing half: every assertion about a coverage rule is paired
# with one that the rule is reached before the findings rule that would otherwise shadow
# it. A mutation that MOVES a rule rather than deleting it is the mutation that beat the
# previous version of this file, and section 4 exists for it.
#
# Two design facts this spec pins, because both are traps a future edit will walk into:
#   - `analyzers_ran` is NOT the coverage test. `solid-check.sh` increments it for its
#     always-on `\Drupal::` grep, which needs no binary, so it is >= 1 with phpstan and
#     phpmd both gone; and `security-check.sh` emits it only in --changed mode.
#   - `tdd` writes no JSON report on any path and says so in its own source, so it is the
#     deliberate exception to report-first. Treating its absent report as unresolved would
#     fail-close every review on a gate behaving as designed.
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

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$TDD" "$SOLID" "$DRY" "$SEC" "$REVIEW" "$CONTRACT"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done

MARK='unresolved: true'

# Line number of the first line matching a fixed string, or empty. Line numbers are the
# whole point here: this file asserts what comes BEFORE what.
lineno() { grep -nF -m1 -- "$2" "$1" 2>/dev/null | cut -d: -f1; }
lineno_re() { grep -nE -m1 -- "$2" "$1" 2>/dev/null | cut -d: -f1; }

# The block of one wrapper's verdict resolution, from the heading to the next H2.
verdict_section() {
  awk '/^## Verdict interpretation/{on=1;next} on && /^## /{exit} on' "$1"
}

# =============================================== 1. the verdict comes from the report
# Three gates write a report on every path. Reading it is the difference between knowing
# what was measured and guessing from a line of terminal output.

for pair in "dry:$DRY:dry-report.json" "solid:$SOLID:solid-report.json" "security:$SEC:security-report.json"; do
  gate="${pair%%:*}"; rest="${pair#*:}"; file="${rest%%:*}"; report="${rest##*:}"

  if grep -qF "$report" "$file"; then
    pass_check "$gate wrapper names its report file $report"
  else
    fail_check "$gate wrapper never names $report — it is still guessing from console text"
  fi
  # Locating it. A hardcoded .reports/ finds nothing on a normal run, because that
  # stopped being the default in code-quality-tools v3.9.6 and is now opt-in.
  if grep -qF 'report-dir.sh --latest' "$file"; then
    pass_check "$gate wrapper locates the report with report-dir.sh --latest"
  else
    fail_check "$gate wrapper does not use report-dir.sh --latest to locate the report"
  fi
  if grep -qE '`\.reports/[a-z]+\.json`' "$file"; then
    fail_check "$gate wrapper still points at a hardcoded .reports/ path"
  else
    pass_check "$gate wrapper does not hardcode a .reports/ path"
  fi
  # The false claim that motivated prose-parsing in the first place. Keyed on the
  # ASSERTION, not the words: the file now quotes the old claim in order to correct it,
  # so a bare grep for the phrase matches the correction and fails a fixed file.
  if grep -qF 'v1 uses heuristics because no stable JSON surface exists yet upstream' "$file"; then
    fail_check "$gate wrapper still asserts no JSON surface exists — it does, and it is read above"
  else
    pass_check "$gate wrapper no longer asserts there is no JSON surface"
  fi
  # A gate that wrote no report cannot say what it measured. Read the PARAGRAPH: the
  # rule and its verdict wrap across lines, and a single-line grep misses the pairing.
  AL=$(lineno "$file" 'A. Was a report written at all?')
  NOREPORT=""
  [ -n "$AL" ] && NOREPORT=$(sed -n "${AL},$((AL+8))p" "$file")
  if [ -n "$NOREPORT" ] && printf '%s' "$NOREPORT" | grep -qF "$report" \
     && printf '%s' "$NOREPORT" | grep -qF "$MARK"; then
    pass_check "$gate wrapper makes a missing report unresolved"
  else
    fail_check "$gate wrapper does not make a missing report unresolved"
  fi
done

# ------------------------------------------------- 1a. the states read off the report
# `unmeasured` / `measured:false` is each gate's own word for "nothing was checked". It
# had no row in any wrapper and fell through "Ambiguous or empty output" to `warning`.
for pair in "dry:$DRY" "solid:$SOLID" "security:$SEC"; do
  gate="${pair%%:*}"; file="${pair#*:}"
  SECTION=$(verdict_section "$file")
  UNM=$(printf '%s' "$SECTION" | grep -F 'unmeasured' | grep -F "$MARK" || true)
  if [ -n "$UNM" ]; then
    pass_check "$gate wrapper maps the report's unmeasured state to unresolved"
  else
    fail_check "$gate wrapper has no unmeasured row — exit 4 falls through to a benign verdict"
  fi
  # A crashed analyzer produced no evidence either. Omitting tools_failed is how a
  # crashed gitleaks reads as a clean one.
  if printf '%s' "$SECTION" | grep -qF 'tools_failed'; then
    pass_check "$gate wrapper weighs tools_failed[] alongside tools_absent[]"
  else
    fail_check "$gate wrapper ignores tools_failed[] — a crashed analyzer reads as a clean one"
  fi
done

# DRY is single-analyzer: any of its could-not-check signals means zero measurement, and
# there is no partial state for it to report.
DRY_SECTION=$(verdict_section "$DRY")
if printf '%s' "$DRY_SECTION" | grep -F "$MARK" | grep -qi 'phpcpd'; then
  pass_check "DRY's could-not-check row names phpcpd, the analyzer that was absent"
else
  fail_check "DRY's unresolved row does not name phpcpd"
fi
if printf '%s' "$DRY_SECTION" | grep -qF 'skip_reason'; then
  pass_check "DRY keys on skip_reason, the field dry-check.sh actually writes"
else
  fail_check "DRY does not key on the report's skip_reason"
fi
if grep -qiE 'only.{0,20}analyzer|analyzer.{0,20}only' "$DRY"; then
  pass_check "DRY wrapper states phpcpd is its only analyzer"
else
  fail_check "DRY wrapper never says phpcpd is its only analyzer"
fi

# ------------------------------- 1b. multi-analyzer gates: derive coverage, don't count
# `analyzers_ran == 0` is UNREACHABLE for SOLID. Asserting its absence as the test is the
# only way to keep the next reader from reintroducing it.
for pair in "solid:$SOLID" "security:$SEC"; do
  gate="${pair%%:*}"; file="${pair#*:}"
  SECTION=$(verdict_section "$file")
  # "Gates on" means a TABLE ROW keyed to it. Prose warning AGAINST it is the fix, not
  # the defect, so this looks only at rows.
  if printf '%s' "$SECTION" | grep -E '^\|' | grep -qF 'analyzers_ran == 0'; then
    fail_check "$gate wrapper still has a verdict row keyed on analyzers_ran == 0, which is unreachable for SOLID and absent half the time for security"
  else
    pass_check "$gate wrapper has no verdict row keyed on analyzers_ran == 0"
  fi
  # The zero-coverage test is a set relation over the tool lists.
  ZERO=$(printf '%s' "$SECTION" | grep -E 'tools_absent.*tools_failed|Every .*analyzer|Every entry' | grep -F "$MARK" || true)
  if [ -n "$ZERO" ]; then
    pass_check "$gate wrapper derives zero coverage from the tool lists, not a counter"
  else
    fail_check "$gate wrapper has no tool-list-derived zero-coverage rule"
  fi
  PARTIAL=$(printf '%s' "$SECTION" | grep -E 'Some but not all' || true)
  if [ -n "$PARTIAL" ] && printf '%s' "$PARTIAL" | grep -q 'warning' \
     && printf '%s' "$PARTIAL" | grep -qiE 'never .*`?pass'; then
    pass_check "$gate wrapper maps partial coverage to warning and rules pass out"
  else
    fail_check "$gate wrapper has no partial-coverage row mapping to warning and excluding pass"
  fi
done

# The counter is a trap in a DIFFERENT way in each gate, so each file must name its own.
# For SOLID it is present and wrong: the always-on grep needs no binary, so it is >= 1
# with phpstan and phpmd both gone.
if grep -qiE 'analyzers_ran.{0,400}(counts checks|needs no binary|trap)|(counts checks|needs no binary).{0,400}analyzers_ran' "$SOLID"; then
  pass_check "solid wrapper warns that analyzers_ran counts checks, not coverage"
else
  fail_check "solid wrapper does not warn that its always-on grep inflates analyzers_ran"
fi
# For security it is simply absent on the standard path.
if grep -qE 'analyzers_ran.{0,200}`?--changed`? mode' "$SEC"; then
  pass_check "security wrapper says analyzers_ran exists only in --changed mode"
else
  fail_check "security wrapper does not say analyzers_ran is absent on the standard path"
fi

# ------------------------------------------------------- 1c. tdd is the stated exception
# It writes no report on any path. Applying the missing-report rule to it would mark every
# TDD run unresolved and fail-close every review.
if grep -qiE 'writes no JSON report|no JSON report at all' "$TDD"; then
  pass_check "tdd wrapper states it has no JSON report, and why that is not a defect"
else
  fail_check "tdd wrapper does not state why it is exempt from report-first"
fi
TDD_SECTION=$(verdict_section "$TDD")
if printf '%s' "$TDD_SECTION" | grep -E 'xit code `?4|CQT_EXIT_UNMEASURED' | grep -qF "$MARK"; then
  pass_check "tdd wrapper maps exit 4 (unmeasured) to unresolved"
else
  fail_check "tdd wrapper does not map exit 4 to unresolved — its only could-not-measure channel"
fi
if printf '%s' "$TDD_SECTION" | grep -F "$MARK" | grep -qiE 'no .*--files|--files.*absent|whole-tree'; then
  pass_check "tdd wrapper keeps the no---files path unresolved"
else
  fail_check "tdd wrapper lost the no---files unresolved path"
fi

# ================================================== 2. ORDER — the assertion that bites
# The tables are "ordered; first match wins". A coverage rule below a findings rule that
# matches a gate's cheerful console output is unreachable. This is what the previous
# version of this spec could not see, so every assertion here is a line-number comparison.

for pair in "dry:$DRY" "solid:$SOLID" "security:$SEC"; do
  gate="${pair%%:*}"; file="${pair#*:}"
  A=$(lineno "$file" 'A. Was a report written at all?')
  B=$(lineno "$file" 'B. Did it measure anything?')
  C=$(lineno "$file" 'C. It measured. Map the finding.')
  if [ -n "$A" ] && [ -n "$B" ] && [ -n "$C" ]; then
    if [ "$A" -lt "$B" ] && [ "$B" -lt "$C" ]; then
      pass_check "$gate resolves report-present, then coverage, then findings, in that order"
    else
      fail_check "$gate resolves its steps out of order (A=$A B=$B C=$C) — a coverage question answered after a findings question is answered too late"
    fi
  else
    fail_check "$gate has no ordered A/B/C resolution (A=$A B=$B C=$C)"
  fi
done

# tdd has the same shape with two steps.
TA=$(lineno "$TDD" 'A. Did anything get measured?')
TB=$(lineno "$TDD" 'B. It measured. Map the finding.')
if [ -n "$TA" ] && [ -n "$TB" ] && [ "$TA" -lt "$TB" ]; then
  pass_check "tdd asks what was measured before mapping the finding"
else
  fail_check "tdd does not ask the coverage question first (A=$TA B=$TB)"
fi

# THE SPECIFIC SHADOW. `Explicit "PASS"` is the row that swallowed every coverage row in
# the previous design, because two of these gates print PASS while measuring nothing. In
# every wrapper it must now come AFTER the coverage rules, without exception.
for pair in "tdd:$TDD" "dry:$DRY" "solid:$SOLID" "security:$SEC"; do
  gate="${pair%%:*}"; file="${pair#*:}"
  FIRST_UNRES=$(lineno "$file" "$MARK")
  EXPLICIT_PASS=$(lineno_re "$file" 'Explicit "PASS"')
  if [ -z "$FIRST_UNRES" ]; then
    fail_check "$gate has no unresolved rule at all"
  elif [ -z "$EXPLICIT_PASS" ]; then
    pass_check "$gate has no Explicit-PASS row to shadow its coverage rules"
  elif [ "$FIRST_UNRES" -lt "$EXPLICIT_PASS" ]; then
    pass_check "$gate's coverage rules are reached before the Explicit-PASS row"
  else
    fail_check "$gate's Explicit-PASS row (line $EXPLICIT_PASS) precedes its coverage rules (line $FIRST_UNRES) — the coverage rules can never evaluate"
  fi
done

# And the ordering must be DECLARED, not merely happen to hold.
for pair in "tdd:$TDD" "dry:$DRY" "solid:$SOLID" "security:$SEC"; do
  gate="${pair%%:*}"; file="${pair#*:}"
  if grep -qiE 'A is checked before B|Resolve in this order' "$file"; then
    pass_check "$gate declares its resolution order"
  else
    fail_check "$gate does not declare that its steps are ordered"
  fi
done

# ======================================================= 3. the contract documents it
if grep -qF "$MARK" "$CONTRACT" && grep -qF 'messages[]' "$CONTRACT"; then
  pass_check "contract states the literal marker and that it goes in messages[]"
else
  fail_check "contract does not state the literal '$MARK' inside messages[]"
fi
if grep -qiE 'review\.md.*(step 8|rule 2)|(step 8|rule 2).*review' "$CONTRACT"; then
  pass_check "contract names review.md step 8 rule 2 as the consumer"
else
  fail_check "contract documents unresolved without naming what consumes it"
fi
if grep -qiE 'fail[- ]closed' "$CONTRACT"; then
  pass_check "contract says the consumer is fail-closed"
else
  fail_check "contract does not say an unresolved gate fails closed"
fi
# Keyed on the could-not-check TABLE ROWS, not the whole file: `phpmd` also appears in a
# `details` example further down, so a whole-file grep stayed green when the row it meant
# to protect was deleted. That is the same defect class this spec exists for.
ROWS=$(grep -E '^\| `(dry|solid|security|tdd)` \|' "$CONTRACT" || true)
if [ -z "$ROWS" ]; then
  fail_check "contract has no per-gate could-not-check table"
else
  for gate in dry solid security tdd; do
    if printf '%s' "$ROWS" | grep -qE "^\| \`$gate\` \|"; then
      pass_check "contract's could-not-check table has a row for $gate"
    else
      fail_check "contract's could-not-check table has no row for $gate"
    fi
  done
  if printf '%s' "$ROWS" | grep -E '^\| `solid` \|' | grep -qF 'phpmd'; then
    pass_check "contract's solid row names phpmd among the binary analyzers"
  else
    fail_check "contract's solid row does not name phpmd"
  fi
  if printf '%s' "$ROWS" | grep -E '^\| `dry` \|' | grep -qF 'phpcpd'; then
    pass_check "contract's dry row names phpcpd"
  else
    fail_check "contract's dry row does not name phpcpd"
  fi
fi
# The two traps have to be written down where the contract is read.
if grep -qF 'Do not derive coverage from `analyzers_ran`' "$CONTRACT"; then
  pass_check "contract warns against deriving coverage from analyzers_ran"
else
  fail_check "contract does not warn against the analyzers_ran trap"
fi
if grep -qiE 'tools_failed.{0,120}(as heavily|counts as)|`tools_failed\[\]` counts' "$CONTRACT"; then
  pass_check "contract weighs tools_failed[] with tools_absent[]"
else
  fail_check "contract does not say tools_failed[] disqualifies like tools_absent[]"
fi
if grep -qiE 'tdd.{0,200}(deliberate exception|no JSON report)|(deliberate exception).{0,200}tdd' "$CONTRACT"; then
  pass_check "contract records tdd as the deliberate report-first exception"
else
  fail_check "contract does not record why tdd is exempt from report-first"
fi

# The skipped row that was the bug in prose.
SKIPPED_ROW=$(grep -E '^\| `skipped` \|' "$CONTRACT" || true)
if [ -z "$SKIPPED_ROW" ]; then
  fail_check "contract has no skipped row in its verdict-semantics table"
elif printf '%s' "$SKIPPED_ROW" | grep -qiE 'tool is unavailable|tool unavailable'; then
  fail_check "contract's skipped row still folds tool-unavailability into a benign skip"
else
  pass_check "contract's skipped row no longer folds tool-unavailability into a benign skip"
fi
for key in tools_absent tools_failed analyzers_ran; do
  if grep -qE "^- \`$key\`" "$CONTRACT"; then
    pass_check "contract documents $key as a stable --details key"
  else
    fail_check "contract does not document $key as a --details key"
  fi
done

# ================================================= 4. the consumer half of /review
# Every producer above is decorative without this.
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

# ------------------------------ 4a. `warning` is a legal verdict and must have a rule
# The partial-coverage verdict the wrappers now emit had nowhere to land: step 8's rules
# covered fail, unresolved, bypass and all-pass, and `warning` fell off the end of the
# list. Falling off the end is not a rule, and it is how a partially-covered gate reached
# a green overall_verdict.
WARN_RULE=$(grep -nE '^ +[0-9]+\. `[a-z]+` if any hard-block gate has `verdict: "warning"`' "$REVIEW" || true)
if [ -z "$WARN_RULE" ]; then
  fail_check "review.md step 8 has no rule for a hard-block warning — aggregation still falls off the end of the list"
else
  WN="${WARN_RULE%%:*}"
  WTEXT="${WARN_RULE#*:}"
  RESOLVES=$(printf '%s' "$WTEXT" | sed -n 's/^ *[0-9]*\. `\([a-z]*\)` if any hard-block.*/\1/p')
  case "$RESOLVES" in
    pass) fail_check "review.md resolves a hard-block warning to pass — a partially-covered gate goes green" ;;
    fail|bypassed) pass_check "review.md resolves a hard-block warning to $RESOLVES, not pass" ;;
    *) fail_check "review.md's warning rule resolves to '$RESOLVES', not a legal overall_verdict" ;;
  esac
  if printf '%s' "$WTEXT" | grep -qiE 'why|because|only \{|left'; then
    pass_check "review.md's warning rule says why it resolves the way it does"
  else
    fail_check "review.md's warning rule states a verdict with no reason"
  fi
  # It has to be RANKED. An unranked rule in an ordered resolution is the same defect.
  PASSRULE=$(grep -nE '^ +[0-9]+\. `pass` if \*\*all\*\* hard-block gates' "$REVIEW" | cut -d: -f1 || true)
  if [ -n "$PASSRULE" ] && [ "$WN" -lt "$PASSRULE" ]; then
    pass_check "review.md's warning rule is ranked before the pass rule"
  else
    fail_check "review.md's warning rule is not ranked before the pass rule (warning=$WN pass=$PASSRULE)"
  fi
fi

# ------------------------------------------ 4b. the pass rule no longer authorizes it
PASS_RULE=$(grep -E '^ +[0-9]+\. `pass` if \*\*all\*\* hard-block gates' "$REVIEW" || true)
if [ -z "$PASS_RULE" ]; then
  fail_check "review.md step 8 has no pass rule"
else
  # Read the parenthesised benign list only: the rule legitimately mentions absent
  # analyzers now, in the clause saying they are NOT benign.
  BENIGN=$(printf '%s' "$PASS_RULE" | sed -n 's/.*Benign non-blocking states (\([^)]*\)).*/\1/p')
  if [ -z "$BENIGN" ]; then
    fail_check "review.md's pass rule has no parenthesised benign-state list to check"
  elif printf '%s' "$BENIGN" | grep -qiE 'tool|analyz'; then
    fail_check "review.md's pass rule still names a tool-availability state as benign: ${BENIGN}"
  else
    pass_check "review.md's pass rule names no tool-availability state as benign"
  fi
  if printf '%s' "$PASS_RULE" | grep -qF 'warning'; then
    pass_check "review.md's pass rule excludes warning explicitly"
  else
    fail_check "review.md's pass rule does not exclude warning"
  fi
  if printf '%s' "$PASS_RULE" | grep -qF 'unresolved'; then
    pass_check "review.md's pass rule routes the absent-analyzer case to unresolved"
  else
    fail_check "review.md's pass rule does not route the absent-analyzer case anywhere"
  fi
fi

if [ "$FAIL" = "0" ]; then
  printf '\ngate-coverage-honesty-spec: all checks passed\n'
else
  printf '\ngate-coverage-honesty-spec: FAILURES\n' >&2
fi
exit "$FAIL"
