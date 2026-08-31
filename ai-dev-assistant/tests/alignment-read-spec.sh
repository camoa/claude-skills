#!/usr/bin/env bash
# Spec for scripts/alignment-read.sh — focuses on the v1.1 optional per-criterion
# `verification` suffix (` — verify: <note>`) and its backward compatibility.
# Also covers the v1.3 optional per-criterion `author` marker (` — by: owner|designer`).
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
SUT="$ROOT/scripts/alignment-read.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

fail_check() {
  FAIL=$((FAIL+1))
  echo "FAIL $1: $2"
  [ -n "${OUT:-}" ] && echo "  out: $OUT"
}
pass_check() { PASS=$((PASS+1)); }

# mkalign: make a fresh per-test task dir, write the given body as alignment.md,
# echo the task dir path. Body is passed on stdin.
mkalign() { # $1=test-name ; body on stdin
  local d="$TMP/$1"; mkdir -p "$d"
  cat > "$d/alignment.md"
  echo "$d"
}

# run the SUT against a task dir; capture OUT/RC
arun() { OUT="$(bash "$SUT" "$@" 2>/dev/null)"; RC=$?; }

# tlcrit: jq path into task_level success criteria; $1=index $2=field
tlcrit() { jq -r ".sections.task_level.success_criteria[$1].$2" <<<"$OUT"; }

# ---------------------------------------------------------------------------
# T1: criterion WITH em-dash verify suffix → verification populated, text excludes suffix
D="$(mkalign t1 <<'EOF'
# Alignment: t1

**Task:** t1
**Created:** 2026-06-15

## Task-Level

### Goal
g

### Success criteria
- [ ] Settings form persists values — verify: playwright save+reload assertion
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "Settings form persists values" ] \
  && [ "$(tlcrit 0 verification)" = "playwright save+reload assertion" ] \
  && [ "$(tlcrit 0 checked)" = "false" ]; then
  pass_check "T1 em-dash verify suffix: text split, verification captured"
else
  fail_check "T1 em-dash verify suffix: text split, verification captured" \
    "text=$(tlcrit 0 text) verif=$(tlcrit 0 verification) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T2: criterion WITHOUT suffix → verification null, text is the full criterion
D="$(mkalign t2 <<'EOF'
# Alignment: t2

## Task-Level

### Success criteria
- [x] Config schema exists at the expected path
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "Config schema exists at the expected path" ] \
  && [ "$(tlcrit 0 verification)" = "null" ] \
  && [ "$(tlcrit 0 checked)" = "true" ]; then
  pass_check "T2 no suffix: verification null, full text (backward compat)"
else
  fail_check "T2 no suffix: verification null, full text (backward compat)" \
    "text=$(tlcrit 0 text) verif=$(tlcrit 0 verification) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T3: mix of with/without in one block → each gets right verification
D="$(mkalign t3 <<'EOF'
# Alignment: t3

## Task-Level

### Success criteria
- [ ] First with note — verify: run the unit suite
- [ ] Second without note
- [x] Third with note — verify: manual smoke in browser
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "First with note" ] \
  && [ "$(tlcrit 0 verification)" = "run the unit suite" ] \
  && [ "$(tlcrit 1 text)" = "Second without note" ] \
  && [ "$(tlcrit 1 verification)" = "null" ] \
  && [ "$(tlcrit 2 text)" = "Third with note" ] \
  && [ "$(tlcrit 2 verification)" = "manual smoke in browser" ]; then
  pass_check "T3 mixed block: per-criterion verification (null vs string)"
else
  fail_check "T3 mixed block: per-criterion verification (null vs string)" \
    "v0=$(tlcrit 0 verification) v1=$(tlcrit 1 verification) v2=$(tlcrit 2 verification) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T4: en-dash and hyphen delimiter variants both parse
D="$(mkalign t4 <<'EOF'
# Alignment: t4

## Task-Level

