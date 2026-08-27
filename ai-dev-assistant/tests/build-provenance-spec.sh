#!/usr/bin/env bash
# build-provenance-spec.sh — a record must be able to say which build wrote it, and a
# dependency check must actually check the version it names.
#
# Both defects surfaced from the same live transcript, and the first is why the second
# took three greps to diagnose. A Phase 3 round improvised a test-runner install that a
# sibling plugin owns. Deciding whether that was a current-build failure or a stale-build
# replay of an already-fixed one should have been readable off the task folder. It was
# not: every gate audit records the payload schema, the gate type, the time and the task
# folder, and no record anywhere says which plugin version produced it. The answer had to
# be reconstructed from cached script paths quoted in a chat transcript.
#
# The same transcript resolved a sibling plugin's path with a lexically-sorted glob and
# read version 3.9.6 while 3.9.8 sat in the same directory. And the four /validate-*
# wrappers each confirmed that directory was "non-empty" and then declared a minimum
# supported version that nothing compared against.
#
# Both are the house shape: a record that cannot say what it does not know, and a check
# that cannot fail.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"
D="${PLUGIN_ROOT}/scripts/plugin-dep-check.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
# A check that could not be set up is neither a pass nor a failure, and it must not vanish
# quietly: an assertion that disappears without saying so is how a suite reports a smaller
# green than it looks. One check below stages a permission failure, which cannot be staged
# at all when the process ignores permission bits (running as root), so it says so.
skip_check() { printf 'SKIP %s\n' "$1"; printf 'SKIP %s\n' "$1" >&2; }
[ -f "$W" ] || { printf 'FAIL: %s missing\n' "$W" >&2; exit 1; }
[ -f "$D" ] || { printf 'FAIL: %s missing\n' "$D" >&2; exit 1; }
[ -x "$D" ] || fail_check "plugin-dep-check.sh is not executable"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
REAL_VERSION=$(jq -r '.version' "${PLUGIN_ROOT}/.claude-plugin/plugin.json")

# ------------------------------------------------- the stamp, on the bare-payload path

mkdir -p "$T/bare"
bash "$W" "$T/bare" dev-guides-load '{"verdict":"pass"}' >/dev/null 2>&1 || true
A="$T/bare/_dev-guides-load.json"
if [ -f "$A" ]; then
  jq -e 'has("plugin_version")' "$A" >/dev/null 2>&1 \
    && pass_check "a bare payload comes back carrying plugin_version" \
    || fail_check "bare payload has no plugin_version — the record cannot say which build wrote it"
  [ "$(jq -r '.plugin_version' "$A")" = "$REAL_VERSION" ] \
    && pass_check "the stamp is this plugin's real version ($REAL_VERSION)" \
    || fail_check "stamp is $(jq -r '.plugin_version' "$A"), expected $REAL_VERSION"
  [ "$(jq -r '.plugin_version | type' "$A")" = "string" ] \
    && pass_check "plugin_version is a string" \
    || fail_check "plugin_version is not a string"
else
  fail_check "no audit written on the bare-payload path"
fi

# ------------------------------------------------ the stamp, on the full-envelope path
#
# And a caller claiming a version must not be believed. Same rule as fired_at: a caller
# that cannot read its own version cannot stamp one, and a wrong version reads as evidence.

mkdir -p "$T/full"
bash "$W" "$T/full" preconditions \
  '{"gate_type":"preconditions","task_folder":"/x","plugin_version":"9.9.9-CALLER-LIE","gate_specific":{"phase":"implement","declared":true,"verdict":"met","preconditions":[]}}' \
  >/dev/null 2>&1 || true
B="$T/full/_preconditions.json"
if [ -f "$B" ]; then
  GOT=$(jq -r '.plugin_version' "$B")
  [ "$GOT" = "$REAL_VERSION" ] \
    && pass_check "a full envelope is stamped too, and the caller's claimed version is discarded" \
    || fail_check "full envelope kept \"$GOT\" — a caller must not be able to assert which build ran"
else
  fail_check "no audit written on the full-envelope path"
fi

