#!/usr/bin/env bash
# checks-can-fail-spec.sh — every assertion is one place the layer reported
# success it had not earned. A check that cannot fail cannot inform.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="${PLUGIN_ROOT}/scripts/visual-regression-gate.sh"
BM="${PLUGIN_ROOT}/scripts/baseline-manager.sh"
READER="${PLUGIN_ROOT}/scripts/screenshot-store-read.sh"
READER_SPEC="${PLUGIN_ROOT}/tests/screenshot-store-read-spec.sh"
SETUP="${PLUGIN_ROOT}/commands/setup-visual-regression.md"
VALIDATE="${PLUGIN_ROOT}/commands/validate-visual-regression.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# === A gate run that checked nothing must not exit 0 ===
# No visual projects in the config: the gate warned, emitted an all-zero summary
# and exited 0, while the rebaseline script treats the identical condition as
# fatal. One of them is wrong and it is not the one that refuses.
CP="$TMP/noproj"; mkdir -p "$CP/tests/visual"
printf 'export default { projects: [] };\n' > "$CP/playwright.config.ts"
printf 'schema_version: "1.3"\nsurfaces: []\n' > "$CP/registry.yml"
RC=0; bash "$GATE" "$CP/registry.yml" "$CP" >/dev/null 2>&1 || RC=$?
if [ "$RC" -ne 0 ]; then
  pass_check "no visual projects → gate exits non-zero (checked nothing is not a pass)"
else
  fail_check "no visual projects → gate exited 0 having run no surface"
fi

# === The consumer must read the exit code, not just parse stdout ===
# The gate exits 2 with an actionable message on stderr and NOTHING on stdout.
# `jq empty` succeeds on empty input, so a consumer checking only that concludes
# the JSON was valid and proceeds, and the stderr message is never shown.
if printf '' | jq empty 2>/dev/null; then
  : # confirms the trap is real: jq empty passes on empty input
  if grep -qiE 'exit code|exit status|non-zero' "$VALIDATE"; then
    pass_check "the command inspects the gate's exit code"
  else
    fail_check "the command checks only that stdout parses, and jq empty passes on empty"
  fi
else
  fail_check "harness assumption wrong: jq empty rejected empty input"
fi

# The file DOES say "surface stderr" — but only inside the `jq empty` branch,
# which never fires on empty input. Surfacing must be tied to the exit code.
if grep -B3 -A3 -iE 'stderr' "$VALIDATE" | grep -qiE 'exit code|exit status|non-zero'; then
  pass_check "stderr is surfaced on a non-zero exit, not only when parsing fails"
else
  fail_check "stderr is surfaced only when jq fails, which is the case that never happens"
fi

# === A rebaseline that wrote nothing must not be recorded as one that did ===
if grep -qE 'playwright_exit|"updated"|surfaces_updated' "$BM"; then
  if grep -qE 'HISTORY_ENTRY' "$BM" && grep -A15 'HISTORY_ENTRY=' "$BM" | grep -qE 'playwright_exit|updated'; then
    pass_check "the history entry records whether the rebaseline actually wrote"
  else
    fail_check "the history entry still records what was planned, not what happened"
  fi
else
  fail_check "the rebaseline records no outcome at all"
fi

# An over-narrow or invalid pattern that plans zero surfaces is not a success.
if grep -qE 'no_surfaces_matched|matched no surface|planned zero' "$BM"; then
  pass_check "a rebaseline that matched no surface says so rather than succeeding"
else
  fail_check "an invalid pattern still exits 0 having written nothing"
fi

# The execute stage must not mix console output into its JSON.
# Match INVOCATIONS, not prose. The first version of this check matched any line
# containing the string, so a header comment mentioning the command counted as an
# unredirected run — which pushed an implementer to reword documentation to
# satisfy a grep. A spec that forces prose changes is measuring the wrong thing.
if grep -nE '^[^#]*npx playwright' "$BM" | grep -qvE '>[[:space:]]*"?\$|>/dev/null|PLAYWRIGHT_JSON_OUTPUT_NAME|2>&1'; then
  fail_check "the rebaseline runs Playwright unredirected, so its stdout cannot be parsed"
else
  pass_check "the rebaseline redirects Playwright away from its own JSON output"
fi

# === Diagnostics the components emit must reach a consumer ===
# Anchored to the SPECIFIC warnings each command's own script emits, not to any
# mention of the word: the recipe loader's warnings and the gate's token warnings
# both matched a loose grep while the real diagnostics stayed discarded.
if grep -qE 'folder_missing' "$SETUP"; then
  pass_check "setup reads the project-state warnings before branching on codePath"
