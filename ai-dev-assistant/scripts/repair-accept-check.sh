#!/usr/bin/env bash
# repair-accept-check.sh. The deterministic accept kernel for a repair, section 2 of the
# deterministic_accept design (../../projects/ai_dev_assistant/.../deterministic_accept/
# architecture.md). Sits beside scripts/repair-scope-check.sh at the same call site and follows its
# contract exactly. Where that sibling answers "did the repair stay on the finding's topic", this one
# answers "may the repair be accepted": accepted / not_accepted / cannot_judge, from a suite result
# plus the test motion the repair made. No model judgment anywhere in the decision.
#
# THE KERNEL RUNS NOTHING. --suite is a result the caller hands in, never a command this script
# executes. That is forced, not chosen: no project records a suite command anywhere
# (scripts/project-state-read.sh), and references/tdd-workflow.md puts an unattended whole-suite
# sweep outside what the agent does. Who runs the suite is already answered by run_mode.
#
# Inputs:
#   --suite <green|red|not_run>              REQUIRED. The result of the existing suite over the
#                    repaired tree. `not_run` is a first-class value, not a missing one, and it
#                    forces cannot_judge (see below). There is no default: a caller who did not run
#                    the suite has to say so.
#   --test-motion-from <file>                REQUIRED. A file holding `git diff --name-status`
#                    output for the REPAIR range (the round's .after to the post-repair HEAD, not
#                    the range of the build being critiqued). TAB-separated "STATUS\tpath"; a rename
#                    "R###\told\tnew" is normalised to old-as-D plus new-as-A, and a copy
#                    "C###\told\tnew" to new-as-A only, the same normalisation
#                    scripts/wo-oracle-check.sh:15-17 already applies. The path must be readable;
#                    an unreadable one is a bad argument, never an empty motion. A readable file of
#                    ZERO BYTES is neither: it forces cannot_judge (see below).
#   --test-globs <json array of strings>     REQUIRED. The paths that count as tests here. Pass `[]`,
#                    never omit the flag, when the caller established there are no test paths.
#                    Matched with bash's own `case` pattern matching against the path STRING: no
#                    filesystem globbing, no directory listing, so a path matching a glob counts even
#                    when no such file exists on disk. That is deliberate. A deleted test file is
#                    exactly the motion this kernel most needs to see, and it is gone from disk by
#                    the time anyone asks.
#   --test-globs-source <determined|undetermined>  OPTIONAL, default determined. `undetermined` means
#                    the caller could not establish what a test path is in this project, and forces
#                    cannot_judge. An empty array cannot carry both "this repair touched no test
#                    path" and "I do not know what a test path is here"; repair-scope-check.sh had to
#                    add this flag after shipping without it, and this one ships with it.
#   --modification-reason <text>             OPTIONAL. Why a test file was modified. A modified test
#                    with no reason is not_accepted; the same modification WITH a reason is accepted.
#                    The tripwire demands a reason, it never forbids the change. Passing the flag
#                    with a value that is empty or whitespace-only is rejected as a bad argument:
#                    omitting the flag says "I have no reason" and is answered not_accepted, while
#                    passing a blank one says "here is my reason" and hands over nothing. Whitespace
#                    is included because the gate that reads this reason back off the record
#                    (build-critique-assert.sh's BAD_BASIS) trims before it decides, so a blank
#                    accepted here would be rejected there.
#
# Output (a single JSON object on stdout):
#   { "action": "accepted|not_accepted|cannot_judge", "blocks": false,
#     "decided_by": "suite_and_motion|motion|none", "suite": "green|red|not_run",
#     "motion": { "added": [], "deleted": [], "modified": [] }, "reasons": [] }
#     action      accepted     = the suite was green and the motion raised nothing unanswered.
#                 not_accepted = the suite was red, OR a test file was modified with no
#                                --modification-reason.
#                 cannot_judge = --test-motion-from named a ZERO-BYTE file, OR --suite was not_run,
#                                OR --test-globs-source was undetermined.
#                                UNMEASURED, never "fine". cannot_judge is NEVER accepted. Folding
#                                "I could not look" into a pass is the defect this repo keeps
#                                re-finding (mechanism-disposition.sh's `not_searched`,
#                                criterion-provenance.sh's `unrecorded`, repair-scope-check.sh's own
#                                `cannot_judge`).
#     blocks      always false. SURFACES, never halts. A brake that fires on most repairs gets
#                 bypassed, not satisfied.
#     decided_by  motion           = the test motion alone settled it, whatever the suite said.
#                 suite_and_motion = both facts were weighed, the motion raised nothing unanswered,
#                                    and the suite result carried the answer.
#                 none             = reserved for cannot_judge, where no comparison was made.
#     suite       the --suite value echoed back, so a reader of the JSON never reconstructs an input.
#     motion      the three arrays, ALWAYS all three and always present even when empty, holding only
#                 the paths that matched --test-globs. Empty across the board when the glob source
#                 was undetermined, because nothing was classified in that case.
#     reasons     plain sentences for what drove the action. Never empty on cannot_judge, where it is
#                 the only place the caller learns which of the three abstentions fired.
#
# WHY A ZERO-BYTE MOTION FILE ABSTAINS. It has no honest reading as a positive claim. A caller who
# established there are no test paths says so with `--test-globs '[]'`, and one who could not
# establish it says so with `--test-globs-source undetermined`; both are already flags. What is left
# is a file nobody wrote anything into, and the two ways to get one are a diff that failed and a
# repair that changed nothing. `git diff` writes its error to stderr while the shell redirect has
# already created the file, so a range handed a checkpoint LABEL instead of a sha exits 128 and
# leaves exactly this. That is how it shipped in commands/implement.md, and reading it as a repair
# that moved no test made every repair on every real build report `accepted` off a diff that was
# never computed. Neither cause is an acceptance.
#
# What this cannot see:
#   - A SELF-REPORTED green suite is not a verified one. This kernel reads a value a caller typed.
#     Nothing on disk distinguishes a suite somebody ran from one they said they ran, and this script
#     does not try to tell them apart.
#   - A GREEN SUITE IS NOT PROOF A REPAIR IS CORRECT. On the real record for `event_archiving`,
#     phpcs, phpstan and phpunit all passed over the repaired tree while two criticals a later critic
#     found were live in it. `accepted` here means "nothing in these two facts objected", never "the
#     repair is right".
#   - Motion is A / M / D only. It cannot see a test that was modified in a way that WEAKENED it: an
#     assertion loosened, a case deleted from inside a file, an expected value edited to match
#     whatever the code now does. All three arrive as one `M`. The --modification-reason string is
#     the only thing carrying direction, and nothing here verifies that the string is true.
#   - Path matching is LITERAL and glob-only. No normalisation, no symlink resolution, no basename
#     matching. A test path the caller's --test-globs failed to describe is invisible to the motion
#     tripwire, and reads here as an ordinary source file.
#   - A name-status status other than A, M, D, R and C (a typechange, an unmerged path) is skipped
#     rather than classified, matching wo-oracle-check.sh. Such a line contributes no motion.
#
# Exit: 0 with JSON on every valid input, cannot_judge included; 2 on a bad or missing argument
# (fail-closed, nothing on stdout).

