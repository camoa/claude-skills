#!/usr/bin/env bash
# command-body-lengths.sh — phase-command body growth ratchet.
#
# The five phase command bodies (commands/{research,design,implement,complete,
# review}.md) are loaded into Claude's context on every Skill invocation, so
# their length is a cost paid on every run rather than a style preference.
# v4.0.2 split each into a terse runtime body plus a
# `references/<phase>-walkthrough.md`, cutting 1465 lines to 265, and added
# this script so the bodies could not regrow silently.
#
# Usage:
#   scripts/command-body-lengths.sh                # check, exit non-zero on overrun
#   scripts/command-body-lengths.sh --json         # machine-readable JSON array
#   scripts/command-body-lengths.sh --budget NAME  # print one budget, for a caller
#                                                  # that needs the number
#
# The "body" is everything after the closing `---` of the YAML frontmatter,
# so the line counts here match `wc -l` on a frontmatter-stripped file.
#
# Run by tests/command-body-lengths-spec.sh, which `make test` discovers and
# `make ci` runs. That spec also proves this script can fail; before v5.35.7
# nothing called it at all.
#
# It exits non-zero on three things, not one: a body over its budget, a phase
# in the list with no budget recorded, and a run that measured no bodies at all.
# The last two exist because a check that found nothing to check has not passed.
#
# ── Where these numbers come from ────────────────────────────────────────────
# They are MEASURED, not designed. Four of the five were set on 2026-08-30 to
# the body length each command had on that date. This is a ratchet against
# further growth, not a claim that any of them is a good size.
#
# The four original budgets (research 100, design 80, implement 120, complete
# 100) were set on 2026-04-25 against bodies of 76/51/72/66 lines — a guess at
# comfortable headroom, never revisited. Nothing ran this script between then
# and 2026-08-30, and over those four months the bodies went to 142/82/363/67.
# `implement` grew 5x, to three times the budget it was nominally under. A
# budget nobody measures against is not a budget, so the honest move is to
# record where each body actually is and make further growth deliberate.
#
# `implement` at 363 is recorded, not endorsed. Shrinking it is real work with
# its own risk — the walkthrough split it once already — and belongs in its own
# task, not in the change that turns the ratchet on. What this file guarantees
# from here is that 363 cannot become 400 without someone editing this line.
#
# `review` is the one number that did not need setting: tests/review-command-
# spec.sh has enforced it since v4.1.0, and each of its nine raises carries a
# written reason. That is what enforcement produces (135 with a paper trail)
# against what its absence produces (363 with none). That spec used to carry a
# hand-mirrored copy of the number; it now reads it from here via --budget, so
# there is one place to change it.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Overridable so the spec can point the check at a fixture tree without
# mutating the real commands/. Defaults to the plugin's own commands/.
COMMANDS_DIR="${COMMAND_BODY_LENGTHS_DIR:-${PLUGIN_ROOT}/commands}"

PHASES="research design implement complete review"

