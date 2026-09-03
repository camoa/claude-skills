#!/usr/bin/env bash
# Behavioral spec for scripts/repair-accept-check.sh.
#
# WRITTEN BEFORE THE IMPLEMENTATION, FROM THE CONTRACT, NOT FROM THE CODE. Every assertion below
# carries, as a comment, the requirement sentence it encodes. Nothing here was derived by reading an
# implementation, because there is no implementation to read: scripts/repair-accept-check.sh does
# not exist when this file is written, and this spec is red for that reason.
#
# WHY THAT ORDERING MATTERS. A test written from finished code ratifies whatever the code happens to
# do. It agrees with every bug the code already has, and it has no opinion about the scope the code
# was supposed to cover, because it never saw a requirement that the code missed. A spec written
# from the contract first can be wrong about the contract, which is a thing a reader can argue with.
# It cannot be silently shaped by the answer.
#
# WHAT THE KERNEL IS. The deterministic accept path for a repair: it decides accepted /
# not_accepted / cannot_judge from a suite result plus the test motion a repair made, with no model
# anywhere in the decision. It SURFACES, never halts, so blocks is false in every outcome.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/repair-accept-check.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# mkns <name> <name-status line>...   writes a git --name-status file, prints its path.
# %b so the \t separators in the lines below are real tabs.
mkns(){
  local name="$1"; shift
  : > "$TMP/$name.tsv"
  local l
  for l in "$@"; do printf '%b\n' "$l" >> "$TMP/$name.tsv"; done
  printf '%s' "$TMP/$name.tsv"
}

# q <label> <jq filter> <expected> -- <kernel args...>
q(){
  local label="$1" filter="$2" expected="$3"; shift 3
  local out v
  out="$(bash "$K" "$@" 2>/dev/null)"
  v="$(jq -r "$filter" <<<"$out" 2>/dev/null)"
  [ "$v" = "$expected" ] && ok || no "$label: got '$v' want '$expected'  raw=$out"
}

# bad <label> <kernel args...>   fail-closed: exit 2 and NOTHING on stdout.
bad(){
  local label="$1"; shift
  local out ec
  if [ "$#" -eq 0 ]; then out="$(bash "$K" 2>/dev/null)"; ec=$?
  else out="$(bash "$K" "$@" 2>/dev/null)"; ec=$?; fi
  { [ "$ec" -eq 2 ] && [ -z "$out" ]; } && ok || no "$label: exit=$ec stdout='$out' (want exit 2, empty stdout)"
}

GLOBS='["tests/*.sh","**/test_*.py"]'

EMPTY="$(mkns empty)"                                             # a ZERO-BYTE file: no diff read
NOTEST="$(mkns notest 'M\tsrc/only_source.php')"                   # motion, none of it a test path
MODTEST="$(mkns modtest 'M\ttests/accept_test.sh')"
ADDTEST="$(mkns addtest 'A\ttests/new_test.sh' 'A\ttests/other_test.sh')"
DELTEST="$(mkns deltest 'D\ttests/old_test.sh')"
MODSRC="$(mkns modsrc 'M\tscripts/repair-accept-check.sh')"
RENTEST="$(mkns rentest 'R100\ttests/old_test.sh\ttests/new_test.sh')"
COPYTEST="$(mkns copytest 'C100\ttests/a_test.sh\ttests/b_test.sh')"
MIX="$(mkns mix 'M\ttests/x_test.sh' 'M\tscripts/thing.sh')"
MODPY="$(mkns modpy 'M\tsrc/pkg/test_x.py')"
GHOST="$(mkns ghost 'M\ttests/ghost_never_created.sh')"

# --- glob-source (review_ladder): the recipes' `**` globs work through THIS kernel, and the origin is recorded ---
DRUPAL="$(mkns drupal 'M\ttests/src/Kernel/FooTest.php')"
GO="$(mkns go 'M\tmain_test.go')"
q "** glob: **/tests/**/*Test.php matches tests/src/Kernel/FooTest.php (modified, no reason -> not_accepted)" .action not_accepted \
  --suite green --test-motion-from "$DRUPAL" --test-globs '["**/tests/**/*Test.php"]'