set -uo pipefail

# A value that itself looks like a flag is rejected rather than silently consumed, the same guard
# repair-scope-check.sh uses, for the same reason: `--suite --test-globs` must not read
# "--test-globs" as the suite value and shift the real flag away.
require_value() {
  case "$2" in
    --*) echo "repair-accept-check: $1 needs a value, got a flag instead: $2" >&2; exit 2 ;;
  esac
}

SUITE=""; MOTION_FROM=""; TEST_GLOBS=""; GLOBS_SOURCE="determined"; GLOBS_ORIGIN=""; MOD_REASON=""; MOD_REASON_SET=0
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/glob-to-regex.sh"
while [ $# -gt 0 ]; do
  case "$1" in
    --suite) [ "$#" -ge 2 ] || { echo "repair-accept-check: --suite needs a value" >&2; exit 2; }; require_value --suite "$2"; SUITE="$2"; shift 2 ;;
    --test-motion-from) [ "$#" -ge 2 ] || { echo "repair-accept-check: --test-motion-from needs a value" >&2; exit 2; }; require_value --test-motion-from "$2"; MOTION_FROM="$2"; shift 2 ;;
    --test-globs) [ "$#" -ge 2 ] || { echo "repair-accept-check: --test-globs needs a value" >&2; exit 2; }; require_value --test-globs "$2"; TEST_GLOBS="$2"; shift 2 ;;
    --test-globs-source) [ "$#" -ge 2 ] || { echo "repair-accept-check: --test-globs-source needs a value" >&2; exit 2; }; require_value --test-globs-source "$2"; GLOBS_SOURCE="$2"; shift 2 ;;
    --test-globs-origin) [ "$#" -ge 2 ] || { echo "repair-accept-check: --test-globs-origin needs a value" >&2; exit 2; }; require_value --test-globs-origin "$2"; GLOBS_ORIGIN="$2"; shift 2 ;;
    --modification-reason) [ "$#" -ge 2 ] || { echo "repair-accept-check: --modification-reason needs a value" >&2; exit 2; }; require_value --modification-reason "$2"; MOD_REASON="$2"; MOD_REASON_SET=1; shift 2 ;;
    *) echo "repair-accept-check: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$SUITE" ] || { echo "repair-accept-check: --suite is required" >&2; exit 2; }
