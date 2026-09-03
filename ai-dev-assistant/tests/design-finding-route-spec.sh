#!/usr/bin/env bash
# Behavioral spec for the design-finding route: the third thing
# scripts/wo-critique-aggregate.sh reads off a finding besides its severity, after the declared
# `extends` link and the component-range check that finding-link-and-range-spec.sh covers.
#
# THE CRITERION, in the task owner's words: "A build finding's fix changes no design decision and
# no test assertion: a fix that swaps the mechanism the component's design names ... is a design
# finding, recorded and handed to review, never repaired mid-build — verify: such a finding runs
# zero repair rounds." The test-assertion half is repair-accept-check.sh's; this file is the other
# half.
#
# WHY IT IS A ROUTE AND NOT A GATE. A repair loop whose subject can edit the standard always
# converges, because the work can move the goalposts instead of meeting them. A finding whose only
# fix is "build it a different way" is not a defect in the build — it is a disagreement with the
# design, and the builder is not the party who settles that. Before this route every blocking
# finding took the same path, so such a finding was repaired mid-build and the design was rewritten
# to match the fix; scripts/contract-baseline.sh notices at the close of the phase, after every
# round it caused has already been spent.
#
# WHY A SEPARATE FILE, not more cells in finding-link-and-range-spec.sh. That file states its scope
# in its own header as two mechanisms and closes with an exact assertion count; a third unrelated
# rule would mean re-scoping the header and moving that guard. The same reasoning its header gives
# for not living inside finding-shape-spec.sh.
#
# The load-bearing cells:
#   - D1/D2 THE CRITERION AS A PAIR. The same critic file, the same severity, the same tier,
#     differing only in the flag: marked, `blocking` is false and the finding is handed to review;
#     unmarked, `blocking` is true. A route that swallowed everything would pass the first half and
#     fail the second, and a flag that recorded without suppressing would do the reverse.
#   - D3 the realistic shape. A critic filing a critical writes `verdict: "critical"` too
#     (agents/wo-critic.md: the kernel lifts the whole verdict to the worst finding). If the verdict
#     survived, the round would open anyway and the whole route would be a recorded flag with no
#     effect on the loop — which is what the range check's own R3 cell exists to prevent.
#   - D4 the bound. One unmarked finding beside a marked one and the verdict stands: the verdict is
#     dropped because it summarises nothing that survived, never because a flag was present.
#   - D5 FAIL-CLOSED ON THE VALUE, and it matters more here than anywhere else in this kernel
#     because this is the one suppression trigger the CRITIC writes rather than the kernel computes.
#     Only the JSON literal `true`. A string "true", a 1, a null: every one of them still blocks.
#   - D6 an `unresolved` verdict is never dropped, marked findings or not. It means the critic could
#     not investigate, which is a separate signal with nowhere else to live.
#   - D7 the two suppressions compose without either swallowing the other's record.
#   - D8 the shape check still binds. `remedy` is required on a critical, and the remedy is this
#     route's whole trigger, so a finding cannot be marked without carrying the field the mark is
#     about.
#   - D9 nothing moves when no flag is present anywhere, which is every record written before the
#     field existed.
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

# A finding carrying every field shape_check requires at schema_version 2.0, so a cell that goes
# red went red for ITS OWN reason. $4 is the raw JSON for design_change, omitted when blank.
f() { # $1 severity  $2 id  $3 where array  [$4 design_change literal]
  jq -nc --arg s "$1" --arg i "$2" --argjson w "$3" --arg d "${4:-}" \
    '{severity:$s, text:"the cron cannot see a queued item", where:$w,
      remedy:"drain from a queue instead of the cron this was designed around", id:$i}
     + (if $d=="" then {} else {design_change:($d|fromjson)} end)'
}
filev() { # $1 the file's own verdict, $2.. findings
  local v="$1"; shift
  jq -nc --arg v "$v" --argjson fs "$(jq -sc '.' <<<"$*")" \
    '{lens:"correctness", schema_version:2.0, verdict:$v, findings:$fs}'
}
file2() { filev pass "$@"; }
W1='[{"file":"src/A.php","line":9}]'