q "** glob: **/*_test.go matches main_test.go at the root" .action not_accepted \
  --suite green --test-motion-from "$GO" --test-globs '["**/*_test.go"]'
q "* stays one segment: tests/*.php does not reach tests/src/Kernel/FooTest.php" '.motion.modified | length' 0 \
  --suite green --test-motion-from "$DRUPAL" --test-globs '["tests/*.php"]'
q "origin recorded: recipe" .test_globs_origin recipe \
  --suite green --test-motion-from "$ADDTEST" --test-globs "$GLOBS" --test-globs-origin recipe
q "origin recorded: convention" .test_globs_origin convention \
  --suite green --test-motion-from "$ADDTEST" --test-globs "$GLOBS" --test-globs-origin convention
q "origin absent: null, never a string" .test_globs_origin null \
  --suite green --test-motion-from "$ADDTEST" --test-globs "$GLOBS"
bad "origin outside the enum" --suite green --test-motion-from "$ADDTEST" --test-globs "$GLOBS" --test-globs-origin guess

DELPHP="$(mkns delphp 'D\ttests/src/Kernel/FooTest.php')"
q "metacharacter in a recipe glob is literal: [ does not swallow the deletion" '.motion.deleted | length' 0 \
  --suite green --test-motion-from "$DELPHP" --test-globs '["**/tests/**/*Test.php["]'
q "control: the same glob without the bracket lists the deletion" '.motion.deleted | length' 1 \
  --suite green --test-motion-from "$DELPHP" --test-globs '["**/tests/**/*Test.php"]'
q "| in a recipe glob is literal: a source file is not a modified test" '.motion.modified | length' 0 \
  --suite green --test-motion-from "$MODSRC" --test-globs '["a|b"]'

q "not_run still surfaces a modified test with no reason (motion-wiring)" .action not_accepted \
  --suite not_run --test-motion-from "$MODTEST" --test-globs "$GLOBS"
# The motion settles this ahead of the not_run abstention, and that is the honest answer rather
# than the merely safe one: cannot_judge means "I could not look", and here we DID look and saw a
# modified test. Before the reason stopped clearing the halt, this same input returned cannot_judge
# only because the reason let it fall through to the suite half.
q "not_run with a reason is decided by the motion, not abstained on" .action not_accepted \
  --suite not_run --test-motion-from "$MODTEST" --test-globs "$GLOBS" --modification-reason "x"

# --- R1: "A repair that MODIFIES a test halts for a stated reason, while one that only adds or
#          only deletes passes silently." ---
q "R1 modified test, no reason -> not_accepted" .action not_accepted \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS"
# THIS CELL ASSERTED THE LOOPHOLE. It required that a stated reason ACCEPT the modification, which
# made the reason a permit the builder issues to itself: the same party writes the change and the
# justification that closes it. A repair loop whose subject may edit the standard always converges,
# because the work can move the goalposts instead of meeting them. The reason is still recorded and
# still reaches review; it no longer decides. Nothing here judges the test -- the motion is the
# subject, which is what the contract's non-goal requires.
q "R1 modified test WITH a reason -> not_accepted, the reason is recorded not spent" .action not_accepted \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS" \
  --modification-reason "the test asserted the inverse"
q "the stated reason survives into reasons[] rather than being dropped with the acceptance" \
  '.reasons | join(" ") | test("the test asserted the inverse")' true \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS" \
  --modification-reason "the test asserted the inverse"
q "R1 only ADDED test paths -> accepted" .action accepted \
  --suite green --test-motion-from "$ADDTEST" --test-globs "$GLOBS"