# ------------------------------------------------------ unreadable resolves, not omits
#
# A script that cannot find its own plugin.json must say so in the record. Silence would
# let "which build" be answered by absence, which is the failure this stamp exists to end.

mkdir -p "$T/orphan" "$T/orphaned-task"
cp "$W" "$T/orphan/gate-audit-write.sh"
bash "$T/orphan/gate-audit-write.sh" "$T/orphaned-task" dev-guides-load '{"verdict":"pass"}' >/dev/null 2>&1 || true
C="$T/orphaned-task/_dev-guides-load.json"
if [ -f "$C" ]; then
  [ "$(jq -r '.plugin_version' "$C")" = "undetermined" ] \
    && pass_check "a writer that cannot read its plugin.json records \"undetermined\"" \
    || fail_check "expected \"undetermined\", got $(jq -r '.plugin_version' "$C")"
  jq -e '.plugin_version != null' "$C" >/dev/null 2>&1 \
    && pass_check "the unknown case is never null" \
    || fail_check "plugin_version came back null — unknown must be a value, not an absence"
else
  fail_check "an orphaned writer wrote nothing at all"
fi

# ---------------------------------------------------------------- the dependency check

R=$(bash "$D" code-quality-tools 0.0.1 2>/dev/null) || true
if printf '%s' "$R" | jq -e '.status == "ok"' >/dev/null 2>&1; then
  pass_check "an installed sibling plugin above the minimum resolves ok"
else
  pass_check "code-quality-tools not installed here; the ok path is exercised by the fixture below"
fi

# A minimum nothing can satisfy must fail, and must name what it found.
set +e
R=$(bash "$D" code-quality-tools 999.0.0 2>/dev/null); RC=$?
set -e
if printf '%s' "$R" | jq -e '.status == "too_old"' >/dev/null 2>&1; then
  pass_check "a version below the stated minimum is reported too_old"
  [ "$RC" = "3" ] && pass_check "too_old exits 3" || fail_check "too_old exited $RC, expected 3"
  printf '%s' "$R" | jq -e '.resolved_version != null' >/dev/null 2>&1 \
    && pass_check "too_old names the version it actually found" \
    || fail_check "too_old did not say what it found"
elif printf '%s' "$R" | jq -e '.status == "undetermined"' >/dev/null 2>&1; then
  pass_check "code-quality-tools not installed here; too_old exercised by the fixture below"
else
  fail_check "a 999.0.0 minimum produced neither too_old nor undetermined"
fi

# ------------------------------------- not-found is never reported as a negative result
#
# The cache is one install location, not the only one. Answering "not installed" from a
# single unreadable place is the same error as a gate that reports clean because it could
# not run.

set +e
R=$(bash "$D" definitely-not-a-real-plugin 1.0.0 2>/dev/null); RC=$?
set -e
printf '%s' "$R" | jq -e '.status == "undetermined"' >/dev/null 2>&1 \
  && pass_check "an unseen plugin is undetermined, never a claim that it is absent" \
  || fail_check "expected undetermined for an unseen plugin, got $(printf '%s' "$R" | jq -r '.status // "no status"')"
[ "$RC" = "4" ] && pass_check "undetermined exits 4" || fail_check "undetermined exited $RC, expected 4"
printf '%s' "$R" | jq -e '.status != "not_installed"' >/dev/null 2>&1 \
  && pass_check "the word not_installed is never used" \
  || fail_check "reported not_installed from a single unreadable location"

# ------------------------------------------------------------------ the lexical trap
#
# The live failure: `ls .../<plugin>/*/ | head -1` returned 3.9.6 with 3.9.8 installed.
# `| tail -1` has the mirror-image bug: it returns 3.9.8 when 3.10.0 is installed. Both
# orders are wrong because both are lexical.
#
# The fixture is chosen so that NEITHER lexical end is the right answer, which takes four
# entries rather than three. With {3.2.0, 3.9.8, 3.10.0} the lexically-first entry is
# 3.10.0 — which is also the correct answer, so a `head -1` implementation passes by
# coincidence and the test proves nothing. That is not hypothetical: this spec was written
# with exactly that three-entry fixture and a `head -1` mutation of the resolver did not
# fail a single assertion. Adding an older major separates them:
#
#   lexical order: 2.0.0, 3.10.0, 3.2.0, 3.9.8   → first 2.0.0, last 3.9.8
#   version order: 2.0.0, 3.2.0, 3.9.8, 3.10.0   → newest 3.10.0
#
# so 3.10.0 is reachable only by version-aware sorting, and both lexical shortcuts fail.