# =============================================================================
# D1/D2 — the criterion, as a pair that differs only in the flag
# =============================================================================

d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 "$W1" true)")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
ok "D1 a marked critical opens no repair round"   "false" "$(jq -r '.blocking' <<<"$out")"
ok "D1 and does not lift the overall verdict"     "pass"  "$(jq -r '.overall' <<<"$out")"
ok "D1 and no halt is emitted"                    "null"  "$(jq -r '.halt_reason' <<<"$out")"
ok "D2 the finding is handed to review"           "f1"    "$(jq -r '.design_change[0].id' <<<"$out")"
ok "D2 with its sites, so review can locate it"   "src/A.php" "$(jq -r '.design_change[0].where[0].file' <<<"$out")"
ok "D2 with the remedy, which is the trigger"     "drain from a queue instead of the cron this was designed around" \
                                                  "$(jq -r '.design_change[0].remedy' <<<"$out")"
ok "D2 and its severity, unchanged by the route"  "critical" "$(jq -r '.design_change[0].severity' <<<"$out")"
ok "D2 and the lens that raised it"               "correctness" "$(jq -r '.design_change[0].lens' <<<"$out")"

# THE NEGATIVE. The same file, the same finding, the flag removed. A route that swallows every
# blocking finding is worse than no route, so this half is not optional.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 "$W1")")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
ok "D2 an ordinary critical still opens a round"  "true"     "$(jq -r '.blocking' <<<"$out")"
ok "D2 and still reads critical overall"          "critical" "$(jq -r '.overall' <<<"$out")"
ok "D2 and is handed to nobody"                   "0"        "$(jq -r '.design_change | length' <<<"$out")"

# =============================================================================
# D3 — the realistic shape: the file's own verdict summarises the marked finding
# =============================================================================

d="$(newdir)"; critic "$d" 1 "$(filev critical "$(f critical f1 "$W1" true)")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
ok "D3 verdict critical, only finding marked: blocking" "false" "$(jq -r '.blocking' <<<"$out")"
ok "D3 and it still reaches review"                     "f1"    "$(jq -r '.design_change[0].id' <<<"$out")"

# D4 the bound. One unmarked finding and the verdict stands, so the drop is about what survived and
# not about a flag having been seen.
d="$(newdir)"; critic "$d" 1 "$(filev critical "$(f critical f1 "$W1" true)" "$(f concern f2 '[{"file":"src/B.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
ok "D4 one unmarked finding: verdict stands, blocking" "true" "$(jq -r '.blocking' <<<"$out")"
ok "D4 the marked one is still handed to review"       "f1"   "$(jq -r '.design_change[0].id' <<<"$out")"

# A marked CRITICAL beside an unmarked CONCERN: the concern is what the file is now worth, so the
# round that opens is a concern's round and not the critical's. Asserted on `overall` because
# `blocking` cannot tell the two apart at high tier with --required.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 "$W1" true)" "$(f concern f2 '[{"file":"src/B.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
ok "D4 the marked critical does not raise the survivor" "concern" "$(jq -r '.overall' <<<"$out")"

# =============================================================================
# D5 — fail-closed on the value. This is the one suppression the CRITIC writes.
# =============================================================================

for v in '"true"' '1' 'null' 'false' '"yes"' '{}' '[true]'; do
  d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 "$W1" "$v")")"
  out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
  ok "D5 design_change:$v is not the literal true, so it still blocks" "true" "$(jq -r '.blocking' <<<"$out")"
  ok "D5 design_change:$v is handed to nobody"                          "0"   "$(jq -r '.design_change | length' <<<"$out")"
done

# =============================================================================
# D6 — an `unresolved` verdict is never dropped
# =============================================================================

