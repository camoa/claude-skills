#!/usr/bin/env bash
# gate-coverage-honesty-spec.sh — a gate that could not measure anything must not
# report the answer a clean tree would have given.
#
# THE DEFECT THIS DEFENDS AGAINST. On a machine without phpcpd, `dry-check.sh` is
# honest: `status:"skipped"`, `skip_reason:"tool_absent"`, `tools_absent:["phpcpd"]`,
# exit 0. phpcpd is the DRY gate's ONLY analyzer, so duplication was never measured.
# The wrapper mapped that to a plain `skipped`, `/review` step 8 rule 4 listed
# "a tool-unavailable soft skip" among the benign states that do not prevent a pass,
# and the review went green reporting a duplication verdict nothing had produced.
# phpmd and the SOLID complexity layer had the same hole with a partial-coverage
# twist: phpstan and an always-on `\Drupal::` grep still ran, so SOME of that gate
# was real and some of it was silence.
#
# The fix propagates a mechanism that already worked in exactly one place.
# `validate-tdd.md` has emitted the literal `unresolved: true` inside `messages[]`
# since the no-test-executed path was found, and `review.md` step 8 rule 2 reads it
# back out and fails closed. Nothing else knew about it: `unresolved` appeared zero
# times in the emitter script, zero times in the envelope contract that calls itself
# the shared contract, and zero times in the other three wrappers.
#
# That is what makes this spec worth having. The convention is a string in prose
# with no schema support — `validation-envelope-write.sh` neither produces nor
# validates it — so nothing but these assertions notices when a producer stops
# emitting it or the one consumer stops reading it. The consumer half is asserted
# on purpose: delete review.md rule 2 and every producer below becomes decorative
# while every one of their own assertions still passes.
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

# The marker is a literal string in message text, not a JSON field, so it is matched
# literally. A wrapper that writes `unresolved:true` or `"unresolved": true` emits an
# envelope review.md's rule-2 wording does not recognise.
MARK='unresolved: true'

# Read one command's "## Verdict interpretation" section. Scoping matters: the marker
# appearing anywhere in a 140-line command file proves nothing about the table that
# decides the verdict.
verdict_section() {
  awk '/^## Verdict interpretation/{on=1;next} on && /^## /{exit} on' "$1"
}

# ====================================================================== 1. producers
# Each wrapper instructs emitting the marker on ITS OWN could-not-check path. The
# four paths are different facts and each is named, so a wrapper cannot satisfy this
# by carrying the phrase with no case attached to it.

for pair in "tdd:$TDD" "solid:$SOLID" "dry:$DRY" "security:$SEC"; do
  gate="${pair%%:*}"; file="${pair#*:}"
  SECTION=$(verdict_section "$file")
  if [ -z "$SECTION" ]; then
    fail_check "$gate wrapper has no ## Verdict interpretation section to check"
    continue
  fi
  if printf '%s' "$SECTION" | grep -qF "$MARK"; then
    pass_check "$gate wrapper's verdict table emits '$MARK' for a could-not-check result"
  else
    fail_check "$gate wrapper's verdict table never emits '$MARK' — a gate that checked nothing reports as one that found nothing"
  fi
  # The marker has to sit on a row that yields `skipped`, not on one that yields pass
  # or fail: rule 2 only fires on a gate whose own verdict stayed skipped.
  if printf '%s' "$SECTION" | grep -F "$MARK" | grep -q 'skipped'; then
    pass_check "$gate wrapper pairs the marker with verdict skipped"
  else
    fail_check "$gate wrapper emits the marker on a row that is not a skipped verdict"
  fi
done

# ------------------------------------------------- 1a. DRY: its ONLY analyzer absent
# DRY is single-analyzer, so it has no partial state and its row must say which tool.
# A generic "a tool was missing" row would be wrong here in a way it is not wrong for
# solid or security.
DRY_SECTION=$(verdict_section "$DRY")
if printf '%s' "$DRY_SECTION" | grep -F "$MARK" | grep -qi 'phpcpd'; then
  pass_check "DRY's could-not-check row names phpcpd, the analyzer that was absent"
else
  fail_check "DRY's unresolved row does not name phpcpd — the reader cannot tell what went unmeasured"
fi
if printf '%s' "$DRY_SECTION" | grep -qiE 'skip_reason.*tool_absent|tool_absent.*skip_reason'; then
  pass_check "DRY's row keys on the report's own skip_reason:\"tool_absent\""