### Success criteria
- [ ] En-dash criterion – verify: endash note
- [ ] Hyphen criterion - verify: hyphen note
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "En-dash criterion" ] \
  && [ "$(tlcrit 0 verification)" = "endash note" ] \
  && [ "$(tlcrit 1 text)" = "Hyphen criterion" ] \
  && [ "$(tlcrit 1 verification)" = "hyphen note" ]; then
  pass_check "T4 en-dash and hyphen delimiter variants parse"
else
  fail_check "T4 en-dash and hyphen delimiter variants parse" \
    "t0=$(tlcrit 0 text) v0=$(tlcrit 0 verification) t1=$(tlcrit 1 text) v1=$(tlcrit 1 verification) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T5: regression — em-dash in text but NO `verify:` token → verification null, text intact
D="$(mkalign t5 <<'EOF'
# Alignment: t5

## Task-Level

### Success criteria
- [ ] supports A — B mode
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "supports A — B mode" ] \
  && [ "$(tlcrit 0 verification)" = "null" ]; then
  pass_check "T5 em-dash without verify: token → null, text intact"
else
  fail_check "T5 em-dash without verify: token → null, text intact" \
    "text=$(tlcrit 0 text) verif=$(tlcrit 0 verification) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T6: prose fallback (no task-list) → success_criteria_not_checklist + empty []
D="$(mkalign t6 <<'EOF'
# Alignment: t6

## Task-Level

### Success criteria
This is prose, not a checklist, and has no task-list lines at all.
EOF
)"
arun "$D"
NCRIT="$(jq -r '.sections.task_level.success_criteria | length' <<<"$OUT")"
WARN="$(jq -r '[.warnings[] | select(.code=="success_criteria_not_checklist")] | length' <<<"$OUT")"
if [ "$RC" -eq 0 ] && [ "$NCRIT" = "0" ] && [ "$WARN" = "1" ]; then
  pass_check "T6 prose fallback: not_checklist warning + empty criteria (unchanged)"
else
  fail_check "T6 prose fallback: not_checklist warning + empty criteria (unchanged)" \
    "ncrit=$NCRIT warn=$WARN rc=$RC"
fi

# ---------------------------------------------------------------------------
# T7: split on FIRST delimiter when the note itself contains a delimiter token
D="$(mkalign t7 <<'EOF'
# Alignment: t7

## Task-Level

### Success criteria
- [ ] Criterion text — verify: run X — then check Y
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "Criterion text" ] \
  && [ "$(tlcrit 0 verification)" = "run X — then check Y" ]; then
  pass_check "T7 split on FIRST delimiter; em-dash in note preserved"
else
  fail_check "T7 split on FIRST delimiter; em-dash in note preserved" \
    "text=$(tlcrit 0 text) verif=$(tlcrit 0 verification) rc=$RC"
fi

# ---------------------------------------------------------------------------
# Wrapped list items (v1.2). A "- [ ] ..." item that continues on the next line
# is ordinary markdown and renders as one item, and the writer produces them —
# but the per-line scan kept only the first line and dropped the rest with no
# warning, so a criterion became a sentence fragment and a wrapped "— verify:"
# note vanished. Found by feeding the reader a real scope contract.

# T8: criterion wraps, and the verify note starts on a continuation line
D="$(mkalign t8 <<'EOF'
# Alignment: t8

**Task:** t8
**Created:** 2026-08-25

## Task-Level

### Goal
g

### Success criteria
- [ ] A fixture set exists, covering: an item wholly in the past; an item wholly
      in the future; a recurring item with past and future occurrences
      — verify: running the routine on a clean database produces all three
EOF
)"
arun "$D"
WANT_T8="A fixture set exists, covering: an item wholly in the past; an item wholly in the future; a recurring item with past and future occurrences"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "$WANT_T8" ] \
  && [ "$(tlcrit 0 verification)" = "running the routine on a clean database produces all three" ] \
  && [ "$(jq -r '.sections.task_level.success_criteria | length' <<<"$OUT")" = "1" ]; then
  pass_check "T8 wrapped criterion: whole text joined, wrapped verify note captured"