[ -n "$MOTION_FROM" ] || { echo "repair-accept-check: --test-motion-from is required" >&2; exit 2; }
[ -n "$TEST_GLOBS" ] || { echo "repair-accept-check: --test-globs is required" >&2; exit 2; }

# Enums validated before any logic runs, so an out-of-enum value can never reach the matrix.
case "$SUITE" in
  green|red|not_run) ;;
  *) echo "repair-accept-check: --suite must be green|red|not_run" >&2; exit 2 ;;
esac
case "$GLOBS_SOURCE" in
  determined|undetermined) ;;
  *) echo "repair-accept-check: --test-globs-source must be determined|undetermined" >&2; exit 2 ;;
esac
# Where the globs came from (scripts/oracle-globs.sh): the recipe's `## Oracle files` row, or a
# convention. Optional, recorded, closed enum. No globs and no recorded origin used to read as "no
# test files changed", a false clean; the record now says which source the classification stood on.
case "$GLOBS_ORIGIN" in
  ""|recipe|convention) ;;
  *) echo "repair-accept-check: --test-globs-origin must be recipe|convention" >&2; exit 2 ;;
esac

# A flag PASSED with a blank value is a bad argument, and this is the one place the difference
# between "absent" and "blank" is load-bearing: absent means the caller has no reason and is answered
# not_accepted, blank means the caller believes they gave one. Trimmed, so `--modification-reason
# " "` is refused with the empty string rather than admitted as a reason of one space.
if [ "$MOD_REASON_SET" = "1" ]; then
  case "$MOD_REASON" in
    *[![:space:]]*) ;;
    *) echo "repair-accept-check: --modification-reason was passed with no reason in it; omit the flag if there is none" >&2; exit 2 ;;
  esac
fi

[ -r "$MOTION_FROM" ] || { echo "repair-accept-check: --test-motion-from is not a readable file: $MOTION_FROM" >&2; exit 2; }
jq -e 'type == "array" and (all(.[]; type == "string"))' >/dev/null 2>&1 <<<"$TEST_GLOBS" \
  || { echo "repair-accept-check: --test-globs must be a JSON array of strings" >&2; exit 2; }

# --- emit ---------------------------------------------------------------------
# to_json_array <string>...  the arguments as a JSON array of strings; `[]` for none.
to_json_array() {
  [ "$#" -eq 0 ] && { printf '[]'; return; }
  printf '%s\n' "$@" | jq -R -s -c 'split("\n") | map(select(length > 0))'
}

REASONS=()
# emit <action> <decided_by> <motion-json>
emit() {
  local reasons_json
  reasons_json="$(to_json_array ${REASONS[@]+"${REASONS[@]}"})"
  jq -nc --arg a "$1" --arg d "$2" --arg s "$SUITE" --argjson m "$3" --argjson r "$reasons_json" --arg o "$GLOBS_ORIGIN" \
    '{action:$a, blocks:false, decided_by:$d, suite:$s, motion:$m, reasons:$r, test_globs_origin:(if $o=="" then null else $o end)}'
}
EMPTY_MOTION='{"added":[],"deleted":[],"modified":[]}'

# --- abstentions, checked before any comparison -------------------------------
# All three are UNMEASURED states, and all three have to be answered before the matrix, because none
# of them leaves anything meaningful to compare. cannot_judge is never accepted.

# The zero-byte motion file, answered FIRST, ahead of the two questions about what the caller knows.
# It is a fact about the input rather than about the caller's knowledge, and it is the more
# diagnostic of any pair: a file with nothing in it says the comparison never happened, which is
# worth naming even when the caller also could not say what a test path is. See the header for why
# an empty file is not a claim of no motion.
if [ ! -s "$MOTION_FROM" ]; then
  REASONS+=("--test-motion-from named a file of zero bytes, so no diff was read: either it was never computed or the repair changed nothing, and neither is a repair that moved no test")
  emit cannot_judge none "$EMPTY_MOTION"
  exit 0
fi

if [ "$GLOBS_SOURCE" = "undetermined" ]; then
  # The caller could not establish what a test path is here. Every path would have to be classified
  # against a set nobody has, so the motion arrays stay empty rather than reporting a guess.
  REASONS+=("--test-globs-source was undetermined, so no path could be classified as a test path")
  emit cannot_judge none "$EMPTY_MOTION"
  exit 0