else
  fail_check "DRY's row does not key on skip_reason:\"tool_absent\", the signal dry-check.sh actually writes"
fi
# The rationale — not decoration. Single-analyzer is WHY this gate has no partial row.
if grep -qiE 'only.{0,20}analyzer|analyzer.{0,20}only' "$DRY"; then
  pass_check "DRY wrapper states phpcpd is its only analyzer"
else
  fail_check "DRY wrapper never says phpcpd is its only analyzer — the reason absence means zero measurement"
fi

# --------------------------------- 1b. solid + security: partial coverage is warning
# Multi-analyzer gates have a state DRY cannot have: some analyzers ran, some did not.
# That is a real measurement and must not be unresolved — but it must not be `pass`
# either, or a machine missing phpmd reports the same verdict as a machine with it.
for pair in "solid:$SOLID" "security:$SEC"; do
  gate="${pair%%:*}"; file="${pair#*:}"
  SECTION=$(verdict_section "$file")
  if printf '%s' "$SECTION" | grep -qE 'analyzers_ran == 0'; then
    pass_check "$gate wrapper's zero-coverage row keys on analyzers_ran == 0"
  else
    fail_check "$gate wrapper has no analyzers_ran == 0 row — it cannot tell 'nothing ran' from 'nothing found'"
  fi
  PARTIAL=$(printf '%s' "$SECTION" | grep -E 'analyzers_ran ?>=? ?1|>= 1' || true)
  if [ -n "$PARTIAL" ] && printf '%s' "$PARTIAL" | grep -q 'warning'; then
    pass_check "$gate wrapper maps partial coverage to warning"
  else
    fail_check "$gate wrapper has no partial-coverage row mapping to warning"
  fi
  if [ -n "$PARTIAL" ] && printf '%s' "$PARTIAL" | grep -qiE 'never .*pass'; then
    pass_check "$gate wrapper's partial row rules pass out explicitly"
  else
    fail_check "$gate wrapper's partial-coverage row does not rule pass out"
  fi
  if printf '%s' "$SECTION" | grep -qF 'tools_absent'; then
    pass_check "$gate wrapper names tools_absent[] as the source of what went unchecked"
  else
    fail_check "$gate wrapper never names tools_absent[]"
  fi
done

# security's coverage number is not always there. `security-check.sh` emits
# analyzers_ran ONLY in --changed mode, which is /review's default path; on the
# standard path a consumer has to derive it. A wrapper that reads the field
# unconditionally gets null on half its runs.
if grep -qF 'analyzers_ran' "$SEC" && grep -q -- '--changed' "$SEC" \
   && grep -qF 'meta.tools' "$SEC"; then
  pass_check "security wrapper says analyzers_ran is --changed-only and how to derive it otherwise"
else
  fail_check "security wrapper does not say analyzers_ran is absent on the standard path"
fi

# ======================================================= 2. the contract documents it
# Four wrappers and one /review rule depend on this string. Before this change the
# file that calls itself the shared envelope contract did not mention it once.
if grep -qF 'unresolved' "$CONTRACT"; then
  pass_check "envelope contract mentions the unresolved convention"
else
  fail_check "envelope contract never mentions unresolved — the mechanism four wrappers depend on is undocumented"
fi
if grep -qF "$MARK" "$CONTRACT" && grep -qF 'messages[]' "$CONTRACT"; then
  pass_check "contract states the literal marker and that it goes in messages[]"
else
  fail_check "contract does not state the literal '$MARK' inside messages[]"
fi
# Name the consumer. A convention with no named consumer is the state this whole
# defect came from: producers emitting into nothing.
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
# When a wrapper must emit it — all four could-not-check paths named in one place.
for tool in phpcpd phpstan phpmd; do
  if grep -qiF "$tool" "$CONTRACT"; then
    pass_check "contract names $tool among the could-not-check paths"
  else
    fail_check "contract's could-not-check table does not name $tool"
  fi
done

# --------------------------------------------- 2a. the skipped row is the written bug
# The old definition read "Gate was invoked but not run (e.g., user passed --skip, or
# the underlying tool is unavailable)". Folding those two into one verdict IS the
# defect, in prose, in the contract both halves are written against.
SKIPPED_ROW=$(grep -E '^\| `skipped` \|' "$CONTRACT" || true)
if [ -z "$SKIPPED_ROW" ]; then
  fail_check "contract has no skipped row in its verdict-semantics table"