else
  fail_check "T8 wrapped criterion: whole text joined, wrapped verify note captured" \
    "text=$(tlcrit 0 text) verif=$(tlcrit 0 verification) rc=$RC"
fi

# T9: criterion wraps mid-sentence with no verify suffix at all
D="$(mkalign t9 <<'EOF'
# Alignment: t9

**Task:** t9
**Created:** 2026-08-25

## Task-Level

### Goal
g

### Success criteria
- [ ] Events are unpublished, never deleted, and the node count is
      unchanged afterwards
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "Events are unpublished, never deleted, and the node count is unchanged afterwards" ] \
  && [ "$(tlcrit 0 verification)" = "null" ]; then
  pass_check "T9 wrapped criterion, no verify suffix: whole text joined"
else
  fail_check "T9 wrapped criterion, no verify suffix: whole text joined" \
    "text=$(tlcrit 0 text) verif=$(tlcrit 0 verification) rc=$RC"
fi

# T10: the verify NOTE itself wraps — the tail of the note must not be cut
D="$(mkalign t10 <<'EOF'
# Alignment: t10

**Task:** t10
**Created:** 2026-08-25

## Task-Level

### Goal
g

### Success criteria
- [ ] An already-unpublished item is left untouched — verify: no re-save, no
      new log entry on a second run
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "An already-unpublished item is left untouched" ] \
  && [ "$(tlcrit 0 verification)" = "no re-save, no new log entry on a second run" ]; then
  pass_check "T10 wrapped verify note: full note captured, not cut mid-sentence"
else
  fail_check "T10 wrapped verify note: full note captured, not cut mid-sentence" \
    "text=$(tlcrit 0 text) verif=$(tlcrit 0 verification) rc=$RC"
fi

# T11: non-goals wrap the same way and lost their tails the same way
D="$(mkalign t11 <<'EOF'
# Alignment: t11

**Task:** t11
**Created:** 2026-08-25

## Task-Level

### Goal
g

### Non-goals
- Changing how items are displayed. The view, its blocks, and the
  calendar are untouched.
- Deleting items.
EOF
)"
arun "$D"
NG0="$(jq -r '.sections.task_level.non_goals[0]' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$NG0" = "Changing how items are displayed. The view, its blocks, and the calendar are untouched." ] \
  && [ "$(jq -r '.sections.task_level.non_goals | length' <<<"$OUT")" = "2" ]; then
  pass_check "T11 wrapped non-goal: whole text joined, count unchanged"
else
  fail_check "T11 wrapped non-goal: whole text joined, count unchanged" \
    "ng0=$NG0 len=$(jq -r '.sections.task_level.non_goals | length' <<<"$OUT") rc=$RC"
fi

# T12: a following line that itself starts a list item is a NEW item, never a
# continuation — two wrapped criteria must stay two criteria
D="$(mkalign t12 <<'EOF'
# Alignment: t12

**Task:** t12
**Created:** 2026-08-25

## Task-Level

### Goal
g

### Success criteria
- [ ] First criterion that wraps onto
      a second line
- [ ] Second criterion that wraps onto
      a second line
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.sections.task_level.success_criteria | length' <<<"$OUT")" = "2" ] \
  && [ "$(tlcrit 0 text)" = "First criterion that wraps onto a second line" ] \
  && [ "$(tlcrit 1 text)" = "Second criterion that wraps onto a second line" ]; then
  pass_check "T12 adjacent wrapped items stay separate items"
else
  fail_check "T12 adjacent wrapped items stay separate items" \
    "len=$(jq -r '.sections.task_level.success_criteria | length' <<<"$OUT") t0=$(tlcrit 0 text) t1=$(tlcrit 1 text)"
fi

