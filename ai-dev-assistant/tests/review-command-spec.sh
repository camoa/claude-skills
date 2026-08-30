#!/usr/bin/env bash
# review-command-spec.sh — verify commands/review.md invariants (v4.1.0+).
#
# Checks the 5-mechanism markers + body line budget + frontmatter required fields.
# Run pre-PR-merge or via /plugin-creation-tools:validate alongside.
#
# Exit 0 on all-pass; 1 on any fail.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${PLUGIN_ROOT}/commands/review.md"

if [ ! -f "$TARGET" ]; then
  printf 'FAIL: %s not found\n' "$TARGET" >&2
  exit 1
fi

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

# 1. Frontmatter required fields
for field in description allowed-tools argument-hint; do
  if grep -q "^${field}:" "$TARGET"; then
    pass_check "frontmatter has $field"
  else
    fail_check "frontmatter missing $field"
  fi
done

# 2. Body line count ≤132 (120 -> 125 in v5.23.0 for the mandatory ## Output
#    section; 125 -> 127 in v5.30.3 for the step-0 phase declaration the other
#    three phase commands have had since v5.29.0 and this one never did;
#    127 -> 129 in v5.33.0 for step 5.0f, the gate that makes the build-critique
#    rung able to fail — the rung shipped with three things that looked like
#    enforcement and none that could;
#    129 -> 131 in v5.35.5 for step 8b, the contract-drift diff. Step 0 absorbed the
#    baseline capture rather than adding a step of its own, so the growth is the one
#    genuinely new gate step and not its prose;
#    131 -> 132 in v5.35.6 for step 8's rule on a hard-block `warning`. `warning` is a
#    legal gates_run[].verdict that none of the four rules named, so aggregation fell off
#    the end of the list and a partially-covered gate reached green with no rule allowing
#    it. The rules are an ORDERED resolution and their rank is the contract, so this could
#    not be folded into the `pass` rule's line without leaving the new case unranked —
#    which is the same defect in a different place.
#    132 -> 135 in v5.35.7, three lines for two fixes that had nowhere else to go. ONE is the
#    sidecar bullet under step 5.0: architecture-validator and spec-axis-reviewer now write their
#    verdict to a file instead of returning it as prose, and the dispatch site has to say where and
#    what an ABSENT sidecar means — a nested bullet under the existing dispatch bullet, because it
#    is a second instruction about the same dispatch and not a step. TWO is step 9a, the file-
#    ownership rule on the [r] remediation path; it is a new step because [r] is a branch of step 9
#    that nothing downstream describes, and folding it into step 9's line would bury a rule about
#    concurrent agents inside the prompt-wording paragraph. The remaining four changes of this
#    version — the spec sidecar, the record archive, the upstream advisory, the Output section —
#    extended lines that already existed and cost nothing.
#    The reasoning for each raise lives here; the NUMBER lives in
#    scripts/command-body-lengths.sh and is read from it below. It used to be
#    written out in both files, and at v5.35.5 they disagreed — this spec
#    enforced 131 while that script still said 129 — which nothing caught,
#    because nothing ran that script. One number, one home.)
BUDGET_SCRIPT="${PLUGIN_ROOT}/scripts/command-body-lengths.sh"
if [ ! -x "$BUDGET_SCRIPT" ] && [ ! -f "$BUDGET_SCRIPT" ]; then
  fail_check "budget source $BUDGET_SCRIPT not found"
  BUDGET=""
else
  BUDGET=$(bash "$BUDGET_SCRIPT" --budget review 2>/dev/null || true)
fi
if ! printf '%s' "$BUDGET" | grep -qE '^[0-9]+$'; then
  # No default. A budget that cannot be read is an unmeasured check, and an
  # unmeasured check does not pass.
  fail_check "could not read the review body budget from $BUDGET_SCRIPT"
else
  BODY_LINES=$(awk 'BEGIN{f=0;d=0;n=0} /^---$/&&!d{f++;if(f==2)d=1;next} f==1&&!d{next} {n++} END{print n}' "$TARGET")
  if [ "$BODY_LINES" -le "$BUDGET" ]; then
    pass_check "body line count $BODY_LINES ≤ $BUDGET"
  else
    fail_check "body line count $BODY_LINES > $BUDGET"
  fi
fi

# 3. 5-mechanism markers
declare -A MARKERS=(
  [anti-bypass-clause]="^## Anti-bypass clause"
  [mandated-wording-ref]="Mandated wording"
  [gate-audit-write-call]="gate-audit-write.sh"
  [show-not-summarize]="verbatim"
  [always-evaluated-framing]="all gates fire|always evaluated|always-evaluated|once invoked"
)
for name in "${!MARKERS[@]}"; do
  if grep -qE "${MARKERS[$name]}" "$TARGET"; then
    pass_check "5-mechanism marker: $name"
  else
    fail_check "5-mechanism marker missing: $name"
  fi
done

# 4. Required flags documented
for flag in --team --dry-run --rerun-failed --no-pr-body --skip-; do
  if grep -qF -- "$flag" "$TARGET"; then
    pass_check "flag documented: $flag"
  else
    fail_check "flag missing: $flag"
  fi
done

if [ "$FAIL" -ne 0 ]; then
  printf '\ncommands/review.md invariants violated.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for commands/review.md.\n'
exit 0
