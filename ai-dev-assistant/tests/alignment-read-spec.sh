#!/usr/bin/env bash
# Spec for scripts/alignment-read.sh — focuses on the v1.1 optional per-criterion
# `verification` suffix (` — verify: <note>`) and its backward compatibility.
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
echo "----"
echo "alignment-read-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