budget_for() {
  case "$1" in
    # 142 -> 144, raise 1: two lines to replace a marker test with a content test at step 2. The
    # marker version overwrote an authored task.md; measured on the real corpus, 63 files carried
    # `Phase 0 — Scope` and 30 of those were authored work up to 246 lines, and the project record
    # is not a git repository so the loss was unrecoverable and undetectable. One line calls
    # scripts/stub-detect.sh and branches; the rest is the evidence, which belongs next to the
    # instruction rather than in a task folder nobody opens while editing this file.
    research) printf '144' ;;
    # 82 -> 83, raise 1: a design-close coverage gate that can halt, replacing a size estimate
    # that could not. Step 7 is now the gate and its records check (two lines for one) and
    # line 41 names the item-marker format in the clause that names acceptance criteria.
    design)   printf '83'  ;;
    # 363 -> 370, raise: wires the size-estimate kernel (since deleted, see 389 -> 382) into the component close, so a build
    # that outgrows its plan is visible while it is still open. Nothing in the lifecycle asked whether
    # a change was bigger than its problem. Measured: one build produced 1,637 insertions for roughly
    # 150 lines of necessary code and no gate, agent or record noticed the ratio at any point; the
    # operator interrupting on their own initiative was the only effective brake in that whole run.
    # Seven lines: four of comment carrying that evidence, one to count insertions, two to call the
    # kernel. It never blocks, so the cost of being wrong about it is one printed line.
    # 370 -> 356, LOWER: the finding_contract change deleted the beyond_remedy and repair_growth
    # instructions from this body, because scripts/repair-scope-check.sh now answers the same
    # question by comparing two sets of file paths instead of asking the builder to grade its own
    # work. The body shrank by 14 lines, so the budget follows it down. A budget left at 370 after a
    # deletion is 14 lines of space that can be reclaimed later without anyone editing this line,
    # which is the whole thing the ratchet exists to prevent. Lowering on a deletion needs no
    # justification beyond the deletion; raising still does.
    # 356 -> 380, raise 24: the accept step after `[a]ddress`. scripts/repair-accept-check.sh shipped
    # with no caller anywhere in commands/, references/ or skills/, while scripts/build-critique-assert.sh
    # already hard-fails any repaired component whose row carries no `accept` verdict. So every repaired
    # component in the next real build would have failed /review for omitting a field no instruction told
    # anyone to write. Nine lines are the runnable block (the post-repair checkpoint, the name-status diff
    # of the REPAIR range rather than the build range, the kernel call with its four flags); the rest is
    # the three things a caller gets wrong without being told: that --suite is a result handed in and never
    # a command the kernel runs, that `not_run` and an undetermined glob source are honest values returning
    # `cannot_judge` rather than a pass, and that the verdict is fail-closed at /review.
    # 380 -> 389, raise 9: the repair range is two SHAS. The block shipped handing `git diff` the
    # checkpoint LABEL `<component>.after`, which build-checkpoint.sh anchors under
    # refs/worktree/aida/build-checkpoints/ and git's rev-parse never searches. Git exited 128 after
    # the shell redirect had already created the file, so every repair on every real build handed the
    # accept kernel a 0-byte diff and read back `accepted` off a comparison nobody made: the tripwire
    # this block exists for could not fire once. Three of the nine lines are the comment saying why
    # the range is built from $AFTER, four are the prose saying it again outside the fence plus the
    # numeric `round` the gate requires and no instruction stated, and two are the blank lines around
    # them. The kernel now abstains on an empty motion file, so the same mistake made later is
    # `cannot_judge` rather than a clean repair, but nothing outside this body says to use the sha.
    # 389 -> 382, LOWER: review_ladder deleted the size-estimate block at the component close (the
    # 363 -> 370 raise above). The kernel compared a build against a number the designer wrote about
    # its own design, omitting the number was free and returned `cannot_judge`, and it hardcoded
    # blocks:false; the criterion it served was deleted from the epic. Seven lines gone, so the budget
    # follows them down, per the rule stated at 370 -> 356.
    # 382 -> 393, raise 11: the security and correctness critics receive the resolved implement
    # recipe. /review one stage later injected the same body into its validator and called
    # dispatching without it a bug, while the per-component critic at step 5 got acceptance
    # criteria and nothing else, so the lens named "does it do the right thing" had no stack
    # method to judge against. One line is the meets-ac exclusion, two are the no-body rule that
    # keeps a correctness critic from inventing the method, and the envelope records the lens
    # it did not run and why. The eighth line says security is still dispatched without a body:
    # the first cut bound both lenses to "inject or do not dispatch", which at medium tier on a
    # project with no recipe meant zero critics and a blocking envelope on every component. Four
    # more (three lines) say the dispatch is the contract and nothing more: with the old lens deleted, a builder wrote
    # a probe list into every prompt and bought a repair round per component (c9, owner-added).
    # 393 -> 405, raise 12: the [a]ddress step re-Reads each framework's body_path before the fix is
    # authored and records fix_recipe_read on _recipe-load.json. Repair is main flow, not a
    # dispatch, so there is no prompt to inject into; the body Read at step 6 is out of context by
    # round three or past a compaction, and the repair loop is where test growth compounds (1,336
    # of 1,944 lines in one change were tests; three fix rounds added 69 assertions and no
    # functions). Twelve lines: the instruction, the record's shape and writer, what `round` is, the
    # phase and `verified` gates on the re-read, and the two non-read verdicts with their reason.
    # 405 -> 417, raise 12: test motion is classified at the build-critique rung on every build, not
    # only on a repair. scripts/repair-accept-check.sh was general in its code and had one caller, the
    # repair path, so a test modified during the initial build was classified only if the component
    # later entered a repair round. Globs come from the recipe's `## Oracle files` row through
    # scripts/oracle-globs.sh, else the project convention, and the origin is recorded on the verdict.
    # Five lines are the runnable block (globs, the origin-or-undetermined branch, the kernel, the
    # verdict read back and said aloud), four the comment saying where the globs come from and why,
    # and three the surfaces-never-blocks rule. The first cut piped an `undetermined` origin into a
    # flag that rejects it and left a 0-byte record nothing read; three critics found it.
    # 417 -> 418, raise 1: the preflight reads the design-close coverage record. Before this the
    # design gate wrote a record nothing read, so a design that left a criterion uncovered or
    # carried an item reaching no goal opened a build anyway; one line makes the halt bind here.
    # 418 -> 432, raise 14: scripts/repair-scope-check.sh is called from the [a]ddress path. It had
    # exactly one live caller, build-critique-assert.sh at /review, which runs once per task after
    # every repair round is over -- so the check that exists to constrain a repair could not reach
    # one. Six lines are the runnable block (the kernel and its three flags, the record it writes,
    # the verdict said aloud), two the comment saying the flags are computed rather than filled in,
    # four the prose outside the fence saying why the rung is the call site and what the two
    # abstentions are, and two the blank lines around them. Every flag value is a subshell rather
    # than a `<placeholder>` on purpose: the same body shipped a repair-accept step whose diff went
    # into $(mktemp) with the name discarded, and a step a reader cannot run verbatim is a step that
    # runs wrong.
    # 432 -> 441, raise 9: the aggregate invocation passes --component-files-from, the range the
    # critics were handed. Without it the kernel that decides `blocking` cannot see the component's
    # own file list, so a finding naming only files outside the slice opened a repair round -- the
    # defect the criterion was written for, measured on this epic's own build. One flag line plus
    # eight of prose saying what the flag suppresses, what it does NOT suppress when absent, and why
    # an empty range is refused rather than applied. A kernel with no caller is the same defect this
    # same body just fixed for repair-scope-check.sh, one round earlier.
    implement) printf '441' ;;
    complete) printf '67'  ;;
    # 135 -> 136, raise 8: one line for the {{mechanism_unresolved_line}} token in the
    # review-summary template. 5.0c could not see a mechanism the cascade never searched, because its
    # only failure condition was an unresolved attended supersede, which exists only when the search
    # FOUND something. Measured on 22 records: 59 of 99 mechanisms were structurally invisible to it.
    # The explanatory prose was folded into 5.0c rather than added as its own paragraph, so the raise
    # is one line rather than three.
    # 136 -> 137, raise 9: one line for the {{spec_provenance_line}} token in the review-summary
    # template. Nothing distinguished a criterion the owner asked for from one the designer wrote,
    # so an invented criterion carried the authority of a real requirement — criterion-provenance.sh
    # and the alignment.md `— by:` marker (references/alignment-contract.md §5.2) exist to fix that.
    # This line surfaces the kernel's per-run counts (owner/designer/unrecorded) and names the
    # designer-authored and unrecorded criteria in the ## Spec block, so a reader sees provenance
    # without opening `_spec.json`. Advisory only: the kernel's `blocks` is hardcoded false and the
    # Spec verdict rule is unchanged — missing_requirements[] alone still drives fail.
    review)   printf '137' ;;
    *) return 1 ;;
  esac
}

