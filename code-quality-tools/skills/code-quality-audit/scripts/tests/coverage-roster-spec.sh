#!/usr/bin/env bash
# Spec: every layer a gate DECLARES in a reported list must be a name that gate can
# actually PUSH into a coverage array.
#
# Two live wrong answers came out of the same construct, one per stack.
#
#   drupal/security-check.sh declared `phpcs_security_linter`, `psalm_taint` and `roave`
#   while its code pushed `php-security-linter` and `psalm`. A consumer computing
#   coverage as `declared - reported` therefore saw three layers permanently missing and
#   two layers it had never heard of, in a file whose two vocabularies sat three lines
#   apart in the same report.
#
#   nextjs/security-check.sh declared `socket` and pushed it nowhere at all, so a
#   missing Socket CLI could not reach any coverage list.
#
# Neither was visible to any assertion, because every existing assertion reads the
# PUSHED lists and none reads the declared roster. This one reads both and diffs them.
#
# DERIVED, never registered. The declared set comes out of the report literals the gate
# itself writes and the pushed set out of its own assignment sites, so adding a layer to
# a gate and forgetting to record it goes red without anybody updating a list here.
#
# ONE DIRECTION ONLY: declared ⊆ pushed. The reverse is legitimate —
# nextjs/solid-check.sh's `binary_analyzers` deliberately names only the layers that
# need a binary, and pushes `large_files` and `typescript_strict` besides.
#
# Written for bash 3.2, like its siblings.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0; FAIL=0
ERRORS=""
ok()  { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); ERRORS="${ERRORS}FAIL: $1"$'\n'; echo "  FAIL: $1"; }

assert_eq() {
  desc="$1"; want="$2"; got="$3"
  if [ "$want" = "$got" ]; then ok "$desc"; else bad "$desc | want '$want', got '$got'"; fi
}

# Every literal array in this file that a consumer reads as a list of layer names.
#
#   `tools:` / `tools_run:` / `tools_skipped:` / `tools_absent:` ...  the report's own
#       keys, quoted or bare, in a jq program or a heredoc.
#   `BINARY_ANALYZERS='[...]'`                                        the roster the
#       SOLID gates emit as binary_analyzers[].
#   `(["a","b"] + $var)`                                              a jq union whose
#       hardcoded half is a list of names — drupal/security-check.sh builds its
#       by-design list this way, and a regex reading only `key: [` walks past it.
declared_names() {
  {
    grep -ohE '"?tools(_run|_skipped|_absent|_failed|_unmeasured)?"?[[:space:]]*:[[:space:]]*\[[^]]*\]' "$1" 2>/dev/null
    grep -ohE "BINARY_ANALYZERS=.\[[^]]*\]" "$1" 2>/dev/null
    grep -ohE '\(\[[^]]*\][[:space:]]*\+[[:space:]]*\$[A-Za-z_]' "$1" 2>/dev/null
  } | sed 's/^[^[]*\[//' \
    | grep -ohE '"[A-Za-z][A-Za-z0-9_.-]*"' 2>/dev/null | tr -d '"' | sort -u
}
# The `sed` is load-bearing: the key is quoted in a heredoc (`"tools_unmeasured": [...]`)
# and without dropping everything before the `[`, the KEY is extracted as if it were one
# of the names inside the array.

# Where a name enters a coverage array. `_BY_DESIGN` is in the pattern because
# nextjs/solid-check.sh records its by-design skips in SKIPPED_BY_DESIGN, and a regex
# reading only `*_TOOLS+=` misses that whole half.
pushed_names() {
  grep -ohE '[A-Z_]+(_TOOLS|_BY_DESIGN)\+=\("[^"]+"\)' "$1" 2>/dev/null \
    | grep -ohE '"[^"]+"' | tr -d '"' | sort -u
}

echo "═══ coverage-roster-spec ═══"
echo ""

GATES=""
for d in drupal nextjs; do
  for f in "${SCRIPTS}/${d}"/*-check.sh; do
    [ -f "$f" ] || continue
    GATES="${GATES}${f}"$'\n'
  done
done

GATE_COUNT="$(printf '%s' "$GATES" | grep -c . || true)"
# A spec that examined no gate has not passed anything.
if [ "${GATE_COUNT}" -lt 4 ]; then
  bad "[ROSTER] found only ${GATE_COUNT} gate script(s) under ${SCRIPTS}/{drupal,nextjs}; the diff below compared almost nothing"
fi

EXAMINED=0
SKIPPED_NO_ARRAYS=""
TOTAL_DECLARED=0

while IFS= read -r gate; do
  [ -n "$gate" ] || continue
  rel="${gate#"${SCRIPTS}"/}"
  pushed="$(pushed_names "$gate")"
  declared="$(declared_names "$gate")"

  # A single-analyzer gate (drupal/dry-check.sh, nextjs/dry-check.sh) has no coverage
  # arrays at all: it records absence inline in its one report. Nothing to diff, and
  # holding its inline `"tools_absent": ["jscpd"]` against a push site that does not
  # exist would fail a file that is already honest. Named rather than silently dropped.
  if [ -z "$pushed" ]; then
    SKIPPED_NO_ARRAYS="${SKIPPED_NO_ARRAYS}${rel} "
    continue
  fi

  EXAMINED=$((EXAMINED + 1))
  n_declared="$(printf '%s\n' "$declared" | grep -c . || true)"
  TOTAL_DECLARED=$((TOTAL_DECLARED + n_declared))

  missing="$(comm -23 \
      <(printf '%s\n' "$declared" | grep . | sort -u) \
      <(printf '%s\n' "$pushed"   | grep . | sort -u) | paste -sd, -)"

  assert_eq "[ROSTER] ${rel}: every declared layer has a push site" "" "${missing}"
done <<EOF
${GATES}
EOF

echo ""
echo "  gates with coverage arrays: ${EXAMINED}"
echo "  declared names compared:    ${TOTAL_DECLARED}"
echo "  single-analyzer gates, no coverage arrays to diff: ${SKIPPED_NO_ARRAYS:-none}"

# The extraction itself has to be load-bearing. If either half silently returned nothing
# the diff above would be empty for every gate and every assertion would pass having
# compared two empty sets — which is the failure mode this whole spec exists to refuse.
assert_eq "[ROSTER] the declared-set extraction actually found names" "yes" \
  "$([ "${TOTAL_DECLARED}" -ge 20 ] && echo yes || echo "no (${TOTAL_DECLARED})")"
assert_eq "[ROSTER] and at least four gates carry coverage arrays to compare against" "yes" \
  "$([ "${EXAMINED}" -ge 4 ] && echo yes || echo "no (${EXAMINED})")"

echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
if [ -n "$ERRORS" ]; then
  echo ""
  printf '%s' "$ERRORS"
  exit 1
fi
exit 0