FAKE="$T/fakehome"
mkdir -p "$FAKE/.claude/plugins/cache/camoa-skills/widget/3.9.8" \
         "$FAKE/.claude/plugins/cache/camoa-skills/widget/3.10.0" \
         "$FAKE/.claude/plugins/cache/camoa-skills/widget/3.2.0" \
         "$FAKE/.claude/plugins/cache/camoa-skills/widget/2.0.0"
touch "$FAKE/.claude/plugins/cache/camoa-skills/widget/README"

R=$(HOME="$FAKE" bash "$D" widget 3.10.0 2>/dev/null) || true
[ "$(printf '%s' "$R" | jq -r '.resolved_version')" = "3.10.0" ] \
  && pass_check "3.10.0 beats 3.9.8 — resolution is by version order, not string order" \
  || fail_check "resolved $(printf '%s' "$R" | jq -r '.resolved_version'), expected 3.10.0"
printf '%s' "$R" | jq -e '.status == "ok"' >/dev/null 2>&1 \
  && pass_check "the newest install satisfies a minimum equal to itself" \
  || fail_check "equality with the minimum was not treated as satisfying it"
printf '%s' "$R" | jq -e '.installed_versions | index("README") == null' >/dev/null 2>&1 \
  && pass_check "a non-version entry in the cache is not mistaken for an install" \
  || fail_check "README was listed as an installed version"
printf '%s' "$R" | jq -e '.installed_versions | length == 4' >/dev/null 2>&1 \
  && pass_check "every version-shaped install is reported, not just the winner" \
  || fail_check "installed_versions did not list all four"
printf '%s' "$R" | jq -e '.installed_versions[0] == "2.0.0" and .installed_versions[-1] == "3.10.0"' >/dev/null 2>&1 \
  && pass_check "installed_versions is itself in version order, not string order" \
  || fail_check "installed_versions came back in string order"

set +e
R=$(HOME="$FAKE" bash "$D" widget 4.0.0 2>/dev/null); RC=$?
set -e
printf '%s' "$R" | jq -e '.status == "too_old"' >/dev/null 2>&1 \
  && pass_check "a fixture below its minimum is too_old" \
  || fail_check "3.10.0 against a 4.0.0 minimum was not too_old"
[ "$RC" = "3" ] && pass_check "the fixture too_old exits 3" || fail_check "fixture too_old exited $RC"

# An empty cache directory proves nothing about whether the plugin is installed.
mkdir -p "$FAKE/.claude/plugins/cache/camoa-skills/hollow"
set +e
R=$(HOME="$FAKE" bash "$D" hollow 1.0.0 2>/dev/null)
set -e
printf '%s' "$R" | jq -e '.status == "undetermined"' >/dev/null 2>&1 \
  && pass_check "a cache directory holding no version is undetermined, not ok" \
  || fail_check "an empty cache directory did not resolve undetermined"

# --------------------------------------------------- a zero-padded minimum is the same
#
# `sort -V` ties 3.00.0 with 3.0.0, and GNU sort is not stable, so it breaks the tie by byte
# comparison and puts 3.0.0 first. Asking which STRING won the sort therefore called an
# equal version too_old, and the documented posture on too_old is abort: a working setup
# blocked by a leading zero in the caller's minimum. Nothing in the repo passes a padded
# minimum today, which is why this was a concern and not a critical, and also why nothing
# would have noticed.