fi

# --- read the motion ----------------------------------------------------------
GLOBS=()
while IFS= read -r _g; do
  [ -n "$_g" ] && GLOBS+=("$_g")
done < <(jq -r '.[]' <<<"$TEST_GLOBS")

# matches_test_glob <path>. Returns 0 when the path string matches any --test-globs pattern.
matches_test_glob() {
  [ "${#GLOBS[@]}" -eq 0 ] && return 1
  local _p="$1" pattern
  for pattern in "${GLOBS[@]}"; do
    # The shared translator, not a bash `case`: under `case`, `**` is `*` and `*` needs the slash
    # present, so `**/tests/**/*Test.php` missed tests/src/Kernel/FooTest.php and `**/*_test.go`
    # missed main_test.go, while wo-oracle-check.sh matched both. Same declaration, one semantics.
    path_matches "$_p" "$pattern"; case $? in
      0) return 0 ;;
      2) echo "repair-accept-check: --test-globs pattern did not compile: $pattern" >&2; exit 2 ;;
    esac
  done
  return 1
}

ADDED=(); DELETED=(); MODIFIED=()
# record <status A|M|D> <path>. Files one normalised change under the matching array, and only when
# the path is a test path. A non-test path is motion this kernel has no opinion about.
record() {
  local _st="$1" _p="$2"
  [ -z "$_p" ] && return 0
  matches_test_glob "$_p" || return 0
  case "$_st" in
    A) ADDED+=("$_p") ;;
    D) DELETED+=("$_p") ;;
    M) MODIFIED+=("$_p") ;;
  esac
}

while IFS=$'\t' read -r _f1 _f2 _f3 || [ -n "${_f1:-}" ]; do
  _f1="${_f1%$'\r'}"; _f2="${_f2%$'\r'}"; _f3="${_f3%$'\r'}"
  [ -z "$_f1" ] && continue
  case "$_f1" in
    # RENAME (R###, or bare R): old path DELETED, new path ADDED. One file to git, two facts here,
    # and neither of them is a modification, which is why a renamed test needs no reason.
    R*) record D "$_f2"; record A "$_f3" ;;
    # COPY (C###, or bare C): only the destination is new. The source is untouched and contributes
    # nothing, so it appears in no array at all.
    C*) record A "$_f3" ;;
    A|M|D) record "$_f1" "$_f2" ;;
    *) continue ;;
  esac
done < "$MOTION_FROM"

A_JSON="$(to_json_array ${ADDED[@]+"${ADDED[@]}"})"
D_JSON="$(to_json_array ${DELETED[@]+"${DELETED[@]}"})"
M_JSON="$(to_json_array ${MODIFIED[@]+"${MODIFIED[@]}"})"
MOTION="$(jq -nc --argjson a "$A_JSON" --argjson d "$D_JSON" --argjson m "$M_JSON" \
  '{added:$a, deleted:$d, modified:$m}')"

# The motion tripwire first, ahead of the not_run abstention too, because it settles the answer whatever
# the suite said or did not say: a green suite
# over a test somebody quietly rewrote is the case the tripwire exists for.
if [ "${#MODIFIED[@]}" -gt 0 ] && [ -z "$MOD_REASON" ]; then
  REASONS+=("a test file was modified with no --modification-reason: ${MODIFIED[*]}")
  emit not_accepted motion "$MOTION"
  exit 0
fi


# The second abstention. The motion is a fact about the repair and stands on its own, so it is read
# and reported even here; what is missing is the other half of the decision.
if [ "$SUITE" = "not_run" ]; then
  REASONS+=("--suite was not_run, so there is no suite result to weigh")
  emit cannot_judge none "$MOTION"
  exit 0
fi

# --- the matrix (deterministic) -----------------------------------------------
if [ "${#MODIFIED[@]}" -gt 0 ]; then
  REASONS+=("a test file was modified and the caller stated a reason: $MOD_REASON")
fi
if [ "${#ADDED[@]}" -gt 0 ] || [ "${#DELETED[@]}" -gt 0 ]; then
  REASONS+=("test paths were added or deleted, neither of which demands a reason")
fi

if [ "$SUITE" = "red" ]; then
  REASONS+=("the suite was red over the repaired tree")
  emit not_accepted suite_and_motion "$MOTION"
  exit 0
fi

REASONS+=("the suite was green and the test motion raised nothing unanswered")
emit accepted suite_and_motion "$MOTION"
exit 0