q "R1 only DELETED test paths -> accepted" .action accepted \
  --suite green --test-motion-from "$DELTEST" --test-globs "$GLOBS"
q "R1 modified NON-test path (matches no glob) -> accepted" .action accepted \
  --suite green --test-motion-from "$MODSRC" --test-globs "$GLOBS"

# --- R2: "A repair is accepted by running the existing suite ... with no model in the accept
#          path." The suite result alone decides when there is no test motion to weigh. ---
q "R2 red suite, no test motion -> not_accepted" .action not_accepted \
  --suite red --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "R2 green suite, no test motion -> accepted" .action accepted \
  --suite green --test-motion-from "$NOTEST" --test-globs "$GLOBS"

# --- R3: "The kernel says plainly what it could not check, and that answer is distinct from a
#          pass." ---
q "R3 suite not_run -> cannot_judge" .action cannot_judge \
  --suite not_run --test-motion-from "$NOTEST" --test-globs "$GLOBS"
# The same case stated as the prohibition, because a kernel that folds "I could not look" into a
# pass is the exact defect this field exists to prevent.
NOTRUN_ACTION="$(bash "$K" --suite not_run --test-motion-from "$NOTEST" --test-globs "$GLOBS" 2>/dev/null | jq -r '.action' 2>/dev/null)"
# The action has to BE one of the three verdicts as well as not being `accepted`: a bare
# not-equal test passes on empty output, which is what a missing kernel produces.
case "$NOTRUN_ACTION" in
  not_accepted|cannot_judge) ok ;;
  *) no "R3 not_run must NEVER be accepted and must still name a verdict, got '$NOTRUN_ACTION'" ;;
esac
q "R3 empty globs + source undetermined -> cannot_judge" .action cannot_judge \
  --suite green --test-motion-from "$MODTEST" --test-globs '[]' --test-globs-source undetermined
# "an empty glob list determined by the caller means 'no test paths here', which is a real answer"
q "R3 empty globs + source determined + green -> accepted" .action accepted \
  --suite green --test-motion-from "$MODTEST" --test-globs '[]' --test-globs-source determined
# An OMITTED source is not a caller's assertion. Found by Phase 4 2026-09-03: this cell asserted
# `accepted`, so `--test-globs '[]'` with no source flag classified nothing, left every motion array
# empty, and still returned "the test motion raised nothing unanswered" over a MODIFIED test file.
# That is a positive claim about a comparison that never ran, and it switched off the whole halt.
# Absence gets its own answer; only an explicit `determined` makes an empty list mean something.
q "R3 empty globs + source omitted -> cannot_judge, absence is not an assertion" .action cannot_judge \
  --suite green --test-motion-from "$MODTEST" --test-globs '[]'
q "R3 empty globs + source omitted names the empty list, not the suite" \
  '[.reasons[] | select(test("empty"))] | length > 0' true \
  --suite green --test-motion-from "$MODTEST" --test-globs '[]'
q "R3 empty globs + source omitted carries decided_by none" .decided_by none \
  --suite green --test-motion-from "$MODTEST" --test-globs '[]'
# The exclusion, so the rule above cannot be satisfied by refusing everything: a NON-empty glob list
# with no source flag is still a determination, and still decides.
q "R3 non-empty globs + source omitted still decides" .action not_accepted \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS"
# "every cannot_judge result carries decided_by 'none' and a non-empty reasons[]"
q "R3 not_run cannot_judge carries decided_by none" .decided_by none \
  --suite not_run --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "R3 undetermined-globs cannot_judge carries decided_by none" .decided_by none \
  --suite green --test-motion-from "$MODTEST" --test-globs '[]' --test-globs-source undetermined
