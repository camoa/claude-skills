#!/usr/bin/env bash
# gate-verdict-resolve-spec.sh — the gate-verdict mapping, checked by RUNNING it against
# real report files and by reading the scripts that produce them.
#
# WHY THIS FILE REPLACES A PILE OF PROSE ASSERTIONS. Three rounds of this work encoded the
# mapping as instructions in `validate-*.md` and asserted it by grepping those same files.
# Every assertion compared our prose to our prose, and not one opened `security-check.sh`.
# Four field paths that do not exist survived all three rounds:
#
#   .status on security-report.json        it is .summary.overall_status. The wrapper read
#                                          null, called it "unrecognised", returned warning,
#                                          and a fully tooled project with a CRITICAL
#                                          finding went green — worse than the original bug.
#   .meta.tools in --changed mode          that mode emits tools_run / tools_skipped. The
#                                          default /review path could detect no coverage
#                                          gap at all.
#   .meta.tools' literal contents          names phpcs_security_linter / psalm_taint /
#                                          roave while the code pushes php-security-linter
#                                          and psalm and never pushes roave.
#   .tools_failed on dry-report.json       dry emits no such key on any path.
#
# So this spec does two things prose assertions cannot:
#
#   1. FIELD PATHS ARE CHECKED AGAINST THE PRODUCER. Every path the resolver declares is
#      looked up in the gate script that writes the report, by walking that script's own
#      JSON emitters. The path list is DERIVED from the resolver (`--field-paths`), so a
#      path cannot be added without being checked. This is the assertion that would have
#      caught all four above, and it is the most important thing in this file.
#   2. THE MAPPING IS EXECUTED. Fixture reports under tests/fixtures/gate-reports/ cover
#      one state per mode, and each asserts the verdict and the two markers the resolver
#      returns. A fixture is a claim someone can run.
#
# Exit 0 on all-pass; 1 on any fail.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_ROOT}/.." && pwd)"
R="${PLUGIN_ROOT}/scripts/gate-verdict-resolve.sh"
PATHS_TOOL="${PLUGIN_ROOT}/tests/lib/emitted-json-paths.py"
FIX="${PLUGIN_ROOT}/tests/fixtures/gate-reports"
CQT="${REPO_ROOT}/code-quality-tools"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

for f in "$R" "$PATHS_TOOL"; do
  [ -f "$f" ] || { printf 'FAIL: %s missing\n' "$f" >&2; exit 1; }
