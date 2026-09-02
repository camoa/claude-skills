#!/usr/bin/env bash
# Behavioral spec for the two things scripts/wo-critique-aggregate.sh reads off a finding BESIDES
# its severity: the declared `extends` link (D7 of
# ../../projects/ai_dev_assistant/.../finding_contract/design/finding-contract.md) and the
# component-range check (`--component-files-from`, the criterion added to that task 2026-09-01).
#
# WHY A SEPARATE FILE, not more cells in finding-shape-spec.sh. That spec states its own scope in
# its header — "the NEW behavior only: shape_check() and its two consequences" — and every one of
# its 27 cells goes through run_shape(), a helper that writes exactly ONE critic file and reads
# exactly one merged critics[0] entry. Neither mechanism here fits that shape: `extends` resolves
# ACROSS critic files, so a one-file helper cannot express it, and the range check is asserted on
# `blocking` and on two top-level envelope fields rather than on a per-critic verdict. Bolting both
# onto run_shape() would mean widening the helper, re-scoping the header and moving that spec's
# assertion-count guard, to end up with one file testing three unrelated rules.
#
# The load-bearing cells:
#   - an out-of-range critical does NOT make blocking true; the SAME finding in range DOES. That
#     pair is the criterion ("opens no round") and is the mutation the build report records.
#   - a file whose verdict is `critical` and whose only finding is out of range does not block;
#     add ONE in-range finding and it blocks again. The verdict is dropped only when it summarises
#     nothing that survived, which is what agents/wo-critic.md defines a verdict to be.
#   - a verdict with NO findings is never dropped: it names no site, so no range can judge it.
#   - THE FLAG ABSENT IS ITS OWN VALUE. `range_check.status:"not_run"` with a reason, and an empty
#     `out_of_range[]` that must not be readable as "every finding was in range". Absent, unreadable
#     and empty-list each get their own reason, and none of them suppresses anything.
#   - what cannot be judged is not out of range: no where[], or a where[] entry whose `file` is not
#     a string, leaves the finding contributing exactly as before.
#   - comparison is LITERAL: "./src/A.php" is not "src/A.php". Same posture as repair-scope-check.sh.
#   - `extends` resolves across files, appends deduplicated, marks the REFERENCED finding
#     under_enumerated, and records failure with a reason for an unknown id and for a self-link.
#   - the explicit NON-GOAL is asserted too: an extending finding still contributes to severity, so
#     a critical that extends a concern still blocks. This child records the link, it does not
#     control the loop, and a cell that would pass if it did is the only way to keep that true.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
KERNEL="$ROOT/scripts/wo-critique-aggregate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
WO="wo-01"

