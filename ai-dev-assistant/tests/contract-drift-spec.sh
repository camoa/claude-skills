#!/usr/bin/env bash
# contract-drift-spec.sh — every assertion here is one place two components
# disagreed about a shared contract, so both could not be right.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
READER="${PLUGIN_ROOT}/scripts/screenshot-store-read.sh"
WRITER="${PLUGIN_ROOT}/scripts/screenshot-store-write.sh"
MIGRATE="${PLUGIN_ROOT}/scripts/migrate-screenshots-to-codepath.sh"
BM="${PLUGIN_ROOT}/scripts/baseline-manager.sh"
SETUP="${PLUGIN_ROOT}/commands/setup-visual-regression.md"
VALIDATE="${PLUGIN_ROOT}/commands/validate-visual-regression.md"
SCHEMA="${PLUGIN_ROOT}/references/visual-review/surface-registry-schema.md"
STORE_SCHEMA="${PLUGIN_ROOT}/references/screenshot-store-schema.md"
PRL="${PLUGIN_ROOT}/skills/process-recipe-loader/SKILL.md"
RL="${PLUGIN_ROOT}/skills/recipe-loader/SKILL.md"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# === The baseline filename grammar: one shape, agreed by every producer ===
# The reader must enumerate what the plugin's OWN template produces. Build a
# codePath the way setup does and ask the reader what it sees.
CP="$TMP/cp"; SNAP="$CP/tests/visual/home.spec.ts-snapshots"
mkdir -p "$SNAP"
for VP in xs md lg; do : > "$SNAP/home-visual-chromium-${VP}-linux.png"; done
OUT=$(bash "$READER" "$CP" 2>/dev/null || true)
COUNT=$(printf '%s' "$OUT" | jq -r '[.. | objects | select(has("viewports")) | .viewports[]?] | length' 2>/dev/null || echo 0)
if [ "${COUNT:-0}" -eq 3 ]; then
  pass_check "reader enumerates the no-ordinal names the starter template produces"
else
  fail_check "reader saw $COUNT of 3 baselines in the plugin's own default shape"
fi

# It must also DISTINGUISH: removing one has to change the answer.
rm -f "$SNAP/home-visual-chromium-md-linux.png"
OUT2=$(bash "$READER" "$CP" 2>/dev/null || true)
COUNT2=$(printf '%s' "$OUT2" | jq -r '[.. | objects | select(has("viewports")) | .viewports[]?] | length' 2>/dev/null || echo 0)
if [ "${COUNT2:-0}" -eq 2 ] && [ "$COUNT2" != "$COUNT" ]; then
  pass_check "reader can tell 3 baselines from 2"
else
  fail_check "reader returned $COUNT2 after a deletion (was $COUNT) — it cannot count"
fi

# An authed baseline carries a -<ctx> segment; the viewport must not absorb it.
mkdir -p "$CP/tests/visual/auth/editor/acct.spec.ts-snapshots"
: > "$CP/tests/visual/auth/editor/acct.spec.ts-snapshots/acct-visual-chromium-lg-editor-linux.png"
OUT3=$(bash "$READER" "$CP" 2>/dev/null || true)
# A viewport entry is an object, not a bare string — compare its .viewport field.
if printf '%s' "$OUT3" | jq -e '[.components[]?.viewports[]?.viewport] | any(. == "lg")' >/dev/null 2>&1; then
  pass_check "authed baseline reports its viewport, not viewport-plus-context"
else
  fail_check "authed baseline's context is folded into the viewport name"
fi

# Authenticated surfaces are scaffolded two directories deeper, under
# tests/visual/auth/<ctx>/. The reader used to search at depth 1 only, so an
# authed baseline was not mis-parsed — it was never scanned. A count built on
# this reader silently omitted every authenticated surface.
if grep -qE 'find .*-maxdepth 1 .*spec\.ts-snapshots' "$READER"; then
  fail_check "reader searches at depth 1, so authenticated surfaces are invisible to it"
else
  pass_check "reader searches deep enough to see authenticated surfaces"
fi

# The docs promise a reader that accepts either shape. Make that true.
: > "$SNAP/home-1-visual-chromium-xs-linux.png"
if bash "$READER" "$CP" 2>/dev/null | grep -q 'meta_schema_mismatch'; then
  fail_check "reader still rejects the ordinal shape its own docs promise to accept"
else
  pass_check "reader accepts both filename shapes, as documented"
fi

# The migration script is a third producer of the same grammar.
if grep -qE 'visual-chromium' "$MIGRATE"; then
  pass_check "migration script writes the shared grammar"
else
  fail_check "migration script does not write the shared filename grammar"
fi