# T13: a blank line closes an item — trailing prose after it is not swallowed
# into the last criterion
D="$(mkalign t13 <<'EOF'
# Alignment: t13

**Task:** t13
**Created:** 2026-08-25

## Task-Level

### Goal
g

### Success criteria
- [ ] A criterion that wraps onto
      a second line

Some trailing note that belongs to nobody.
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.sections.task_level.success_criteria | length' <<<"$OUT")" = "1" ] \
  && [ "$(tlcrit 0 text)" = "A criterion that wraps onto a second line" ]; then
  pass_check "T13 blank line closes the item; trailing prose not absorbed"
else
  fail_check "T13 blank line closes the item; trailing prose not absorbed" \
    "len=$(jq -r '.sections.task_level.success_criteria | length' <<<"$OUT") t0=$(tlcrit 0 text)"
fi

# ---------------------------------------------------------------------------
# A section with zero parsed content splits two ways (v1.2). Before this, both
# reported section_empty_stub — so an author who wrote the four fields as bold
# labels instead of H3 headings was told the section was empty while looking at
# a screen full of their own text, and had to go read the grammar to find out
# what was actually wrong.

# T14: body content present, no recognized H3 → section_unparsed_body
D="$(mkalign t14 <<'EOF'
# Alignment: t14

**Task:** t14
**Created:** 2026-08-25

## Task-Level

**Goal**

Published items whose dates have passed stay published indefinitely.

**Success criteria**

- [ ] A past item is unpublished automatically
EOF
)"
arun "$D"
W="$(jq -r '[.warnings[].code] | join(",")' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$W" = "section_unparsed_body" ] \
  && [ "$(jq -r '.sections.task_level.present' <<<"$OUT")" = "false" ]; then
  pass_check "T14 bold labels: section_unparsed_body, not section_empty_stub"
else
  fail_check "T14 bold labels: section_unparsed_body, not section_empty_stub" \
    "warnings=$W present=$(jq -r '.sections.task_level.present' <<<"$OUT") rc=$RC"
fi

# T15: H2 with genuinely nothing under it keeps section_empty_stub
D="$(mkalign t15 <<'EOF'
# Alignment: t15

**Task:** t15
**Created:** 2026-08-25

## Task-Level
EOF
)"
arun "$D"
W="$(jq -r '[.warnings[].code] | join(",")' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$W" = "section_empty_stub" ] \
  && [ "$(jq -r '.sections.task_level.present' <<<"$OUT")" = "false" ]; then
  pass_check "T15 genuinely empty H2 still reports section_empty_stub"
else
  fail_check "T15 genuinely empty H2 still reports section_empty_stub" \
    "warnings=$W present=$(jq -r '.sections.task_level.present' <<<"$OUT") rc=$RC"
fi

# T16: a well-formed section with a line of preamble under the H2 before the
# first H3 is NOT flagged — it parsed fine, so neither warning applies
D="$(mkalign t16 <<'EOF'
# Alignment: t16

**Task:** t16
**Created:** 2026-08-25

## Task-Level

A sentence of preamble that belongs to no field.

### Goal

g

### Success criteria

- [ ] a criterion
EOF
)"
arun "$D"
W="$(jq -r '[.warnings[].code] | join(",")' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.sections.task_level.present' <<<"$OUT")" = "true" ] \
  && [[ "$W" != *"section_unparsed_body"* ]] \
  && [[ "$W" != *"section_empty_stub"* ]]; then
  pass_check "T16 preamble under a populated H2 raises neither stub warning"
else
  fail_check "T16 preamble under a populated H2 raises neither stub warning" \
    "warnings=$W present=$(jq -r '.sections.task_level.present' <<<"$OUT") rc=$RC"
fi

# ---------------------------------------------------------------------------
# v1.3: optional per-criterion author marker (` — by: owner|designer`).

# A1: `— by: owner` alone → author owner, text clean
D="$(mkalign a1 <<'EOF'
# Alignment: a1