newdir() { mktemp -d "$TMP/cd.XXXX"; }
critic() { printf '%s' "$3" > "$1/${WO}.critic-$2.json"; }   # dir, k, body
rangef() { local f; f="$(mktemp "$TMP/range.XXXX")"; printf '%s\n' "$@" > "$f"; echo "$f"; }
run()    { bash "$KERNEL" --wo "$WO" --mode fanout --evaluated true "$@"; }
ok()     { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: got '$3' want '$2'"; fi; }

# A finding template: severity, sites, id, and an optional extends. Every field shape_check
# requires at schema_version 2.0 is present, so a cell that goes red went red for ITS OWN reason and
# not because the shape check fired on a fixture missing a remedy.
f() { # $1 severity  $2 id  $3 json array of where entries  [$4 extends]
  jq -nc --arg s "$1" --arg i "$2" --argjson w "$3" --arg e "${4:-}" \
    '{severity:$s, text:"x", where:$w, remedy:"fix", id:$i} + (if $e=="" then {} else {extends:$e} end)'
}
filev() { # $1 the file's own verdict, $2.. findings -> a schema_version 2.0 critic file body
  local v="$1"; shift
  jq -nc --arg v "$v" --argjson fs "$(jq -sc '.' <<<"$*")" \
    '{lens:"correctness", schema_version:2.0, verdict:$v, findings:$fs}'
}
file2() { filev pass "$@"; }

# =============================================================================
# c5 — a build finding is a defect in the slice's own code
# =============================================================================

# R1/R2 THE CRITERION, as a pair that differs only in the range file. Same critic file, same
# severity, same tier, same --required. Out of range: blocking false and the finding is handed to
# review in out_of_range[]. In range: blocking true. A mechanism that recorded the flag without
# suppressing the severity would pass R1's first assertion and fail its second.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 '[{"file":"other/Z.php","line":9}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R1 out-of-range critical: blocking"        "false"    "$(jq -r '.blocking' <<<"$out")"
ok "R1 out-of-range critical: overall"         "pass"     "$(jq -r '.overall' <<<"$out")"
ok "R1 the finding is handed to review"        "f1"       "$(jq -r '.out_of_range[0].id' <<<"$out")"
ok "R1 with its sites, so review can act"      "other/Z.php" "$(jq -r '.out_of_range[0].where[0].file' <<<"$out")"
ok "R1 and is marked on the critic entry"      "true"     "$(jq -r '.critics[0].findings[0].out_of_range' <<<"$out")"
ok "R1 range_check says a comparison was made" "ran sets" "$(jq -r '.range_check | .status+" "+.decided_by' <<<"$out")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef other/Z.php)")"
ok "R2 the SAME finding in range: blocking"    "true"     "$(jq -r '.blocking' <<<"$out")"
ok "R2 in range: nothing handed to review"     "0"        "$(jq -r '.out_of_range | length' <<<"$out")"
ok "R2 in range: no finding is marked"         "null"     "$(jq -r '.critics[0].findings[0].out_of_range' <<<"$out")"