mkdir -p "$FAKE/.claude/plugins/cache/camoa-skills/padded/3.0.0"
set +e
R=$(HOME="$FAKE" bash "$D" padded 3.00.0 2>/dev/null); RC=$?
set -e
printf '%s' "$R" | jq -e '.status == "ok"' >/dev/null 2>&1 \
  && pass_check "3.0.0 satisfies a 3.00.0 minimum — they are the same version" \
  || fail_check "3.0.0 against a 3.00.0 minimum came back $(printf '%s' "$R" | jq -r '.status // "nothing"'), expected ok"
[ "$RC" = "0" ] \
  && pass_check "and it exits 0 rather than the abort-worthy 3" \
  || fail_check "a padded minimum on a satisfying install exited $RC, expected 0"
set +e
R=$(HOME="$FAKE" bash "$D" padded 03.1.0 2>/dev/null); RC=$?
set -e
printf '%s' "$R" | jq -e '.status == "too_old"' >/dev/null 2>&1 \
  && pass_check "normalising the padding does not stop a genuinely higher minimum failing" \
  || fail_check "3.0.0 against a 03.1.0 minimum came back $(printf '%s' "$R" | jq -r '.status // "nothing"'), expected too_old"

# ------------------------------------------------------- a symlinked install is an install
#
# `find -type d` does not match a symlink pointing at a directory, so symlinking a working
# copy into the cache — an ordinary developer setup — resolved undetermined with an empty
# installed_versions[]. Undetermined is the honest word for "I could not see it" and nothing
# breaks, but the plugin was right there.

mkdir -p "$FAKE/real-checkout" "$FAKE/.claude/plugins/cache/camoa-skills/linked"
ln -s "$FAKE/real-checkout" "$FAKE/.claude/plugins/cache/camoa-skills/linked/4.0.0"
R=$(HOME="$FAKE" bash "$D" linked 4.0.0 2>/dev/null) || true
[ "$(printf '%s' "$R" | jq -r '.resolved_version')" = "4.0.0" ] \
  && pass_check "a version directory that is a symlink is seen as an install" \
  || fail_check "a symlinked install resolved $(printf '%s' "$R" | jq -r '.resolved_version'), expected 4.0.0"
printf '%s' "$R" | jq -e '.status == "ok"' >/dev/null 2>&1 \
  && pass_check "and resolves ok rather than undetermined" \
  || fail_check "a symlinked install came back $(printf '%s' "$R" | jq -r '.status')"

# Widening the search must not widen it to things that are not directories at all.
printf 'x\n' > "$FAKE/real-file"
ln -s "$FAKE/real-file"    "$FAKE/.claude/plugins/cache/camoa-skills/linked/5.0.0"
ln -s "$FAKE/nowhere-here" "$FAKE/.claude/plugins/cache/camoa-skills/linked/6.0.0"
R=$(HOME="$FAKE" bash "$D" linked 4.0.0 2>/dev/null) || true
[ "$(printf '%s' "$R" | jq -r '.installed_versions | join(",")')" = "4.0.0" ] \
  && pass_check "a symlink to a file and a dangling symlink are still not installs" \
  || fail_check "installed_versions is [$(printf '%s' "$R" | jq -r '.installed_versions | join(",")')], expected only 4.0.0"

# ------------------------------------------ readable is not the same as enterable
#
# A directory needs the execute bit to be traversed. `-r` alone reported a chmod 444
# directory as ok, and the documented posture on ok is "use the returned path if you need to
# read anything out of that plugin" — which is exactly what nobody can do with it.

mkdir -p "$FAKE/.claude/plugins/cache/camoa-skills/noenter/1.0.0"
chmod 444 "$FAKE/.claude/plugins/cache/camoa-skills/noenter/1.0.0"
if [ -x "$FAKE/.claude/plugins/cache/camoa-skills/noenter/1.0.0" ]; then
  chmod 755 "$FAKE/.claude/plugins/cache/camoa-skills/noenter/1.0.0"
  skip_check "chmod 444 leaves the directory traversable here (running as root?), so an un-enterable install cannot be staged"