## Task-Level

### Success criteria
- [ ] Settings form persists values — by: owner
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "Settings form persists values" ] \
  && [ "$(tlcrit 0 author)" = "owner" ]; then
  pass_check "A1 by: owner alone: author owner, text clean"
else
  fail_check "A1 by: owner alone: author owner, text clean" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) rc=$RC"
fi

# A2: `— by: designer` alone → author designer
D="$(mkalign a2 <<'EOF'
# Alignment: a2

## Task-Level

### Success criteria
- [ ] Landing page matches the mockup — by: designer
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "Landing page matches the mockup" ] \
  && [ "$(tlcrit 0 author)" = "designer" ]; then
  pass_check "A2 by: designer alone: author designer"
else
  fail_check "A2 by: designer alone: author designer" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) rc=$RC"
fi

# A3: both markers on one line, `— by: owner — verify: <how>` → author owner AND
# verification captured AND text clean
D="$(mkalign a3 <<'EOF'
# Alignment: a3

## Task-Level

### Success criteria
- [ ] Settings form persists values — by: owner — verify: playwright save+reload assertion
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "Settings form persists values" ] \
  && [ "$(tlcrit 0 author)" = "owner" ] \
  && [ "$(tlcrit 0 verification)" = "playwright save+reload assertion" ]; then
  pass_check "A3 both markers on one line: author + verification + clean text"
else
  fail_check "A3 both markers on one line: author + verification + clean text" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) verif=$(tlcrit 0 verification) rc=$RC"
fi

# A4: no marker → author null, text is the full criterion (backward compat)
D="$(mkalign a4 <<'EOF'
# Alignment: a4

## Task-Level

### Success criteria
- [ ] Config schema exists at the expected path
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "Config schema exists at the expected path" ] \
  && [ "$(tlcrit 0 author)" = "null" ]; then
  pass_check "A4 no marker: author null, full text (backward compat)"
else
  fail_check "A4 no marker: author null, full text (backward compat)" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) rc=$RC"
fi

# A5: `— by: someone-else` → author null, text left WHOLE (marker not stripped),
# warning criterion_author_unrecognized present
D="$(mkalign a5 <<'EOF'
# Alignment: a5

## Task-Level

### Success criteria
- [ ] Bad tail case — by: someone-else
EOF
)"
arun "$D"
WARN5="$(jq -r '[.warnings[] | select(.code=="criterion_author_unrecognized")] | length' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "Bad tail case — by: someone-else" ] \
  && [ "$(tlcrit 0 author)" = "null" ] \
  && [ "$WARN5" = "1" ]; then
  pass_check "A5 unrecognized tail: author null, text whole, warning present"
else
  fail_check "A5 unrecognized tail: author null, text whole, warning present" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) warn=$WARN5 rc=$RC"
fi

# A6: em-dash present in text but no `by:` token → author null, text intact
D="$(mkalign a6 <<'EOF'
# Alignment: a6

## Task-Level

### Success criteria
- [ ] supports A — B mode
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "supports A — B mode" ] \
  && [ "$(tlcrit 0 author)" = "null" ]; then
  pass_check "A6 em-dash without by: token: author null, text intact"
else
  fail_check "A6 em-dash without by: token: author null, text intact" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) rc=$RC"
fi

# A7: a wrapped (multi-line) criterion carrying the marker — join_wrapped runs
# first, so the marker parses the same as on a single line
D="$(mkalign a7 <<'EOF'
# Alignment: a7

## Task-Level

### Success criteria
- [ ] A fixture set exists, covering: an item wholly in the past and one wholly
      in the future — by: owner
EOF
)"
arun "$D"
WANT_A7="A fixture set exists, covering: an item wholly in the past and one wholly in the future"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "$WANT_A7" ] \
  && [ "$(tlcrit 0 author)" = "owner" ]; then
  pass_check "A7 wrapped criterion with author marker: parses same as one line"
