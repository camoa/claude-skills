#!/usr/bin/env bash
# criterion-provenance-wiring-spec.sh — doc-contract test for the criterion-provenance wiring
# (v1.3+ alignment-contract: the `— by: owner|designer` marker + criterion-provenance.sh).
#
# Nothing distinguished a criterion the owner asked for from one the designer wrote. A builder
# wrote a criterion at design time describing a filter it had already decided to build; four
# critics then checked the filter against that description, faithfully, for two rounds. This
# wiring makes a criterion's authorship a recorded, readable fact: `/scope` writes it, `/design`
# inherits it through the same inline flow, and `/review`'s Spec axis surfaces it — never gates
# on it. This spec follows tests/mechanism-challenge-wiring-spec.sh's pattern: grep the command
# files for the literal instruction so a reverted wire goes red.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$DIR/.."
KERNEL="$ROOT/scripts/criterion-provenance.sh"
SCOPE="$ROOT/commands/scope.md"
DESIGN="$ROOT/commands/design.md"
REVIEW="$ROOT/commands/review.md"
AGENT="$ROOT/agents/spec-axis-reviewer.md"
AXISREF="$ROOT/references/spec-axis-review.md"
CONTRACT="$ROOT/references/alignment-contract.md"
fail=0
for f in "$KERNEL" "$SCOPE" "$DESIGN" "$REVIEW" "$AGENT" "$AXISREF" "$CONTRACT"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; fail=1; }
done
has(){ local f="$1" d="$2"; shift 2; if grep -Eq "$@" "$f"; then echo "PASS: $d"; else echo "FAIL: $d (missing: $* in $(basename "$f"))"; fail=1; fi; }
hasnt(){ local f="$1" d="$2"; shift 2; if grep -Eq "$@" "$f"; then echo "FAIL: $d (must NOT appear: $* in $(basename "$f"))"; fail=1; else echo "PASS: $d"; fi; }

# --- the kernel exists, is executable, and never blocks ---
[ -x "$KERNEL" ] && echo "PASS: criterion-provenance.sh executable" || { echo "FAIL: kernel not executable"; fail=1; }
has "$KERNEL" "kernel blocks is hardcoded false" -- 'blocks: ?false'

# --- alignment-contract.md §5.2 documents the marker ---
has "$CONTRACT" "contract documents the — by: marker"          -- '— by: <owner\|designer>'
has "$CONTRACT" "contract: absent marker is null, not owner"   -i 'null does not mean owner|absent marker'

# --- commands/scope.md: who writes owner, who writes designer ---
has "$SCOPE" "scope instructs the owner marker on confirm"       -i 'by: owner.*confirm|confirmed.*by: owner|— by: owner.{0,80}confirmed'
has "$SCOPE" "scope instructs designer on the unattended path"   -i 'unattended.{0,120}designer|designer.{0,120}unattended'
has "$SCOPE" "scope canonical template shows the by: marker"     -- '- \[ \] <falsifiable statement> — by: <owner\|designer>'
has "$SCOPE" "scope states marker precedes verify suffix"        -i 'before.{0,40}verify|marker.{0,40}before'

# --- commands/design.md: names the author rule for its inline scope flow ---
has "$DESIGN" "design names the author rule for inline scope"    -i 'author marker'
has "$DESIGN" "design: command does not decide, confirm does"    -i 'confirm does'

# --- design-walkthrough.md: traceability walkthrough tags provenance ---
WALK="$ROOT/references/design-walkthrough.md"
[ -f "$WALK" ] || { echo "FAIL: missing $WALK"; fail=1; }
has "$WALK" "walkthrough tags [designer]/[unrecorded] AC rows"   -- '\[designer\]|\[unrecorded\]'

# --- commands/review.md: invokes the kernel and never adds a new halt ---
has "$REVIEW" "review invokes criterion-provenance.sh"           'criterion-provenance\.sh'
has "$REVIEW" "review passes author to spec-axis-reviewer"       -i 'author.{0,80}spec-axis-reviewer|spec-axis-reviewer.{0,80}author'
has "$REVIEW" "review renders spec_provenance_line"              '\{\{spec_provenance_line\}\}'
has "$REVIEW" "review states the verdict rule is unchanged"      -i 'verdict rule.{0,40}unchanged|never changes the verdict rule'
has "$REVIEW" "review states provenance never gates"              -i 'never folded into it|never a new halt'

# --- agents/spec-axis-reviewer.md: sees per-criterion author, does not re-report it ---
has "$AGENT" "agent input carries per-criterion author"          -i 'recorded \*\*author\*\*|author.{0,40}owner.{0,10}designer.{0,10}null'
has "$AGENT" "agent never reads null author as owner's"          -i 'never report it as one|never.{0,60}(fold|report).{0,60}owner'

# --- commands/review.md: names what the owner never asked for, in the rendered ## Spec block ---
# This is the actual requirement, not a separate agent-produced list: criterion-provenance.sh already
# computes designer_authored[]/unrecorded[] deterministically, so /review renders them by name via
# {{spec_provenance_line}} instead of asking the agent to compute the same thing twice.
has "$REVIEW" "review names designer-authored criteria by name"  -- 'designer: <name>'
has "$REVIEW" "review names unrecorded criteria by name"         -- 'unrecorded: <name>'

# --- F4b: no_criteria renders a distinct line, not silence ---
# Before this fix, "the task declared no criteria" and "the kernel never ran" both looked like
# nothing printed. Step 13 must render a plain line on the kernel's no_criteria status too.
has "$REVIEW" "review renders a distinct line on no_criteria"    -i 'no criteria recorded for this section'
has "$REVIEW" "review omits the line only when the field itself is absent" -i 'gate_specific\.provenance.{0,40}absent|provenance.{0,20}key.{0,20}absent'