# reasons[] on cannot_judge is "the only place the caller learns which of the three abstentions
# fired", so a non-empty array is not enough to satisfy it: each abstention has to NAME its own
# cause and stay silent about the other. A kernel emitting one constant sentence everywhere is
# non-empty in both and tells the caller nothing. Matched as a SUBSTRING on the contract's own
# vocabulary for the two causes (`not_run`, `undetermined`), never on a whole sentence, so a
# rewording that changes no behaviour does not fail here.
q "R3 not_run cannot_judge names not_run as its cause" '.reasons | join(" ") | test("not_run")' true \
  --suite not_run --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "R3 not_run cannot_judge does not name the other abstention" '.reasons | join(" ") | test("undetermined")' false \
  --suite not_run --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "R3 undetermined-globs cannot_judge names undetermined as its cause" '.reasons | join(" ") | test("undetermined")' true \
  --suite green --test-motion-from "$MODTEST" --test-globs '[]' --test-globs-source undetermined
q "R3 undetermined-globs cannot_judge does not name the other abstention" '.reasons | join(" ") | test("not_run")' false \
  --suite green --test-motion-from "$MODTEST" --test-globs '[]' --test-globs-source undetermined
# Stated once more as the whole-field comparison, because the two per-cause assertions above could
# both hold on a kernel that concatenated both sentences into every abstention.
CJ_NOTRUN="$(bash "$K" --suite not_run --test-motion-from "$NOTEST" --test-globs "$GLOBS" 2>/dev/null | jq -r '.reasons | join(" ")' 2>/dev/null)"
CJ_UNDET="$(bash "$K" --suite green --test-motion-from "$MODTEST" --test-globs '[]' --test-globs-source undetermined 2>/dev/null | jq -r '.reasons | join(" ")' 2>/dev/null)"
{ [ -n "$CJ_NOTRUN" ] && [ -n "$CJ_UNDET" ] && [ "$CJ_NOTRUN" != "$CJ_UNDET" ]; } && ok \
  || no "R3 the two cannot_judge reasons must differ: not_run='$CJ_NOTRUN' undetermined='$CJ_UNDET'"

# --- R3b: "A diff the kernel cannot read returns its own verdict and never `accepted`." A file of
#          ZERO BYTES is such a diff. It carries no claim: a caller who established there are no
#          test paths says so with `--test-globs '[]'`, and one who could not establish it says so
#          with `--test-globs-source undetermined`, so what is left is a diff that was never
#          computed or a repair that changed nothing. The wiring in commands/implement.md handed
#          `git diff` a checkpoint LABEL instead of a sha; git exited 128 after the shell redirect
#          had already created the file, and every repair on every real build read as `accepted`
#          off a comparison that never happened. The third abstention, and the reason the first two
#          were not enough. ---
q "R3b a zero-byte motion file -> cannot_judge" .action cannot_judge \
  --suite green --test-motion-from "$EMPTY" --test-globs "$GLOBS"
# The abstention is answered BEFORE the matrix, so the suite result cannot turn it into a decided
# outcome in either direction. A red suite here would otherwise read as not_accepted for the right
# verdict and the wrong reason, and the caller would never learn the diff was missing.
q "R3b a zero-byte motion file abstains even on a red suite" .action cannot_judge \
  --suite red --test-motion-from "$EMPTY" --test-globs "$GLOBS"
q "R3b zero-byte cannot_judge carries decided_by none" .decided_by none \
  --suite green --test-motion-from "$EMPTY" --test-globs "$GLOBS"
q "R3b zero-byte cannot_judge still reports all three motion arrays, empty" \
  '[(.motion.added|length),(.motion.deleted|length),(.motion.modified|length)] | join(",")' '0,0,0' \
  --suite green --test-motion-from "$EMPTY" --test-globs "$GLOBS"
q "R3b zero-byte cannot_judge names the empty file as its cause" \
  '.reasons | join(" ") | test("zero bytes")' true \
  --suite green --test-motion-from "$EMPTY" --test-globs "$GLOBS"
q "R3b zero-byte cannot_judge names neither of the other two abstentions" \
  '.reasons | join(" ") | test("not_run|undetermined")' false \
  --suite green --test-motion-from "$EMPTY" --test-globs "$GLOBS"