else
  fail_check "A7 wrapped criterion with author marker: parses same as one line" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) rc=$RC"
fi

# A8: wrong order, `— verify: how — by: owner` → author null and the marker
# stays inside verification. This is the documented consequence of running
# the verify split first, not an accident.
D="$(mkalign a8 <<'EOF'
# Alignment: a8

## Task-Level

### Success criteria
- [ ] Criterion text — verify: how — by: owner
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "Criterion text" ] \
  && [ "$(tlcrit 0 author)" = "null" ] \
  && [ "$(tlcrit 0 verification)" = "how — by: owner" ]; then
  pass_check "A8 wrong order: author null, marker stays inside verification"
else
  fail_check "A8 wrong order: author null, marker stays inside verification" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) verif=$(tlcrit 0 verification) rc=$RC"
fi

# ---------------------------------------------------------------------------
# F1 regression: the author marker accepts EM-DASH ONLY. "by:" is ordinary
# English, unlike the distinctive "verify:" token, so a hyphen or en-dash
# delimiter here would read unmarked prose as a marker and silently promote
# it to an author — the exact failure this field exists to prevent.

# A9: hyphen delimiter is NOT a marker → author null, text is the FULL line,
# nothing stripped
D="$(mkalign a9 <<'EOF'
# Alignment: a9

## Task-Level

### Success criteria
- [ ] the task list can be filtered - by: owner
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "the task list can be filtered - by: owner" ] \
  && [ "$(tlcrit 0 author)" = "null" ]; then
  pass_check "A9 hyphen delimiter rejected: author null, text whole"
else
  fail_check "A9 hyphen delimiter rejected: author null, text whole" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) rc=$RC"
fi

# A10: en-dash delimiter is NOT a marker → author null, text whole
D="$(mkalign a10 <<'EOF'
# Alignment: a10

## Task-Level

### Success criteria
- [ ] the task list can be filtered – by: owner
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "the task list can be filtered – by: owner" ] \
  && [ "$(tlcrit 0 author)" = "null" ]; then
  pass_check "A10 en-dash delimiter rejected: author null, text whole"
else
  fail_check "A10 en-dash delimiter rejected: author null, text whole" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) rc=$RC"
fi

# A11: em-dash delimiter still works (the accepted case, kept as a regression
# guard alongside A1)
D="$(mkalign a11 <<'EOF'
# Alignment: a11

## Task-Level

### Success criteria
- [ ] the task list can be filtered — by: owner
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "the task list can be filtered" ] \
  && [ "$(tlcrit 0 author)" = "owner" ]; then
  pass_check "A11 em-dash delimiter still accepted"
else
  fail_check "A11 em-dash delimiter still accepted" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) rc=$RC"
fi

# A12: hyphen "marker" plus a real verify suffix → verification captured,
# author null, the hyphen text stays inside text (not stripped)
D="$(mkalign a12 <<'EOF'
# Alignment: a12

## Task-Level

### Success criteria
- [ ] filtered - by: owner — verify: run the suite
EOF
)"
arun "$D"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "filtered - by: owner" ] \
  && [ "$(tlcrit 0 author)" = "null" ] \
  && [ "$(tlcrit 0 verification)" = "run the suite" ]; then
  pass_check "A12 hyphen not a marker, verify still splits: text keeps hyphen tail"
else
  fail_check "A12 hyphen not a marker, verify still splits: text keeps hyphen tail" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) verif=$(tlcrit 0 verification) rc=$RC"
fi

# ---------------------------------------------------------------------------
# F5 regression: a near-miss marker must fire criterion_author_unrecognized,
# not fail silently. The strict em-dash delimiter (F1) rejects a wrong
# spacing or a wrong dash character, same as it rejects wrong prose — but the
# writer who typed it meant a marker, and needs to be told why it didn't
# parse rather than just seeing an unrecorded author.