# The critic could not investigate. `severity` is concern|critical only, so the file verdict is the
# only field that signal can live in; dropping it would convert "I could not settle this" into a
# clean pass. Same rule the range check holds, reached through the other trigger.
d="$(newdir)"; critic "$d" 1 "$(filev unresolved "$(f critical f1 "$W1" true)")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
ok "D6 an unresolved verdict survives a fully marked file" "true" "$(jq -r '.blocking' <<<"$out")"
# And an unrecognised verdict ranks the same way, fail-closed.
d="$(newdir)"; critic "$d" 1 "$(filev sideways "$(f critical f1 "$W1" true)")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
ok "D6 an unrecognised verdict is not dropped either"      "true" "$(jq -r '.blocking' <<<"$out")"

# =============================================================================
# D7 — the two suppressions compose, and neither swallows the other's record
# =============================================================================

# One finding, both triggers. It belongs in both records: each array answers a different question,
# and a reviewer reading only one of them would otherwise see the finding vanish from that one.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 '[{"file":"other/Z.php"}]' true)")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "D7 out of range AND marked: still no round"      "false" "$(jq -r '.blocking' <<<"$out")"
ok "D7 recorded in design_change[]"                  "f1"    "$(jq -r '.design_change[0].id' <<<"$out")"
ok "D7 and recorded in out_of_range[] as well"       "f1"    "$(jq -r '.out_of_range[0].id' <<<"$out")"

# Two findings, one suppressed by each trigger, nothing surviving. The verdict summarises only
# suppressed findings, so it goes too — the drop condition reads BOTH triggers or this cell blocks.
d="$(newdir)"; critic "$d" 1 "$(filev critical "$(f critical f1 '[{"file":"other/Z.php"}]')" "$(f critical f2 '[{"file":"src/A.php"}]' true)")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "D7 one of each and nothing left: no round"       "false" "$(jq -r '.blocking' <<<"$out")"
ok "D7 the range-suppressed one still reaches review" "f1"   "$(jq -r '.out_of_range[0].id' <<<"$out")"
ok "D7 the marked one still reaches review"           "f2"   "$(jq -r '.design_change[0].id' <<<"$out")"

# The range check is untouched by a marked finding elsewhere in the file: an IN-RANGE unmarked
# critical still blocks beside a marked one.
d="$(newdir)"; critic "$d" 1 "$(file2 "$(f critical f1 '[{"file":"src/A.php"}]' true)" "$(f critical f2 '[{"file":"src/A.php"}]')")"
out="$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$(rangef src/A.php)")"
ok "D7 a marked finding does not shelter its neighbours" "true" "$(jq -r '.blocking' <<<"$out")"

# =============================================================================
# D8 — the shape check still binds, so the trigger field cannot go missing
# =============================================================================

# `remedy` is required on a critical, and the remedy is what the mark is a claim about. A critic
# that marks a finding and files no remedy has made an unreadable claim, and the file goes
# unresolved exactly as it would without the mark. The mark must not buy an exemption.
d="$(newdir)"
critic "$d" 1 '{"lens":"correctness","schema_version":2.0,"verdict":"pass","findings":[
  {"severity":"critical","text":"x","id":"f1","where":[{"file":"src/A.php"}],"design_change":true}]}'
out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
ok "D8 a marked finding with no remedy fails the shape check" "fail" "$(jq -r '.critics[0].shape_check' <<<"$out")"
ok "D8 and the file is unresolved, so the mark buys nothing"  "unresolved" "$(jq -r '.critics[0].effective' <<<"$out")"
ok "D8 which still blocks"                                    "true" "$(jq -r '.blocking' <<<"$out")"

# =============================================================================
# D9 — nothing moves when no flag is present
# =============================================================================

# Every record written before this field existed is this shape, and a pre-contract file (no
# schema_version) is read exactly as it was.
d="$(newdir)"; critic "$d" 1 '{"lens":"correctness","verdict":"concern","findings":[{"severity":"concern","text":"x"}]}'
out="$(run --tier high --expected 1 --critics-dir "$d" --required)"
ok "D9 a pre-contract file is unchanged: overall"   "concern" "$(jq -r '.overall' <<<"$out")"
ok "D9 and design_change[] is empty"                "0"       "$(jq -r '.design_change | length' <<<"$out")"
ok "D9 the key is always present, never absent"     "array"   "$(jq -r '.design_change | type' <<<"$out")"