q "R3b blocks is false on the zero-byte abstention too" .blocks false \
  --suite green --test-motion-from "$EMPTY" --test-globs "$GLOBS"
# Two abstentions at once. The empty file is answered first, deliberately: it is a fact about the
# input rather than about what the caller knows, and it is the more diagnostic of the pair.
q "R3b an empty file beside undetermined globs reports the empty file" \
  '.reasons | join(" ") | test("zero bytes")' true \
  --suite green --test-motion-from "$EMPTY" --test-globs '[]' --test-globs-source undetermined
# All three abstention reasons differ, for the same reason the first two must.
CJ_EMPTY="$(bash "$K" --suite green --test-motion-from "$EMPTY" --test-globs "$GLOBS" 2>/dev/null | jq -r '.reasons | join(" ")' 2>/dev/null)"
{ [ -n "$CJ_EMPTY" ] && [ "$CJ_EMPTY" != "$CJ_NOTRUN" ] && [ "$CJ_EMPTY" != "$CJ_UNDET" ]; } && ok \
  || no "R3b the zero-byte reason must differ from both others: empty='$CJ_EMPTY'"

# --- R4: "Fail-closed on bad input, matching the sibling scripts/repair-scope-check.sh exactly:
#          a missing required flag, an unknown flag, an out-of-enum --suite value, an unreadable
#          --test-motion-from path, a --test-globs value that is not a JSON array: each exits 2
#          with NOTHING on stdout." ---
bad "R4 no args at all"
bad "R4 missing --test-motion-from and --test-globs" --suite green
bad "R4 missing --test-globs" --suite green --test-motion-from "$NOTEST"
bad "R4 missing --suite" --test-motion-from "$NOTEST" --test-globs "$GLOBS"
bad "R4 unknown flag" --suite green --test-motion-from "$NOTEST" --test-globs "$GLOBS" --bogus x
bad "R4 out-of-enum --suite" --suite maybe --test-motion-from "$NOTEST" --test-globs "$GLOBS"
bad "R4 unreadable --test-motion-from path" --suite green --test-motion-from "$TMP/does-not-exist.tsv" --test-globs "$GLOBS"
bad "R4 --test-globs is a JSON object, not an array" --suite green --test-motion-from "$NOTEST" --test-globs '{"not":"an array"}'
bad "R4 --test-globs is not JSON at all" --suite green --test-motion-from "$NOTEST" --test-globs 'tests/*.sh'
bad "R4 --suite with no value at all" --test-motion-from "$NOTEST" --test-globs "$GLOBS" --suite
# Sibling parity: repair-scope-check.sh rejects an out-of-enum source value the same way.
bad "R4 out-of-enum --test-globs-source" --suite green --test-motion-from "$NOTEST" --test-globs "$GLOBS" --test-globs-source perhaps
# "a flag whose value looks like another flag (e.g. `--suite --test-globs`) exits 2 rather than
# silently consuming it"
bad "R4 flag consumed as a value" --suite --test-globs --test-motion-from "$NOTEST"
# "An empty string is not a reason and is rejected as a bad argument." OMITTING the flag and
# PASSING it blank are different statements: the first says there is no reason and is answered
# not_accepted, the second says here is my reason and hands over nothing. Rejecting the second is
# the only way a caller who meant to write one finds out they did not. Whitespace goes with it,
# because the gate that reads this reason back off the record trims before it decides, so a blank
# accepted here would be rejected there.
bad "R4 --modification-reason passed as an empty string" \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS" --modification-reason ""
bad "R4 --modification-reason passed as whitespace only" \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS" --modification-reason "   "