else
  if printf '%s' "$SKIPPED_ROW" | grep -qiE 'tool is unavailable|tool unavailable'; then
    fail_check "contract's skipped row still folds tool-unavailability into a benign skip"
  else
    pass_check "contract's skipped row no longer folds tool-unavailability into a benign skip"
  fi
  if printf '%s' "$SKIPPED_ROW" | grep -qF 'unresolved'; then
    pass_check "contract's skipped row points at unresolved for the not-measured case"
  else
    fail_check "contract's skipped row does not distinguish the not-measured case"
  fi
fi

# The two coverage keys ride through --details untouched, so they need documenting
# as stable keys rather than as something a reader infers from one example.
for key in tools_absent analyzers_ran; do
  if grep -qE "^- \`$key\`" "$CONTRACT"; then
    pass_check "contract documents $key as a stable --details key"
  else
    fail_check "contract does not document $key as a --details key"
  fi
done

# ================================================= 3. the consumer half of /review
# Every producer above is decorative without this. Asserted separately from the
# producers on purpose: deleting rule 2 leaves all of section 1 green.
RULE2=$(grep -nE '^ +2\. `fail` if any hard-block gate is' "$REVIEW" | cut -d: -f1 || true)
if [ -z "$RULE2" ]; then
  fail_check "review.md step 8 has no rule 2 — the unresolved consumer is gone"
else
  R2=$(sed -n "${RULE2}p" "$REVIEW")
  # Read the ENVELOPE, not just the words. Rule 2 has always described writing
  # `unresolved: true` into its own gates_run[] entry for a parse error, so a check
  # for the marker plus "messages[]" stays green on a rule 2 that no longer looks at
  # a wrapper's file at all. The load-bearing half is the path: rule 2 must say it
  # reads `validations/latest/<gate>.json`, which is where the producers write.
  if printf '%s' "$R2" | grep -qF 'validations/latest/' \
     && printf '%s' "$R2" | grep -qF "$MARK" && printf '%s' "$R2" | grep -qF 'messages[]'; then
    pass_check "review.md rule 2 still reads '$MARK' out of a wrapper envelope at validations/latest/"
  else
    fail_check "review.md rule 2 no longer reads the marker out of a wrapper's envelope — producers emit into nothing"
  fi
  # And propagates it. Reading a value it then drops is the same silence.
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

# ---------------------------------------------- 3a. rule 4 no longer authorizes it
# Rule 4 lists the benign states that do NOT prevent a pass. "a tool-unavailable soft
# skip" was on that list, which is what let a gate measuring nothing go green. The
# assertion reads the parenthesised list only — rule 4 legitimately mentions absent
# analyzers now, in the clause saying they are NOT benign.
RULE4=$(grep -E '^ +4\. `pass` if \*\*all\*\* hard-block gates' "$REVIEW" || true)
if [ -z "$RULE4" ]; then
  fail_check "review.md step 8 has no rule 4"
else
  BENIGN=$(printf '%s' "$RULE4" | sed -n 's/.*Benign non-blocking states (\([^)]*\)).*/\1/p')
  if [ -z "$BENIGN" ]; then
    fail_check "review.md rule 4 has no parenthesised benign-state list to check"
  elif printf '%s' "$BENIGN" | grep -qiE 'tool|analyz'; then
    fail_check "review.md rule 4 still names a tool-availability state as benign: ${BENIGN}"
  else
    pass_check "review.md rule 4's benign list names no tool-availability state"
  fi
  if printf '%s' "$RULE4" | grep -qiE '(analyzer|tool).{0,40}(not|NOT) (benign|one of them)|NOT benign'; then
    pass_check "review.md rule 4 says an absent-analyzer skip is not benign"
  else
    fail_check "review.md rule 4 does not say an absent-analyzer skip is not benign"
  fi
  if printf '%s' "$RULE4" | grep -qF 'unresolved'; then
    pass_check "review.md rule 4 routes the absent-analyzer case to unresolved"
  else
    fail_check "review.md rule 4 does not route the absent-analyzer case anywhere"
  fi
fi

if [ "$FAIL" = "0" ]; then
  printf '\ngate-coverage-honesty-spec: all checks passed\n'
else
  printf '\ngate-coverage-honesty-spec: FAILURES\n' >&2
fi
exit "$FAIL"