# R3 the realistic shape: a critic that files an out-of-range critical writes verdict "critical"
# too (agents/wo-critic.md: "the kernel takes the worst severity across your findings and lifts your
# whole verdict to it"). If the verdict survived, the round would open anyway and this whole
# criterion would be a recorded flag with no effect on the loop.
d="$(newdir)"; critic "$d" 1 "$(filev critical "$(f critical f1 '[{"file":"other/Z.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R3 verdict critical, only finding out of range: blocking" "false" "$(jq -r '.blocking' <<<"$out")"

# R4 fail-closed direction: ONE in-range finding and the verdict stands untouched. The verdict is
# dropped because it summarises nothing that survived, never because a range file was passed.
d="$(newdir)"; critic "$d" 1 "$(filev critical "$(f critical f1 '[{"file":"other/Z.php"}]')" "$(f concern f2 '[{"file":"src/A.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R4 one in-range finding: verdict stands, blocking" "true" "$(jq -r '.blocking' <<<"$out")"
ok "R4 the out-of-range one is still handed to review" "f1"  "$(jq -r '.out_of_range[0].id' <<<"$out")"

# R5 a verdict with no findings at all is never dropped: it names no site, so no range can judge it.
d="$(newdir)"; critic "$d" 1 '{"lens":"correctness","schema_version":2.0,"verdict":"critical","findings":[]}'
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R5 verdict-only critical is not suppressed" "true" "$(jq -r '.blocking' <<<"$out")"

# R6 EVERY site must be outside. One site in the range and the finding is in range, whole.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 '[{"file":"other/Z.php"},{"file":"src/A.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R6 one site inside: in range, blocking"   "true" "$(jq -r '.blocking' <<<"$out")"
ok "R6 one site inside: not handed to review" "0"    "$(jq -r '.out_of_range | length' <<<"$out")"

# R7/R8 what cannot be judged is NOT out of range. A finding with no where[] (pre-contract file, so
# shape_check does not fire on it) and a where[] entry whose `file` is not a string both keep
# contributing exactly as before. Reading either as "outside the range" would suppress a finding on
# the strength of a field nobody could read.
d="$(newdir)"; critic "$d" 1 '{"lens":"correctness","verdict":"pass","findings":[{"severity":"critical","text":"x"}]}'
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R7 no where[]: still blocks"              "true" "$(jq -r '.blocking' <<<"$out")"
ok "R7 no where[]: not handed to review"      "0"    "$(jq -r '.out_of_range | length' <<<"$out")"
d="$(newdir)"; critic "$d" 1 '{"lens":"correctness","verdict":"pass","findings":[{"severity":"critical","text":"x","where":[{"file":123}]}]}'
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R8 where[].file is not a string: still blocks" "true" "$(jq -r '.blocking' <<<"$out")"

# R9 THE ABSENT FLAG IS ITS OWN VALUE. Not "every finding was in range": a status and a reason, and
# nothing suppressed. This repo has shipped a false all-clear from exactly this shape three times.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 '[{"file":"other/Z.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
ok "R9 flag absent: status"                 "not_run" "$(jq -r '.range_check.status' <<<"$out")"
ok "R9 flag absent: decided_by"             "none"    "$(jq -r '.range_check.decided_by' <<<"$out")"
ok "R9 flag absent: a reason naming the flag" "yes"   "$(jq -r 'if (.range_check.reason // "") | test("component-files-from") then "yes" else "no: \(.range_check.reason)" end' <<<"$out")"
ok "R9 flag absent: nothing is suppressed"  "true"    "$(jq -r '.blocking' <<<"$out")"
ok "R9 flag absent: out_of_range is empty and means nothing" "0" "$(jq -r '.out_of_range | length' <<<"$out")"

# R10 a path that does not exist is not_run WITH THE PATH in the reason, not a silent clean run.
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$TMP/no-such-file.txt")"
ok "R10 unreadable list: status"      "not_run" "$(jq -r '.range_check.status' <<<"$out")"
ok "R10 unreadable list: names the path" "yes"  "$(jq -r 'if (.range_check.reason // "") | test("no-such-file") then "yes" else "no: \(.range_check.reason)" end' <<<"$out")"
ok "R10 unreadable list: nothing suppressed" "true" "$(jq -r '.blocking' <<<"$out")"

# R11 an EMPTY list is not "the range is nothing, so everything is outside it" — that would suppress
# every sited finding in the run. It is not_run with its own reason.
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef '')")"
ok "R11 empty list: status"                  "not_run" "$(jq -r '.range_check.status' <<<"$out")"
ok "R11 empty list: says it was empty"       "yes"     "$(jq -r 'if (.range_check.reason // "") | test("empty") then "yes" else "no: \(.range_check.reason)" end' <<<"$out")"
ok "R11 empty list: suppresses nothing"      "true"    "$(jq -r '.blocking' <<<"$out")"

# R12 a flag-shaped value is refused AND the flag it swallowed is still parsed: --required has to
# survive. The kernel always emits an envelope, so this is not_run rather than an exit 2.
out="$(bash "$KERNEL" --wo "$WO" --mode fanout --evaluated true --tier low --expected 1 --critics-dir "$d" --component-files-from --required)"
ok "R12 flag-shaped value: status"           "not_run" "$(jq -r '.range_check.status' <<<"$out")"
ok "R12 flag-shaped value: --required survived" "true" "$(jq -r '.required' <<<"$out")"

# R13 comparison is LITERAL. "./src/A.php" and "src/A.php" are different paths here, the same way
# repair-scope-check.sh treats them, and the same way `git diff --name-only` writes them.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 '[{"file":"./src/A.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R13 './src/A.php' vs 'src/A.php': out of range, no normalisation" "false" "$(jq -r '.blocking' <<<"$out")"

# R14 the list is read as one path per line, blank lines dropped and surrounding whitespace trimmed —
# so a range file with a trailing newline and an indented entry still matches.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 '[{"file":"src/A.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef '' '  src/A.php  ' '')")"
ok "R14 blank lines and padding are not part of a path" "true" "$(jq -r '.blocking' <<<"$out")"

# R15-R19 THE DROP IS BOUNDED BY WHAT THE SUPPRESSED FINDINGS ACTUALLY SAID. Dropping the file's own
# verdict is defensible only while that verdict is a summary of findings that were all suppressed.
# agents/wo-critic.md:154-155 defines it as exactly that ("the kernel takes the worst severity across
# your findings and lifts your whole verdict to it") -- but two verdicts are NOT that summary and
# must survive the drop:
#
#   - `unresolved` has an independent meaning. wo-critic.md:218-219: "A finding you could not
#     investigate is `unresolved`, which is a different thing and still blocks." `severity` is
#     concern|critical only, so the file verdict is the ONLY field that signal can live in, and it is
#     not in out_of_range[] either, because that array carries findings. Dropping it turns "I could
#     not settle this" into a clean pass, on the strength of a range comparison that never judged the
#     verdict -- the kernel's own header says a verdict names no site and cannot be judged against a
#     range. Measured before this rule existed: verdict `unresolved` plus one out-of-range concern
#     went from blocking true to blocking false and the signal landed in no decision field.
#   - a verdict RANKING ABOVE every suppressed finding is claiming more than they said, so what it
#     is claiming was never compared to anything. Fail closed and keep it.
#
# The rule is therefore: drop only when the verdict is one of pass|concern|critical AND ranks no
# higher than the worst out-of-range finding. R16 is the case c5 needs and it still drops.

# R15 the signal that has nowhere else to live: could-not-investigate survives the suppression.
d="$(newdir)"; critic "$d" 1 "$(filev unresolved "$(f concern f1 '[{"file":"other/Z.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R15 unresolved over an out-of-range concern: blocking" "true"       "$(jq -r '.blocking' <<<"$out")"
ok "R15 and the signal is still in a decision field"       "unresolved" "$(jq -r '.critics[0].effective' <<<"$out")"
ok "R15 while the finding is still handed to review"       "f1"         "$(jq -r '.out_of_range[0].id' <<<"$out")"

# R16 the case c5 exists for, unchanged: a critic filing an out-of-range critical writes verdict
# critical too, and that verdict summarises nothing that survived. It still drops, so the round does
# not open on the verdict alone.
d="$(newdir)"; critic "$d" 1 "$(filev critical "$(f critical f1 '[{"file":"other/Z.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R16 critical over an out-of-range critical: still dropped" "false" "$(jq -r '.blocking' <<<"$out")"

# R17 the fail-closed direction: a verdict claiming MORE than the suppressed finding said. The range
# check judged a concern; nothing judged the critical, so it stands.
d="$(newdir)"; critic "$d" 1 "$(filev critical "$(f concern f1 '[{"file":"other/Z.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R17 critical over an out-of-range concern: verdict stands, blocking" "true"     "$(jq -r '.blocking' <<<"$out")"
ok "R17 and it reads critical, not pass"                                 "critical" "$(jq -r '.critics[0].effective' <<<"$out")"

# R18 unresolved is never dropped, whatever the suppressed finding ranked. A critic that could not
# investigate is not a critic that found nothing outside the slice.
d="$(newdir)"; critic "$d" 1 "$(filev unresolved "$(f critical f1 '[{"file":"other/Z.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R18 unresolved over an out-of-range critical: blocking" "true"       "$(jq -r '.blocking' <<<"$out")"
ok "R18 and still reads unresolved"                         "unresolved" "$(jq -r '.critics[0].effective' <<<"$out")"

# R19 the ordinary drop is untouched by the narrowing: a rankable verdict equal to the worst
# suppressed finding still goes, so the round does not open on it.
d="$(newdir)"; critic "$d" 1 "$(filev concern "$(f concern f1 '[{"file":"other/Z.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "R19 concern over an out-of-range concern: still dropped" "false" "$(jq -r '.blocking' <<<"$out")"
ok "R19 and the run reads clean"                             "pass"  "$(jq -r '.overall' <<<"$out")"

# =============================================================================
# c3 — under-enumeration is a recorded link
# =============================================================================

# E1 the escaping thread: one finding, two later critics adding a site each. The REFERENCED finding
# collects both sites and is recorded under-enumerated; the extenders record that the link resolved.
d="$(newdir)"
critic "$d" 1 "$(file2 "$(f concern f1 '[{"file":"a.php","line":1}]')")"
critic "$d" 2 "$(file2 "$(f concern f2 '[{"file":"b.php","line":2}]' f1)")"
critic "$d" 3 "$(file2 "$(f concern f3 '[{"file":"c.php","line":3}]' f1)")"
out="$(run --tier high --expected 3 --critics-dir "$d")"
sites() { jq -r --arg i "$1" '[.critics[].findings[] | select(.id==$i) | .where[].file] | join(",")' <<<"$out"; }
ok "E1 sites are appended to the referenced finding" "a.php,b.php,c.php" "$(sites f1)"
ok "E1 the referenced finding is under-enumerated"   "true"  "$(jq -r '[.critics[].findings[] | select(.id=="f1") | .under_enumerated][0]' <<<"$out")"
ok "E1 the extender records the link resolved"       "true"  "$(jq -r '[.critics[].findings[] | select(.id=="f2") | .extends_resolved][0]' <<<"$out")"
ok "E1 an extender is not itself under-enumerated"   "null"  "$(jq -r '[.critics[].findings[] | select(.id=="f2") | .under_enumerated][0]' <<<"$out")"
ok "E1 the extender keeps its own site list"         "b.php" "$(sites f2)"
ok "E1 no site is invented on an unrelated finding"  "c.php" "$(sites f3)"

# E2 append is DEDUPLICATED and order-preserving: an extender naming a site the referenced finding
# already has adds nothing.
d="$(newdir)"
critic "$d" 1 "$(file2 "$(f concern f1 '[{"file":"a.php","line":1}]')")"
critic "$d" 2 "$(file2 "$(f concern f2 '[{"file":"a.php","line":1}]' f1)")"
out="$(run --tier high --expected 2 --critics-dir "$d")"
ok "E2 a duplicate site is not appended twice" "a.php" "$(sites f1)"
ok "E2 the link still resolved"                "true"  "$(jq -r '[.critics[].findings[] | select(.id=="f2") | .extends_resolved][0]' <<<"$out")"

# E3 an id nobody carries is a RECORDED FAILURE naming the id — never silently dropped, and never
# recorded as resolved. Absence of a target is its own answer, not the absence of a problem.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f concern f1 '[{"file":"a.php"}]')" "$(f concern f9 '[{"file":"z.php"}]' ghost)")"
out="$(run --tier high --expected 1 --critics-dir "$d")"
ok "E3 unknown id: resolved is false"        "false" "$(jq -r '[.critics[].findings[] | select(.id=="f9") | .extends_resolved][0]' <<<"$out")"
ok "E3 unknown id: the reason names the id"  "yes"   "$(jq -r '[.critics[].findings[] | select(.id=="f9") | .extends_reason][0] | if test("ghost") then "yes" else "no: \(.)" end' <<<"$out")"
ok "E3 unknown id: nothing was appended anywhere" "a.php" "$(sites f1)"

# E4 a finding extending ITSELF is a failure with its own reason, and does not append its sites to
# itself — a rule that resolved this one would grow a where[] on every run.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f concern f4 '[{"file":"d.php"}]' f4)")"
out="$(run --tier high --expected 1 --critics-dir "$d")"
ok "E4 self-link: resolved is false"          "false" "$(jq -r '[.critics[].findings[] | select(.id=="f4") | .extends_resolved][0]' <<<"$out")"
ok "E4 self-link: the reason says it is its own id" "yes" "$(jq -r '[.critics[].findings[] | select(.id=="f4") | .extends_reason][0] | if test("own id") then "yes" else "no: \(.)" end' <<<"$out")"
ok "E4 self-link: where[] is unchanged"       "d.php" "$(sites f4)"
ok "E4 self-link: not marked under-enumerated" "null" "$(jq -r '[.critics[].findings[] | select(.id=="f4") | .under_enumerated][0]' <<<"$out")"

# E5 a finding that declares no link carries neither key. The two fields are a record of something
# that happened, so a finding they did not happen to must not carry them.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f concern f1 '[{"file":"a.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d")"
ok "E5 no extends: no extends_resolved key"  "null" "$(jq -r '.critics[0].findings[0].extends_resolved' <<<"$out")"
ok "E5 no extends: no under_enumerated key"  "null" "$(jq -r '.critics[0].findings[0].under_enumerated' <<<"$out")"

# E6 order-independent, and it works inside one file: the extender written BEFORE its target still
# resolves. A one-pass implementation that walked the list forward would fail this.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f concern f2 '[{"file":"b.php"}]' f1)" "$(f concern f1 '[{"file":"a.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d")"
ok "E6 extender written first still resolves" "true"        "$(jq -r '.critics[0].findings[0].extends_resolved' <<<"$out")"
ok "E6 and the target still collects the site" "a.php,b.php" "$(sites f1)"

# E7 THE EXPLICIT NON-GOAL (D7: "this child records the link, it does not control the loop"). An
# extending finding contributes to severity exactly as it did before: a critical that extends a
# concern still blocks. If a later change makes `extends` suppress a round, this cell goes red and
# the reader is sent to the design that says the suppression belongs to `deterministic_accept`.
d="$(newdir)"
critic "$d" 1 "$(file2 "$(f concern f1 '[{"file":"a.php"}]')")"
critic "$d" 2 "$(file2 "$(f critical f2 '[{"file":"b.php"}]' f1)")"
out="$(run --tier high --expected 2 --critics-dir "$d" --required)"
ok "E7 an extending critical still blocks"  "true"     "$(jq -r '.blocking' <<<"$out")"
ok "E7 and still reads critical overall"    "critical" "$(jq -r '.overall' <<<"$out")"

# E8 the link pass never adds or removes a finding, and never moves clean_returns: a clean critic
# beside a linked pair is still credited exactly once.
d="$(newdir)"
critic "$d" 1 '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[]}'
critic "$d" 2 "$(file2 "$(f concern f1 '[{"file":"a.php"}]')")"
critic "$d" 3 "$(file2 "$(f concern f2 '[{"file":"b.php"}]' f1)")"
out="$(run --tier high --expected 3 --critics-dir "$d")"
ok "E8 clean_returns is untouched by the link pass" "1" "$(jq -r '.clean_returns' <<<"$out")"
ok "E8 the finding count is untouched"              "2" "$(jq -r '[.critics[].findings[]] | length' <<<"$out")"

# E9 the two mechanisms do not interfere: an out-of-range finding is judged on ITS OWN sites, before
# any append, so a link cannot drag a finding into or out of the range after the fact.
d="$(newdir)"
critic "$d" 1 "$(file2 "$(f concern f1 '[{"file":"src/A.php"}]')")"
critic "$d" 2 "$(file2 "$(f critical f2 '[{"file":"other/Z.php"}]' f1)")"
out="$(run --tier high --expected 2 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "E9 the out-of-range extender is still suppressed" "false" "$(jq -r '.blocking' <<<"$out")"
ok "E9 and is still handed to review"                 "f2"   "$(jq -r '.out_of_range[0].id' <<<"$out")"
ok "E9 while its site is appended to the target"       "src/A.php,other/Z.php" "$(sites f1)"

# --- guard: exact count, so a silently-skipped block cannot pass as green (D8) ---
[ "$((PASS + FAIL))" -eq 69 ] || { echo "finding-link-and-range-spec: expected 69 assertions, ran $((PASS + FAIL))"; exit 2; }

echo "----"; echo "finding-link-and-range-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