# --- R5: "Rename and copy normalisation, from the name-status format." ---
# "R100\told_test.php\tnew_test.php is treated as old DELETED and new ADDED, not as a modification"
q "R5 rename -> old deleted, new added" \
  '(.motion.deleted|sort|join(",")) + "|" + (.motion.added|sort|join(","))' \
  'tests/old_test.sh|tests/new_test.sh' \
  --suite green --test-motion-from "$RENTEST" --test-globs "$GLOBS"
# Counted, not joined: an expected empty string would also match a kernel that emitted nothing at
# all, so an absent implementation would read as a pass here.
q "R5 rename is NOT a modification" '"n=" + (.motion.modified | length | tostring)' 'n=0' \
  --suite green --test-motion-from "$RENTEST" --test-globs "$GLOBS"
# "C100\ta.php\tb.php is treated as b ADDED only; a is untouched"
q "R5 copy -> destination added" '.motion.added | join(",")' 'tests/b_test.sh' \
  --suite green --test-motion-from "$COPYTEST" --test-globs "$GLOBS"
q "R5 copy -> source appears in no array" \
  '[.motion.added[], .motion.deleted[], .motion.modified[]] | map(select(. == "tests/a_test.sh")) | length' '0' \
  --suite green --test-motion-from "$COPYTEST" --test-globs "$GLOBS"
# "a rename of a test file with no --modification-reason must therefore be accepted, because a
# rename is an add plus a delete and neither demands a reason"
q "R5 renamed test, no reason -> accepted" .action accepted \
  --suite green --test-motion-from "$RENTEST" --test-globs "$GLOBS"

# --- R6: "blocks is always false, in every outcome including not_accepted." ---
q "R6 blocks false on accepted" .blocks false \
  --suite green --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "R6 blocks false on not_accepted" .blocks false \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS"
q "R6 blocks false on cannot_judge" .blocks false \
  --suite not_run --test-motion-from "$NOTEST" --test-globs "$GLOBS"

# --- R7: "The motion object always reports the three arrays, even when empty, and lists only paths
#          matching --test-globs." ---
q "R7 all three arrays present with no test motion at all" \
  '[(.motion.added|type),(.motion.deleted|type),(.motion.modified|type)] | join(",")' 'array,array,array' \
  --suite green --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "R7 a non-matching path is listed nowhere" '"n=" + (.motion.modified | length | tostring)' 'n=0' \
  --suite green --test-motion-from "$MODSRC" --test-globs "$GLOBS"
q "R7 mixed motion lists only the glob-matching path" '.motion.modified | join(",")' 'tests/x_test.sh' \
  --suite green --test-motion-from "$MIX" --test-globs "$GLOBS"

# --- decided_by: a decided outcome names WHICH fact decided it. `motion` = the test-motion tripwire
#     settled it whatever the suite said; `suite_and_motion` = both facts were weighed, the motion
#     raised nothing unanswered, and the suite result carried the answer; `none` is reserved for
#     cannot_judge. Every cell below pins one exact value. A pattern admitting either decided value
#     would pass against a kernel that emitted one of them for every outcome and never drew the
#     distinction, which is the whole informational content of the field. ---
q "accepted on a green suite with no test motion is decided by suite_and_motion" .decided_by suite_and_motion \
  --suite green --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "not_accepted on a red suite with no test motion is decided by suite_and_motion" .decided_by suite_and_motion \
  --suite red --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "not_accepted on a modified test with no reason is decided by motion" .decided_by motion \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS"
# "whatever the suite said." The same modification against a RED suite is still decided by motion.
# This is the one cell where both facts point at not_accepted, so decided_by is the only thing that
# says which of them settled it.
q "a modified test with no reason is decided by motion even when the suite is red" .decided_by motion \
  --suite red --test-motion-from "$MODTEST" --test-globs "$GLOBS"
# A stated reason no longer answers the motion, so the motion decides whether or not one was
# given. Same motion as the cell above, SAME decider -- which is the point: the reason cannot move
# the decision from the motion to the suite.
q "a modified test WITH a reason is still decided by motion" .decided_by motion \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS" \
  --modification-reason "the test asserted the inverse"