else
  set +e
  R=$(HOME="$FAKE" bash "$D" noenter 1.0.0 2>/dev/null); RC=$?
  set -e
  printf '%s' "$R" | jq -e '.status == "unreadable"' >/dev/null 2>&1 \
    && pass_check "a directory that cannot be entered is unreadable, not ok" \
    || fail_check "a chmod 444 install came back $(printf '%s' "$R" | jq -r '.status // "nothing"'), and ok invites the caller to read from it"
  [ "$RC" = "4" ] \
    && pass_check "and exits 4 rather than 0" \
    || fail_check "an un-enterable install exited $RC, expected 4"
  chmod 755 "$FAKE/.claude/plugins/cache/camoa-skills/noenter/1.0.0"
fi

# ------------------------------------------------------------------------ jq is required
#
# The single JSON object this script exists to print is rendered by jq. Without an up-front
# probe, `set -uo pipefail` with no `-e` turned a broken jq into a run that printed nothing
# and still exited 4 — a status the caller reads as "undetermined", which is a verdict the
# check never computed.

mkdir -p "$T/nojqbin"
printf '#!/bin/sh\nexit 127\n' > "$T/nojqbin/jq"
chmod +x "$T/nojqbin/jq"
set +e
OUTPUT=$(PATH="$T/nojqbin:$PATH" HOME="$FAKE" bash "$D" widget 3.10.0 2>/dev/null); RC=$?
ERRTEXT=$(PATH="$T/nojqbin:$PATH" HOME="$FAKE" bash "$D" widget 3.10.0 2>&1 >/dev/null)
set -e
[ "$RC" = "5" ] \
  && pass_check "an unrunnable jq is refused up front with its own exit code" \
  || fail_check "a broken jq exited $RC, which a caller cannot tell from a real verdict"
[ -z "$OUTPUT" ] && [ -n "$ERRTEXT" ] \
  && pass_check "and says so on stderr instead of printing an empty verdict" \
  || fail_check "a broken jq produced stdout [$OUTPUT] and no diagnostic"

# Bad arguments are rejected rather than guessed at.
set +e
bash "$D" >/dev/null 2>&1; RC=$?
set -e
[ "$RC" = "2" ] && pass_check "called with no arguments it exits 2" || fail_check "no-argument call exited $RC, expected 2"
set +e
bash "$D" widget "not-a-version" >/dev/null 2>&1; RC=$?
set -e
[ "$RC" = "2" ] && pass_check "a non-numeric minimum is rejected" || fail_check "a non-numeric minimum exited $RC, expected 2"

# --------------------------------------------- the wrappers actually call the new check

for c in validate-tdd validate-solid validate-dry validate-security; do
  F="${PLUGIN_ROOT}/commands/${c}.md"
  if grep -q 'plugin-dep-check.sh code-quality-tools 3.0.0' "$F"; then
    pass_check "/$c calls plugin-dep-check.sh with its stated minimum"
  else
    fail_check "/$c does not call plugin-dep-check.sh — its minimum is still unenforced"
  fi
  if grep -q 'returns a non-empty directory' "$F"; then
    fail_check "/$c still verifies its dependency by directory non-emptiness"
  else
    pass_check "/$c no longer treats a non-empty directory as a version check"
  fi
  if grep -q 'undetermined' "$F" && grep -q 'do NOT abort' "$F"; then
    pass_check "/$c is told not to abort on an unconfirmable version"
  else
    fail_check "/$c does not say what to do when the version cannot be confirmed"
  fi
done

# ------------------------------------------------------ the schema documents the field

S="${PLUGIN_ROOT}/references/gate-audit-schema.md"
grep -q '`plugin_version`' "$S" \
  && pass_check "the schema documents plugin_version" \
  || fail_check "plugin_version is written but undocumented"
grep -q 'Absence is itself provenance' "$S" \
  && pass_check "the schema says what a missing stamp means on an older record" \
  || fail_check "the schema does not explain records written before the stamp existed"

if [ "$FAIL" = "0" ]; then printf '\nbuild-provenance-spec: all checks passed\n'; else printf '\nbuild-provenance-spec: FAILURES\n' >&2; fi
exit "$FAIL"