MODE="check"
case "${1:-}" in
  --json)   MODE="json" ;;
  --budget) MODE="budget" ;;
  "")       ;;
  *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

if [ "$MODE" = "budget" ]; then
  want="${2:-}"
  if [ -z "$want" ]; then
    printf '--budget needs a phase name (one of: %s)\n' "$PHASES" >&2
    exit 2
  fi
  if ! budget_for "$want"; then
    printf 'no budget recorded for phase: %s\n' "$want" >&2
    exit 2
  fi
  printf '\n'
  exit 0
fi

# Body line count = total lines minus frontmatter (between first two --- lines, inclusive).
body_lines() {
  awk 'BEGIN{in_fm=0; done_fm=0; n=0}
    /^---$/ && !done_fm { in_fm++; if (in_fm == 2) done_fm=1; next }
    in_fm == 1 && !done_fm { next }
    { n++ }
    END { print n }
  ' "$1"
}

FAIL=0
CHECKED=0
RESULTS=""
for phase in $PHASES; do
  # A phase named in the list with no recorded budget is a hole in the table,
  # not a pass. Reachable the moment someone adds a sixth phase command and
  # forgets the number.
  if ! budget="$(budget_for "$phase")"; then
    printf 'FAIL: no budget recorded for phase %s\n' "$phase" >&2
    FAIL=1
    continue
  fi
  file="${COMMANDS_DIR}/${phase}.md"
  if [ ! -f "$file" ]; then
    if [ "$MODE" = "json" ]; then
      RESULTS="${RESULTS}{\"phase\":\"${phase}\",\"verdict\":\"missing\",\"file\":\"${file}\"},"
    else
      printf 'MISSING: %s\n' "$file" >&2
    fi
    FAIL=1
    continue
  fi
  lines=$(body_lines "$file")
  CHECKED=$((CHECKED + 1))
  if [ "$lines" -gt "$budget" ]; then
    verdict="over"
    FAIL=1
  else
    verdict="ok"
  fi
  if [ "$MODE" = "json" ]; then
    RESULTS="${RESULTS}{\"phase\":\"${phase}\",\"verdict\":\"${verdict}\",\"lines\":${lines},\"budget\":${budget}},"
  else
    printf '%-9s %3d / %3d lines  %s\n' "$phase" "$lines" "$budget" "$verdict"
  fi
done

if [ "$MODE" = "json" ]; then
  RESULTS="${RESULTS%,}"
  printf '[%s]\n' "$RESULTS"
fi

# A check that measured nothing has not passed. Reached when COMMANDS_DIR holds
# none of the five files — a wrong override, a moved commands/, an empty tree.
if [ "$CHECKED" -eq 0 ]; then
  printf 'FAIL: measured no command bodies under %s; nothing was checked.\n' "$COMMANDS_DIR" >&2
  exit 1
fi

exit "$FAIL"