# A clean critic is still credited: the route adds a record, it does not add or remove a finding.
d="$(newdir)"
critic "$d" 1 '{"lens":"security","schema_version":2.0,"verdict":"pass","findings":[]}'
critic "$d" 2 "$(file2 "$(f critical f1 "$W1" true)")"
out="$(run --tier high --expected 2 --critics-dir "$d" --required)"
ok "D9 clean_returns is untouched by the route"     "1" "$(jq -r '.clean_returns' <<<"$out")"
ok "D9 and the finding count is untouched"          "1" "$(jq -r '[.critics[].findings[]] | length' <<<"$out")"
ok "D9 the marked file itself still reads pass"     "pass" "$(jq -r '.critics[1].effective' <<<"$out")"

# =============================================================================
# D10 — THE SUPPRESSION HAS TO SURVIVE ITS NEXT READER
# =============================================================================
#
# Every cell above stops at the aggregate envelope. Phase 4 (2026-09-03) found that one line further
# on, `commands/implement.md` rebuilds the list of files a repair must touch from the RAW critics
# array, selecting on severity alone, and hands the design site to repair-scope-check.sh anyway. So
# a repair that obeyed the rule and left the design file alone was reported `unaddressed` -- named
# out loud as a shortfall -- while one that rewrote it mid-build came back clean. The deterministic
# reading rewarded the forbidden repair. Suppressing a finding from `effective` is not the whole
# rule; the rule is that no downstream reader may ask for it back.
#
# So this block does not assert on the envelope. It runs the aggregate for real, lifts the site
# expression and the invocation OUT of the command body the way build-critique-gate-spec does, and
# executes them. A grep for `design_change` in the body would have passed on the broken version.
IMPL="$ROOT/commands/implement.md"
d="$(newdir)"
critic "$d" 1 "$(filev critical "$(f critical dsg '[{"file":"src/DESIGN.php","line":3}]' true)" "$(f concern ord '[{"file":"src/ORD.php","line":4}]')")"
ENV_OUT="$(run --tier high --expected 1 --critics-dir "$d" --required)"
CJ="$TMP/d10.critique.json"; printf '%s' "$ENV_OUT" > "$CJ"

# The site expression, lifted verbatim from the body rather than restated here: a copy in this file
# would agree with itself forever while the shipped one drifted.
SITE_JQ="$(awk '/--finding-sites /{ sub(/^.*--finding-sites "\$\(jq -c /,""); sub(/" \$\{?CD.*$/,""); sub(/ "\$CD.*$/,""); print; exit }' "$IMPL" | sed "s/^'//; s/'\$//")"
if [ -z "$SITE_JQ" ]; then
  FAIL=$((FAIL+1)); echo "FAIL D10: no --finding-sites expression could be lifted from implement.md"