# === Rebaseline reads the registry it is handed ===
if grep -qE '\-\-registry' "$BM" && grep -qiE 'viewports' "$BM"; then
  if grep -qF 'This script does NOT parse registry.yml' "$BM"; then
    fail_check "rebaseline header still declares registry-blindness as intended"
  else
    pass_check "rebaseline header no longer declares registry-blindness"
  fi
else
  fail_check "rebaseline does not take viewports from the registry"
fi

# === Scoping a rebaseline to ONE surface ===
if grep -qE 'exact-surface|\\\\b' "$BM"; then
  pass_check "rebaseline can scope to exactly one surface"
else
  fail_check "rebaseline pattern still over-matches sibling surfaces"
fi
if grep -qE 'exact-surface|surface-id>\\\\b' "$VALIDATE"; then
  pass_check "the command prescribes a pattern that scopes to one surface"
else
  fail_check "the command still prescribes the over-matching pattern"
fi

# === Provenance: one enum, and the documented value is in it ===
# Prose wraps, so flatten before matching: the provenance argument sits across
# two lines in the command and a line-anchored grep sees neither half.
VFLAT=$(tr '\n' ' ' < "$VALIDATE")
DOCVAL=$(printf '%s' "$VFLAT" | grep -oE 'write-baseline-codepath[^`]*' | head -1 \
  | grep -oE '(framework-)?playwright(-accessible)?' | head -1 || true)
if [ -n "$DOCVAL" ] && grep -qF -- "$DOCVAL" "$WRITER"; then
  pass_check "the provenance value the command documents is accepted by the writer"
else
  fail_check "the command documents provenance value '${DOCVAL:-none}' that the writer rejects"
fi

# Two subcommands must not disagree about which values are legal. Compare the
# distinct accepted-value sets the file declares.
SETS=$(grep -oE "playwright(-accessible)?\)" "$WRITER" | sort -u | tr -d ')' | sort | tr '\n' ',')
CASES=$(grep -cE '^\s*playwright\|playwright-accessible\)|^\s*playwright\)' "$WRITER" || true)
if [ "${CASES:-0}" -le 1 ]; then
  pass_check "the writer states one provenance enum, not two"
else
  fail_check "the writer declares $CASES separate provenance enums (values seen: ${SETS%,})"
fi

# === The registry has one home and one version ===
if grep -qE 'memory project folder' "$SCHEMA"; then
  fail_check "schema still puts the registry in the memory project folder"
else
  pass_check "schema and command agree the registry lives at the code path"
fi
# A changelog legitimately names old versions. What must agree is the version
# the document claims to BE: its title, its section heading, and its example.
SELF=$(grep -nE '^# .*v1\.[0-9]|^## .*v1\.[0-9]|schema_version: *"1\.[0-9]"' "$SCHEMA" \
  | grep -oE '1\.[0-9]' | sort -u | tr '\n' ' ')
if [ "$(printf '%s' "$SELF" | wc -w | tr -d ' ')" = "1" ]; then
  pass_check "schema states one version of itself ($SELF)"
else
  fail_check "schema contradicts itself about its own version: $SELF"
fi
SFLAT=$(tr '\n' ' ' < "$SETUP")
if printf '%s' "$SFLAT" | grep -qE 'schema[[:space:]]+v1\.2'; then
  fail_check "setup still cites the superseded schema version"
else
  pass_check "setup cites the current schema version"
fi

# === Adding a surface twice cannot produce an invalid registry ===
# Anchor to the --add-surface path; "already" appears all over an idempotent
# command and matched something unrelated.
if sed -n '/--add-surface/,/^## /p' "$SETUP" | grep -qiE 'uniqu|already (registered|in the registry|present)'; then
  pass_check "adding a surface checks the id is not already registered"
else
  fail_check "--add-surface appends without a uniqueness check"
fi

# === A gate token outside the vocabulary is not a clean skip ===
if grep -qiE 'unrecognis|unrecognized|unknown gate|not in the schema' "$VALIDATE"; then
  pass_check "an unknown gate token is surfaced rather than silently skipped"
else
  fail_check "an out-of-vocabulary gate token still produces a clean skip"
fi

# === Skill bodies: no bare positional parameters ===
for F in "$PRL" "$RL"; do
  N=$(basename "$(dirname "$F")")
  if awk '/^```bash/{inb=1;next} /^```/{inb=0} inb' "$F" | grep -qE '\$\{?[1-9]\}?'; then
    fail_check "$N still uses bare positional parameters inside bash blocks"
  else
    pass_check "$N uses named variables, so caller arguments cannot overwrite them"
  fi
  if grep -qE '^version: 0\.1\.0' "$F"; then
    fail_check "$N still declares version 0.1.0"
  else
    pass_check "$N declares a version that moves when it changes"
  fi
done

printf '\n'
[ "$FAIL" -eq 0 ] && printf 'contract-drift-spec: all checks passed\n' || printf 'contract-drift-spec: FAILURES above\n' >&2
exit "$FAIL"