done
[ -d "$FIX" ] || { printf 'FAIL: fixture directory %s missing\n' "$FIX" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 required\n' >&2; exit 1; }

# ==========================================================================================
# 1. FIELD PATHS — every path the resolver reads is emitted by the script that writes it.
# ==========================================================================================

DECL=$(bash "$R" --field-paths 2>/dev/null || true)
if printf '%s' "$DECL" | jq -e . >/dev/null 2>&1; then
  pass_check "resolver publishes its field paths as JSON (--field-paths)"
else
  fail_check "resolver's --field-paths is not valid JSON — the path list cannot be derived, only copied"
  printf '\ngate-verdict-resolve-spec: FAILURES\n' >&2
  exit 1
fi

GATES=$(printf '%s' "$DECL" | jq -r 'keys[]')
CHECKED_PATHS=0
for gate in $GATES; do
  PRODUCER=$(printf '%s' "$DECL" | jq -r --arg g "$gate" '.[$g].producer')
  PFILE="${CQT}/${PRODUCER}"
  if [ ! -f "$PFILE" ]; then
    fail_check "$gate: declared producer $PRODUCER does not exist — the paths below are checked against nothing"
    continue
  fi
  mapfile -t PLIST < <(printf '%s' "$DECL" | jq -r --arg g "$gate" '.[$g].paths[]?')
  if [ "${#PLIST[@]}" -eq 0 ]; then
    # tdd declares none, deliberately: it writes no report. That is a claim too.
    if printf '%s' "$DECL" | jq -er --arg g "$gate" '.[$g].note' 2>/dev/null | grep -qi 'no JSON report'; then
      pass_check "$gate declares no field paths and says why (it writes no report)"
    else
      fail_check "$gate declares no field paths and gives no reason — a gate that reads nothing decides on nothing"
    fi
    continue
  fi
  if OUT=$(python3 "$PATHS_TOOL" "$PFILE" "${PLIST[@]}" 2>&1); then
    pass_check "$gate: all ${#PLIST[@]} declared paths are emitted by $(basename "$PRODUCER")"
    CHECKED_PATHS=$((CHECKED_PATHS + ${#PLIST[@]}))
  else
    fail_check "$gate: declared paths NOT emitted by $(basename "$PRODUCER") — $(printf '%s' "$OUT" | tr '\n' ' ')"
  fi
done

if [ "$CHECKED_PATHS" -ge 15 ]; then
  pass_check "field-path check covered $CHECKED_PATHS paths across the producers"
else
  fail_check "field-path check only covered $CHECKED_PATHS paths — it is not looking at enough to mean anything"
fi

# The checker itself must be able to FAIL, or the block above is decoration. Ask it for
# the three paths that burned us and require it to reject each one.
SEC="${CQT}/skills/code-quality-audit/scripts/drupal/security-check.sh"
DRYP="${CQT}/skills/code-quality-audit/scripts/drupal/dry-check.sh"
NEXTSOLID="${CQT}/skills/code-quality-audit/scripts/nextjs/solid-check.sh"
for probe in "$SEC:.status:security has no top-level .status" \
             "$DRYP:.tools_failed:dry-report.json has no tools_failed" \
             "$NEXTSOLID:.tools_absent:the Next.js solid emitter has no tool lists"; do
  pf="${probe%%:*}"; rest="${probe#*:}"; pp="${rest%%:*}"; why="${rest#*:}"
  if [ -f "$pf" ] && python3 "$PATHS_TOOL" "$pf" "$pp" >/dev/null 2>&1; then
    fail_check "the path checker accepted $pp on $(basename "$pf") — $why, so the checker cannot fail"
  else
    pass_check "path checker rejects $pp on $(basename "$pf") ($why)"
  fi
done

# And the reverse direction: a path READ in the resolver must be DECLARED. Otherwise a new
# read slips in unchecked, which is exactly how .status got there.
ALL_DECLARED=$(printf '%s' "$DECL" | jq -r '[.[].paths[]?] | unique | .[]')
UNDECLARED=""
while IFS= read -r used; do
  [ -n "$used" ] || continue
  case "$used" in .timestamp) continue ;; esac   # freshness fallback, common to all shapes
  printf '%s\n' "$ALL_DECLARED" | grep -qxF "$used" || UNDECLARED="${UNDECLARED} ${used}"
done < <(grep -oE "jq(r|len|join) '\.[a-z_.]+'" "$R" | sed -E "s/.*'(\.[a-z_.]+)'/\1/" | sort -u)
if [ -z "$UNDECLARED" ]; then
  pass_check "every report path the resolver reads is declared in --field-paths"
else
  fail_check "resolver reads undeclared paths (never checked against a producer):${UNDECLARED}"
fi

# ==========================================================================================
# 2. THE MAPPING, EXECUTED — one fixture per state, per mode.
# ==========================================================================================

# expect <fixture> <gate> <verdict> <unresolved> <coverage_partial> <what it proves>
expect() {
  local fx="$1" gate="$2" want_v="$3" want_u="$4" want_p="$5" why="$6"; shift 6
  local path="${FIX}/${fx}"
  if [ ! -f "$path" ]; then fail_check "fixture $fx missing"; return; fi
  local out
  if ! out=$(bash "$R" "$gate" "$path" "$@" 2>/dev/null); then
    fail_check "$fx: resolver exited non-zero"; return
  fi
  local v u p
  v=$(printf '%s' "$out" | jq -r '.verdict')
  u=$(printf '%s' "$out" | jq -r '.unresolved')
  p=$(printf '%s' "$out" | jq -r '.coverage_partial')
  if [ "$v" = "$want_v" ] && [ "$u" = "$want_u" ] && [ "$p" = "$want_p" ]; then
    pass_check "$fx → $v (unresolved=$u partial=$p) — $why"
  else
    fail_check "$fx → $v/$u/$p, expected $want_v/$want_u/$want_p — $why"
  fi
  # The markers the wrappers hand to /review are emitted by the resolver, not by a caller
  # who might forget. Verify they track the booleans.
  if [ "$u" = "true" ] && ! printf '%s' "$out" | jq -e '.messages[] | select(. == "unresolved: true")' >/dev/null 2>&1; then
    fail_check "$fx: unresolved true but no 'unresolved: true' in messages[] — /review reads the string, not the field"
  fi
  if [ "$p" = "true" ] && ! printf '%s' "$out" | jq -e '.messages[] | select(. == "coverage_partial: true")' >/dev/null 2>&1; then
    fail_check "$fx: coverage_partial true but no 'coverage_partial: true' in messages[]"
  fi
  if [ "$u" = "true" ] && [ "$p" = "true" ]; then
    fail_check "$fx: both markers set — nothing-measured and part-measured are different facts"
  fi
}

# ------------------------------------------------------------------ dry: ONE analyzer
expect dry-whole-clean.json     dry pass    false false "measured, within target"
expect dry-whole-warning.json   dry warning false false "6% duplication: a FULL measurement over a soft threshold, not a coverage gap"
expect dry-whole-fail.json      dry fail    false false "over the hard threshold"
expect dry-tool-absent.json     dry skipped true  false "phpcpd absent — its only analyzer, so nothing was measured"
expect dry-unmeasured.json      dry skipped true  false "the gate's own unmeasured state (exit 4)"
expect dry-changed-partial.json dry warning false true  "changed files not on disk — part of the change unread"

# ----------------------------------------------------- solid: multi-analyzer, the trap
expect solid-whole-clean.json      solid pass    false false "every analyzer ran, nothing over threshold"
expect solid-whole-warning.json    solid warning false false "11 SOLID warnings with every tool present — a full measurement"
expect solid-whole-fail.json       solid fail    false false "over the hard threshold"
expect solid-one-absent.json       solid warning false true  "phpmd absent while the gate still says pass — partial coverage"
expect solid-all-absent.json       solid skipped true  false "phpstan AND phpmd absent while analyzers_ran is 1 — THE analyzers_ran trap"
expect solid-tools-failed.json     solid skipped true  false "both binary analyzers crashed: no evidence, same as absent"
expect solid-tools-unmeasured.json solid warning false true  "phpmd had nothing to read"
expect solid-changed-partial.json  solid warning false true  "the gate's own status:partial"
expect solid-unmeasured.json       solid skipped true  false "the gate's own unmeasured state"
expect solid-nextjs-no-lists.json  solid pass    false false "Next.js emitter has NO tool lists: coverage undetermined, which is NOT nothing-ran"

# --------------------------------------------------------- security: both report modes
expect sec-whole-clean.json      security pass    false false "every layer ran, nothing over threshold"
expect sec-whole-warning.json    security warning false false "findings under the fail threshold, every layer present"
expect sec-whole-fail.json       security fail    false false "CRITICAL finding — the case the .status slip turned green"
expect sec-whole-absent.json     security warning false true  "gitleaks and semgrep absent while the gate says pass"
expect sec-fail-with-absent.json security fail    false true  "a real fail AND a coverage gap: the fail is not softened"
expect sec-status-partial.json   security warning false true  "the gate's own status:partial"
expect sec-unmeasured.json       security skipped true  false "the gate's own unmeasured state"
expect sec-skipped.json          security skipped true  false "zero findings but tools returned nothing usable"
expect sec-changed-clean.json    security pass    false false "--changed mode, /review's DEFAULT path, fully covered"
expect sec-changed-zero.json     security skipped true  false "--changed mode with analyzers_ran 0"
expect sec-changed-partial.json  security warning false true  "--changed mode with gitleaks absent — invisible before this change"
expect sec-wrong-shape.json      security skipped true  false "a top-level .status, the shape the prose assumed: refuse to guess"

# ------------------------------------------------------------------ no report, bad report
if OUT=$(bash "$R" dry "${FIX}/does-not-exist.json" 2>/dev/null) \
   && [ "$(printf '%s' "$OUT" | jq -r '.unresolved')" = "true" ]; then
  pass_check "absent report → unresolved (a gate that wrote nothing cannot say what it measured)"
else
  fail_check "absent report did not resolve to unresolved"
fi
expect dry-malformed.json dry skipped true false "unparseable JSON → unresolved, never a guess"

# --------------------------------------------------------------------------------- tdd
# No report on any path; the exit code is the only channel.
for pair in "0:pass:false" "1:fail:false" "2:skipped:true" "4:skipped:true" "9:skipped:true"; do
  code="${pair%%:*}"; rest="${pair#*:}"; wv="${rest%%:*}"; wu="${rest##*:}"
  out=$(bash "$R" tdd "" --exit-code "$code" 2>/dev/null || true)
  v=$(printf '%s' "$out" | jq -r '.verdict' 2>/dev/null || echo ERR)
  u=$(printf '%s' "$out" | jq -r '.unresolved' 2>/dev/null || echo ERR)
  if [ "$v" = "$wv" ] && [ "$u" = "$wu" ]; then
    pass_check "tdd exit $code → $v (unresolved=$u)"
  else
    fail_check "tdd exit $code → $v/$u, expected $wv/$wu"
  fi
done
# And an ABSENT report must NOT make tdd unresolved: it never writes one, so that rule
# would fail-close every review on a gate behaving exactly as designed.
out=$(bash "$R" tdd "${FIX}/does-not-exist.json" --exit-code 0 2>/dev/null || true)
if [ "$(printf '%s' "$out" | jq -r '.unresolved')" = "false" ]; then
  pass_check "tdd with no report and exit 0 is NOT unresolved — it never writes one"
else
  fail_check "tdd treats its by-design absent report as unresolved — every review fail-closes"
fi

# ------------------------------------------------------------------------- freshness
# report-dir.sh can resolve to a dated directory and fall back to the newest existing one,
# so a rerun that dies before writing leaves the PREVIOUS report in place.
out=$(bash "$R" dry "${FIX}/dry-stale.json" --not-before "2026-08-29T00:00:00Z" 2>/dev/null || true)
if [ "$(printf '%s' "$out" | jq -r '.unresolved')" = "true" ]; then
  pass_check "a report generated before the run began is STALE → unresolved"
else
  fail_check "a stale report resolved to $(printf '%s' "$out" | jq -r '.verdict') — a previous run's green is read as this run's"
fi
out=$(bash "$R" dry "${FIX}/dry-whole-clean.json" --not-before "2026-08-29T00:00:00Z" 2>/dev/null || true)
if [ "$(printf '%s' "$out" | jq -r '.evidence.freshness')" = "fresh" ]; then
  pass_check "a report generated after the run began is fresh"
else
  fail_check "a fresh report was not reported fresh"
fi
out=$(bash "$R" dry "${FIX}/dry-whole-clean.json" 2>/dev/null || true)
if [ "$(printf '%s' "$out" | jq -r '.evidence.freshness')" = "unchecked" ]; then
  pass_check "without --not-before, freshness is reported 'unchecked' and never assumed"
else
  fail_check "freshness is silently assumed when no baseline is supplied"
fi

# ==========================================================================================
# 3. THE DIRECTIONAL PAIR — keyed off the resolver's OUTPUT, not off any file's wording.
# Getting this backwards ships a false green on every under-covered project, or a false red
# on every ordinary one. Both halves were previously asserted against review.md's phrasing
# and broke on a rewrite; a resolver's output is a value, and a value cannot be rephrased.
# ==========================================================================================

ORDINARY="dry-whole-warning.json:dry solid-whole-warning.json:solid sec-whole-warning.json:security"
for pair in $ORDINARY; do
  fx="${pair%%:*}"; gate="${pair##*:}"
  out=$(bash "$R" "$gate" "${FIX}/${fx}" 2>/dev/null || true)
  v=$(printf '%s' "$out" | jq -r '.verdict'); u=$(printf '%s' "$out" | jq -r '.unresolved'); p=$(printf '%s' "$out" | jq -r '.coverage_partial')
  if [ "$v" = "warning" ] && [ "$u" = "false" ] && [ "$p" = "false" ]; then
    pass_check "DIRECTION 1: $gate's ordinary measured warning carries NEITHER marker — it does not block"
  else
    fail_check "DIRECTION 1 FAILED: $gate's ordinary measured warning came back $v/$u/$p — a fully tooled project now fails /review for findings that never blocked"
  fi
done

PARTIAL="solid-one-absent.json:solid sec-whole-absent.json:security sec-changed-partial.json:security"
for pair in $PARTIAL; do
  fx="${pair%%:*}"; gate="${pair##*:}"
  out=$(bash "$R" "$gate" "${FIX}/${fx}" 2>/dev/null || true)
  p=$(printf '%s' "$out" | jq -r '.coverage_partial')
  if [ "$p" = "true" ]; then
    pass_check "DIRECTION 2: $gate's partial coverage ($fx) DOES carry the blocking marker"
  else
    fail_check "DIRECTION 2 FAILED: $fx carries no coverage_partial marker — a half-scanned gate reaches a green review"
  fi
done

# The two directions must be DISTINGUISHABLE, not merely both present: if the resolver
# marked everything, direction 2 would pass while meaning nothing.
NMARK=$(for pair in $ORDINARY $PARTIAL; do fx="${pair%%:*}"; gate="${pair##*:}";
  bash "$R" "$gate" "${FIX}/${fx}" 2>/dev/null | jq -r '.coverage_partial'; done | sort | uniq -c | wc -l)
if [ "$NMARK" -eq 2 ]; then
  pass_check "the marker discriminates: some of these six carry it and some do not"
else
  fail_check "every one of the six fixtures got the same marker value — it discriminates nothing"
fi

if [ "$FAIL" = "0" ]; then
  printf '\ngate-verdict-resolve-spec: all checks passed\n'
else
  printf '\ngate-verdict-resolve-spec: FAILURES\n' >&2
fi
exit "$FAIL"