else
  PASS=$((PASS+1))
  SITES="$(jq -c "$SITE_JQ" "$CJ" 2>/dev/null)"
  ok "D10 the ordinary finding is still asked for"  "true"  "$(jq -r 'index("src/ORD.php") != null' <<<"$SITES")"
  ok "D10 the design site is NOT asked for"         "false" "$(jq -r 'index("src/DESIGN.php") != null' <<<"$SITES")"
  # The OTHER suppression, tested on its own. Both disjuncts went into the fix together and only one
  # had a cell: dropping the out_of_range half left this block at 55/55 under mutation. A rule looks
  # covered when its sibling is.
  # The off-range finding carries NO design_change, or the design half alone would suppress it and
  # this cell could never isolate the range half. That is exactly how the first version of it passed.
  dO="$(newdir)"
  critic "$dO" 1 "$(filev critical "$(f critical off '[{"file":"src/OFF.php","line":7}]')" "$(f concern ord '[{"file":"src/ORD.php","line":4}]')")"
  RJ="$(rangef src/ORD.php)"
  ENV_OOR="$(run --tier high --expected 1 --critics-dir "$dO" --required --component-files-from "$RJ")"
  SITES_OOR="$(jq -c "$SITE_JQ" <<<"$ENV_OOR" 2>/dev/null)"
  ok "D10 the range check marked the off-range site" "true" "$(jq -r '[.out_of_range[].id] | index("off") != null' <<<"$ENV_OOR")"
  ok "D10 an out-of-range site is NOT asked for"     "false" "$(jq -r 'index("src/OFF.php") != null' <<<"$SITES_OOR")"
  ok "D10 while the in-range site still is"          "true"  "$(jq -r 'index("src/ORD.php") != null' <<<"$SITES_OOR")"
  # And the design half isolated the same way: in range, so only the flag can suppress it.
  RJ2="$(rangef src/ORD.php src/DESIGN.php)"
  S2="$(jq -c "$SITE_JQ" <<<"$(run --tier high --expected 1 --critics-dir "$d" --required --component-files-from "$RJ2")" 2>/dev/null)"
  ok "D10 an in-range design site is still NOT asked for" "false" "$(jq -r 'index("src/DESIGN.php") != null' <<<"$S2")"
  ok "D10 and the in-range ordinary site still is"        "true"  "$(jq -r 'index("src/ORD.php") != null' <<<"$S2")"
fi

# And the same thing again through the real checker, because the site list is an input nobody reads
# directly: what a builder is told is repair-scope-check.sh's verdict.
LIT="$TMP/d10-scope.sh"
awk 'index($0, "/scripts/repair-scope-check.sh") { s=1 }
     s { print; if ($0 !~ /\\[[:space:]]*$/) exit }' "$IMPL" | sed 's/<component>/main/g' > "$LIT"
if [ ! -s "$LIT" ]; then
  FAIL=$((FAIL+1)); echo "FAIL D10: implement.md carries no repair-scope-check.sh invocation to run"
else
  PASS=$((PASS+1))
  CD10="$TMP/d10cd"; mkdir -p "$CD10"
  cp "$CJ" "$CD10/main.critique.json"
  # THE COMPLIANT REPAIR: it fixes the ordinary finding and leaves the design file alone, which is
  # exactly what the criterion demands of it.
  printf 'M\tsrc/ORD.php\n' > "$CD10/main.repair.txt"
  ( CLAUDE_PLUGIN_ROOT="$ROOT" CD="$CD10" bash "$LIT" ) >/dev/null 2>&1
  ok "D10 the compliant repair is not told it missed the design site" "false" \
     "$(jq -r '(.unaddressed // []) | index("src/DESIGN.php") != null' "$CD10/main.scope.json" 2>/dev/null)"
  ok "D10 and it is not told it missed anything at all"               "0" \
     "$(jq -r '(.unaddressed // []) | length' "$CD10/main.scope.json" 2>/dev/null)"
  # THE INVERSE, so the cell above cannot be satisfied by a checker that reports nothing ever: a
  # repair that DOES rewrite the design site is now touching a file no finding asked it to.
  printf 'M\tsrc/ORD.php\nM\tsrc/DESIGN.php\n' > "$CD10/main.repair.txt"
  ( CLAUDE_PLUGIN_ROOT="$ROOT" CD="$CD10" bash "$LIT" ) >/dev/null 2>&1
  ok "D10 the repair that rewrites the design site is flagged, not cleared" "true" \
     "$(jq -r '(.unnamed // []) | index("src/DESIGN.php") != null' "$CD10/main.scope.json" 2>/dev/null)"
fi

# --- guard: exact count, so a silently-skipped block cannot pass as green ---
[ "$((PASS + FAIL))" -eq 60 ] || { echo "design-finding-route-spec: expected 60 assertions, ran $((PASS + FAIL))"; exit 2; }

echo "----"; echo "design-finding-route-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