else
  fail_check "setup discards the folder_missing warning and gives the wrong remediation"
fi
if grep -qE 'meta_schema_mismatch|store reader.*warnings|reader.s `warnings`' "$VALIDATE"; then
  pass_check "the command reads the store reader's warnings"
else
  fail_check "the command consumes the store reader while discarding the warnings that explain its failures"
fi

# === The reader must not report a surface that no longer exists ===
# The reader needs the registry to know what is registered. Supplying one is the
# point: the first version of this check called the reader WITHOUT a registry and
# demanded the orphan vanish, which would have required the reader to GUESS that
# an empty directory is a leftover rather than a surface never yet baselined.
# Guessing is the failure class this file exists to catch, so the check was wrong.
# An orphan is MARKED, not dropped — dropping it silently loses information a
# consumer may want.
CP2="$TMP/orphan"; mkdir -p "$CP2/tests/visual/gone.spec.ts-snapshots"
mkdir -p "$CP2/tests/visual/live.spec.ts-snapshots"
: > "$CP2/tests/visual/live.spec.ts-snapshots/live-visual-chromium-lg-linux.png"
cat > "$CP2/registry.yml" <<'YML'
schema_version: "1.3"
surfaces:
  - id: live
    url: /
    gates: [visual_regression]
YML
OUT=$(bash "$READER" "$CP2" --registry "$CP2/registry.yml" 2>/dev/null || true)
if printf '%s' "$OUT" | jq -e '.components[] | select(.name=="gone") | .orphan == true' >/dev/null 2>&1; then
  pass_check "an unregistered leftover directory is marked as an orphan"
else
  fail_check "an orphan snapshot directory is indistinguishable from a real component"
fi

# And with NO registry the reader must say the cross-reference did not run,
# rather than reporting a clean list it had no basis for.
OUT_NR=$(bash "$READER" "$CP2" 2>/dev/null || true)
if printf '%s' "$OUT_NR" | jq -e '.registry_checked == false' >/dev/null 2>&1 \
   || printf '%s' "$OUT_NR" | jq -e '[.warnings[]?.code] | index("registry_not_checked")' >/dev/null 2>&1; then
  pass_check "without a registry the reader reports that it did not cross-reference"
else
  fail_check "without a registry the reader reports a component list it cannot vouch for"
fi

# === The reader's own spec must exercise the shape the plugin produces ===
# It only ever built ordinal-form fixtures, which is why the defect survived it.
# An ordinal filename CONTAINS the no-ordinal substring, so match must exclude a
# preceding numeric segment. Every existing fixture is ordinal-form, which is
# exactly why the defect survived this suite.
if grep -oE '[a-z-]+-visual-chromium-[a-z0-9]+-linux\.png' "$READER_SPEC" \
   | grep -qvE '^[a-z-]*-?[0-9]+-visual-chromium'; then
  pass_check "the reader's spec builds the no-ordinal fixtures its template produces"
else
  fail_check "the reader's spec only builds ordinal fixtures, so it looks where the bug is not"
fi

# === A digest tool that is absent must not produce a blank digest ===
# macOS ships shasum and no sha256sum; coreutils ships the reverse. A bare call to
# either returns EMPTY on the other platform, and an empty hash gets written or
# compared as though it were real.
for F in "$PLUGIN_ROOT/scripts/screenshot-store-write.sh" "$PLUGIN_ROOT/scripts/screenshot-store-read.sh" "$BM"; do
  N=$(basename "$F")
  if grep -qE 'shasum' "$F" && grep -qE 'sha256sum' "$F"; then
    pass_check "$N resolves a checksum tool rather than assuming one"
  else
    fail_check "$N calls one checksum tool with no fallback — silently blank on the other platform"
  fi
done

# === A re-run must not rename a viewport out from under committed baselines ===
# A viewport name is a path segment in every baseline filename, so renaming it
# orphans every baseline for that viewport.
if grep -qiE 'viewport NAMES already in the registry win|existing names' "$SETUP"; then
  pass_check "a re-run keeps existing viewport names rather than re-deriving them"
else
  fail_check "a re-run can rename a viewport, orphaning every baseline filed under the old name"
fi

# === An existing spec from an older template must not be skipped silently ===
if grep -qE 'Check an existing spec before skipping it|predates the shared settle' "$SETUP"; then
  pass_check "an outdated spec is reported rather than silently skipped"
else
  fail_check "an upgrade leaves existing surfaces on the old capture with no mention"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && printf 'checks-can-fail-spec: all checks passed\n' || printf 'checks-can-fail-spec: FAILURES above\n' >&2
exit "$FAIL"
