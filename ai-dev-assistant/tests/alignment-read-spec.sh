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
echo "----"
echo "alignment-read-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