# A13: double space around "by:" → author null, warning present
D="$(mkalign a13 <<EOF
# Alignment: a13

## Task-Level

### Success criteria
- [ ] extra space —  by:  owner
EOF
)"
arun "$D"
WARN13="$(jq -r '[.warnings[] | select(.code=="criterion_author_unrecognized")] | length' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 author)" = "null" ] \
  && [ "$WARN13" = "1" ]; then
  pass_check "A13 near-miss: double space around by:, warning present"
else
  fail_check "A13 near-miss: double space around by:, warning present" \
    "author=$(tlcrit 0 author) warn=$WARN13 rc=$RC"
fi

# A14: a tab in the delimiter → author null, warning present
D="$(mkalign a14 <<EOF
# Alignment: a14

## Task-Level

### Success criteria
- [ ] tab before —$(printf '\t')by: owner
EOF
)"
arun "$D"
WARN14="$(jq -r '[.warnings[] | select(.code=="criterion_author_unrecognized")] | length' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 author)" = "null" ] \
  && [ "$WARN14" = "1" ]; then
  pass_check "A14 near-miss: tab in delimiter, warning present"
else
  fail_check "A14 near-miss: tab in delimiter, warning present" \
    "author=$(tlcrit 0 author) warn=$WARN14 rc=$RC"
fi

# A15: hyphen delimiter (F1's rejected dash) → author null, text WHOLE,
# warning present. Covers F1 and F5 together.
D="$(mkalign a15 <<'EOF'
# Alignment: a15

## Task-Level

### Success criteria
- [ ] the task list can be filtered - by: owner
EOF
)"
arun "$D"
WARN15="$(jq -r '[.warnings[] | select(.code=="criterion_author_unrecognized")] | length' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "the task list can be filtered - by: owner" ] \
  && [ "$(tlcrit 0 author)" = "null" ] \
  && [ "$WARN15" = "1" ]; then
  pass_check "A15 near-miss: hyphen delimiter, text whole, warning present"
else
  fail_check "A15 near-miss: hyphen delimiter, text whole, warning present" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) warn=$WARN15 rc=$RC"
fi

# A16: exact delimiter, wrong-case tail ("Owner") → this is the EXISTING
# exact-match-bad-tail path (not the near-miss path), and already warns
D="$(mkalign a16 <<'EOF'
# Alignment: a16

## Task-Level

### Success criteria
- [ ] Landing page matches the mockup — by: Owner
EOF
)"
arun "$D"
WARN16="$(jq -r '[.warnings[] | select(.code=="criterion_author_unrecognized")] | length' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 author)" = "null" ] \
  && [ "$WARN16" = "1" ]; then
  pass_check "A16 capitalized tail: author null, warning present"
else
  fail_check "A16 capitalized tail: author null, warning present" \
    "author=$(tlcrit 0 author) warn=$WARN16 rc=$RC"
fi

# A17: em-dash in text, no "by:" token at all → author null, NO warning. The
# near-miss detector must not fire on ordinary prose.
D="$(mkalign a17 <<'EOF'
# Alignment: a17

## Task-Level

### Success criteria
- [ ] supports A — B mode
EOF
)"
arun "$D"
WARN17="$(jq -r '[.warnings[] | select(.code=="criterion_author_unrecognized")] | length' <<<"$OUT")"
if [ "$RC" -eq 0 ] \
  && [ "$(tlcrit 0 text)" = "supports A — B mode" ] \
  && [ "$(tlcrit 0 author)" = "null" ] \
  && [ "$WARN17" = "0" ]; then
  pass_check "A17 em-dash without by: token: no near-miss warning"
else
  fail_check "A17 em-dash without by: token: no near-miss warning" \
    "text=$(tlcrit 0 text) author=$(tlcrit 0 author) warn=$WARN17 rc=$RC"
fi

# ---------------------------------------------------------------------------
echo "----"
echo "alignment-read-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