# --- reasons[] on a DECIDED outcome: "plain sentences for what drove the action". The contract
#     states each action's cause in its own words (accepted = the suite was GREEN and the motion
#     raised nothing unanswered; not_accepted = the suite was RED, or a test file was MODIFIED with
#     no --modification-reason), so an outcome whose reasons[] does not name its cause has not said
#     what drove it. Substrings of that vocabulary, never whole sentences. ---
q "accepted carries a non-empty reasons[]" '.reasons | length > 0' true \
  --suite green --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "accepted names the green suite as its cause" '.reasons | join(" ") | test("green")' true \
  --suite green --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "not_accepted on a modified test carries a non-empty reasons[]" '.reasons | length > 0' true \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS"
q "not_accepted on a modified test names the modification as its cause" '.reasons | join(" ") | test("modif")' true \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS"
q "not_accepted on a red suite names the red suite as its cause" '.reasons | join(" ") | test("red")' true \
  --suite red --test-motion-from "$NOTEST" --test-globs "$GLOBS"
# The two not_accepted causes are distinct, so their reasons must be too, for the same reason the
# two cannot_judge abstentions must be.
NA_MOD="$(bash "$K" --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS" 2>/dev/null | jq -r '.reasons | join(" ")' 2>/dev/null)"
NA_RED="$(bash "$K" --suite red --test-motion-from "$NOTEST" --test-globs "$GLOBS" 2>/dev/null | jq -r '.reasons | join(" ")' 2>/dev/null)"
{ [ -n "$NA_MOD" ] && [ -n "$NA_RED" ] && [ "$NA_MOD" != "$NA_RED" ]; } && ok \
  || no "the two not_accepted reasons must differ: modified='$NA_MOD' red='$NA_RED'"

# --- suite is echoed back, so a reader of the JSON never has to reconstruct the input ---
q "suite echoes green" .suite green --suite green --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "suite echoes red"   .suite red   --suite red   --test-motion-from "$NOTEST" --test-globs "$GLOBS"
q "suite echoes not_run" .suite not_run --suite not_run --test-motion-from "$NOTEST" --test-globs "$GLOBS"

# --- "Glob matching uses bash `case` pattern matching, no filesystem globbing." ---
q "glob tests/*.sh matches" '.motion.modified | join(",")' 'tests/accept_test.sh' \
  --suite green --test-motion-from "$MODTEST" --test-globs "$GLOBS"
q "glob **/test_*.py matches a nested path" '.motion.modified | join(",")' 'src/pkg/test_x.py' \
  --suite green --test-motion-from "$MODPY" --test-globs "$GLOBS"
# No filesystem globbing: none of these paths exist on disk, and the match must not care. A kernel
# that expanded the pattern against the working directory would list nothing here.
q "a path matching a glob but absent from disk still counts" '.motion.modified | join(",")' 'tests/ghost_never_created.sh' \
  --suite green --test-motion-from "$GHOST" --test-globs "$GLOBS"

# --- a spec that checked nothing has not passed ---
# 83 = 12 glob-source + 6 R1 + 2 R2 + 12 R3 + 9 R3b + 14 R4 + 5 R5 + 3 R6 + 3 R7 + 5 decided_by + 6 reasons
#      R1 gained one when the stated reason stopped accepting the modification: the halt and the
#      survival of the reason into reasons[] are two different claims and each can fail alone.
#      + 3 suite-echo + 3 glob.
# Asserted rather than trusted: a block that fails to run, or a helper that returns early, subtracts
# assertions silently and the run still prints "0 failed", which reads as green.
EXPECTED=86
TOTAL=$((PASS + FAIL))
[ "$TOTAL" -eq "$EXPECTED" ] && ok || no "expected $EXPECTED assertions, ran $TOTAL (a skipped block reads as green)"

echo "----"; echo "repair-accept-check-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