# --- non-zero kernel exit: its own state, its own line ---
# The kernel can exit 2 with no JSON. Before this, step 5.0d said nothing about that case, so it was
# undefined at the exact moment the kernel says it could not look. A non-zero exit must read as
# no_return, never as no_criteria and never as a pass.
has "$REVIEW" "review checks the kernel's exit code before parsing" -i 'check the exit code before parsing'
has "$REVIEW" "review records a non-zero exit as no_return"       -- '"status": "no_return"'
has "$REVIEW" "review renders a distinct line on no_return"       -i 'check did not run'

# --- F8: the provenance line discriminates instead of firing the same way on every task ---
# Measured against 166 real contracts: every one is fully unrecorded, so an unconditional
# enumeration prints the same shape every time (median 588 chars, max 2476, one line) — a signal
# that fires on 100% of the corpus carries none. The line must tell five things apart on screen:
# check-did-not-run, no-criteria, no-author-recorded, a-mix-with-names, all-owner-confirmed.
has "$REVIEW" "review has a distinct no-author-recorded form"     -i 'no criterion records an author'
has "$REVIEW" "review does not enumerate the no-author-recorded case" -i 'do not enumerate'
has "$REVIEW" "review has a distinct all-owner form"               -i 'all <T> criteria owner-confirmed|all.{0,10}criteria owner-confirmed'
has "$REVIEW" "review caps the enumeration and states the cap"     -i 'capped at 5 names'
has "$REVIEW" "review truncates names and states the length"       -i 'first 60 characters'
has "$REVIEW" "review distinguishes criteria_unreadable from no_criteria" -i 'criteria_unreadable|not readable as a checklist'
has "$REVIEW" "review names the reader's warning code on criteria_unreadable" -- 'success_criteria_not_checklist'
has "$REVIEW" "review renders counts.unrecognized in the mix line"     -- '<R> unrecognized'
has "$REVIEW" "review always shows unrecognized, including zero"       -- '<R>.{0,40}always shown, including zero'

# --- references/gate-hardening-prompts.md carries the same seven-state contract ---
GATEDOC="$ROOT/references/gate-hardening-prompts.md"
[ -f "$GATEDOC" ] || { echo "FAIL: missing $GATEDOC"; fail=1; }
has "$GATEDOC" "gate-hardening-prompts documents no_return"        -- 'status: "no_return"'
has "$GATEDOC" "gate-hardening-prompts documents the no-author form" -i 'no criterion records an author'
has "$GATEDOC" "gate-hardening-prompts documents the all-owner form" -i 'all.{0,10}criteria owner-confirmed'
has "$GATEDOC" "gate-hardening-prompts names the warning code"       -- 'success_criteria_not_checklist'
has "$GATEDOC" "gate-hardening-prompts renders counts.unrecognized"  -- '<R> unrecognized'

# --- references/spec-axis-review.md documents the same contract ---
has "$AXISREF" "axis reference documents provenance"             -i 'criterion-provenance\.sh'
has "$AXISREF" "axis reference: report not a gate"                -i 'report, not a gate'

# --- the callers can actually PRODUCE a non-owner author (the repair itself, not just prose) ---
# Without these two, the whole repair is invisible to the suite: restoring scope.md/review.md
# from HEAD would remove every mention of the by: marker from commands/ and this suite would
# still pass on prose alone. Exercise the kernel directly against a fixture.
TMP_TASK="$(mktemp -d)"
trap 'rm -rf "$TMP_TASK"' EXIT
cat > "$TMP_TASK/alignment.md" <<'EOF'
# Alignment: fixture

## Task-Level

### Goal

x

### Expected result

y

### Success criteria

- [ ] an owner criterion — by: owner
- [ ] a designer criterion — by: designer
- [ ] an unrecorded criterion

### Non-goals

- z
EOF
OUT="$("$KERNEL" --task-folder "$TMP_TASK" --section task_level 2>/dev/null)"
[ "$(jq -r '.status' <<<"$OUT" 2>/dev/null)" = "unrecorded_present" ] \
  && echo "PASS: kernel status unrecorded_present on a mixed fixture" \
  || { echo "FAIL: kernel status wrong on mixed fixture: $OUT"; fail=1; }
[ "$(jq -r '.counts.owner' <<<"$OUT" 2>/dev/null)" = "1" ] && [ "$(jq -r '.counts.designer' <<<"$OUT" 2>/dev/null)" = "1" ] && [ "$(jq -r '.counts.unrecorded' <<<"$OUT" 2>/dev/null)" = "1" ] \
  && echo "PASS: kernel counts owner/designer/unrecorded 1/1/1" \
  || { echo "FAIL: kernel counts wrong on mixed fixture: $OUT"; fail=1; }
[ "$(jq -r '.designer_authored[0]' <<<"$OUT" 2>/dev/null)" = "a designer criterion" ] \
  && echo "PASS: kernel names the designer-authored criterion" \
  || { echo "FAIL: kernel did not name the designer-authored criterion: $OUT"; fail=1; }
[ "$(jq -r '.blocks' <<<"$OUT" 2>/dev/null)" = "false" ] \
  && echo "PASS: kernel blocks is false on a mixed fixture" \
  || { echo "FAIL: kernel must never block: $OUT"; fail=1; }

echo
if [ "$fail" -eq 0 ]; then echo "criterion-provenance-wiring-spec: ALL PASS"; exit 0; else echo "criterion-provenance-wiring-spec: FAILURES"; exit 1; fi
