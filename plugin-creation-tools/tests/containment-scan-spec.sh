#!/usr/bin/env bash
# TDD spec for scripts/containment-scan.sh (P-series leak/containment gate).
#
# Fixtures that need to TRIGGER a finding are built from runtime concatenation
# so this spec file itself never contains a literal home path, secret, or email
# verbatim — otherwise the gate would (correctly) flag its own test source.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
ROOT="$(dirname "$HERE")"
SUT="$ROOT/scripts/containment-scan.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

krun() { OUT="$(bash "$SUT" "$@" 2>/dev/null)"; RC=$?; }
pass_check() { PASS=$((PASS+1)); }
fail_check() { FAIL=$((FAIL+1)); echo "FAIL $1: $2"; [ -n "${OUT:-}" ] && echo "  out: $OUT"; }

mkplugin() { local d="$TMP/$1"; mkdir -p "$d/.claude-plugin"; echo '{"name":"x","version":"1.0.0"}' > "$d/.claude-plugin/plugin.json"; echo "$d"; }

# Concatenated leak literals (kept out of this file as single tokens).
HOMEPATH="/home/""realdev/.claude/plugins/cache/x/1.0.0/scripts/foo.sh"
GHTOKEN="ghp_""$(printf 'a%.0s' {1..36})"
EMAIL="someone.real""@""gmail.com"

# ---------------------------------------------------------------------------
# T1: clean plugin → PASS, rc 0, zero findings
P="$(mkplugin clean)"
echo 'Use ${CLAUDE_PLUGIN_ROOT}/scripts/run.sh and ~/.claude for state.' > "$P/SKILL.md"
krun "$P"
if [ "$RC" -eq 0 ] && [ "$(jq -r '.result' <<<"$OUT")" = "PASS" ] && [ "$(jq -r '.errors' <<<"$OUT")" = "0" ]; then
  pass_check
else
  fail_check "T1 clean-plugin" "result=$(jq -r '.result' <<<"$OUT" 2>/dev/null) errors=$(jq -r '.errors' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T2: absolute home path → P01 error, FAIL, rc 1
P="$(mkplugin homepath)"
mkdir -p "$P/commands"
printf 'Run %s now.\n' "$HOMEPATH" > "$P/commands/run.md"
krun "$P"
if [ "$RC" -eq 1 ] && [ "$(jq -r '.result' <<<"$OUT")" = "FAIL" ] && [ "$(jq -r '[.findings[]|select(.rule=="P01")]|length' <<<"$OUT")" -ge 1 ]; then
  pass_check
else
  fail_check "T2 abs-home-path" "result=$(jq -r '.result' <<<"$OUT" 2>/dev/null) p01=$(jq -r '[.findings[]|select(.rule=="P01")]|length' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T3: placeholder username /home/user/ → NOT flagged
P="$(mkplugin placeholder)"
mkdir -p "$P/docs"
echo 'Example install path: /home/user/.config/app — replace with yours.' > "$P/docs/install.md"
krun "$P"
if [ "$RC" -eq 0 ] && [ "$(jq -r '[.findings[]|select(.rule=="P01")]|length' <<<"$OUT")" = "0" ]; then
  pass_check
else
  fail_check "T3 placeholder-user-exempt" "p01=$(jq -r '[.findings[]|select(.rule=="P01")]|length' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T4: secret token → P02 error, redacted (full token NOT echoed), FAIL
P="$(mkplugin secret)"
mkdir -p "$P/scripts"
printf 'TOKEN=%s\n' "$GHTOKEN" > "$P/scripts/deploy.sh"
krun "$P"
if [ "$RC" -eq 1 ] \
  && [ "$(jq -r '[.findings[]|select(.rule=="P02")]|length' <<<"$OUT")" -ge 1 ] \
  && ! grep -q "$GHTOKEN" <<<"$OUT"; then
  pass_check
else
  fail_check "T4 secret-redacted" "p02=$(jq -r '[.findings[]|select(.rule=="P02")]|length' <<<"$OUT" 2>/dev/null) leaked=$(grep -qc "$GHTOKEN" <<<"$OUT" 2>/dev/null; echo $?) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T5: personal email in a SKILL body → P03 warn; PASS without --strict, FAIL with
P="$(mkplugin email)"
printf 'Contact %s for help.\n' "$EMAIL" > "$P/SKILL.md"
krun "$P"
ok_warn=$([ "$(jq -r '[.findings[]|select(.rule=="P03")]|length' <<<"$OUT")" -ge 1 ] && echo 1 || echo 0)
ok_pass=$([ "$RC" -eq 0 ] && [ "$(jq -r '.result' <<<"$OUT")" = "PASS" ] && echo 1 || echo 0)
krun "$P" --strict
ok_strict=$([ "$RC" -eq 1 ] && [ "$(jq -r '.result' <<<"$OUT")" = "FAIL" ] && echo 1 || echo 0)
if [ "$ok_warn" = 1 ] && [ "$ok_pass" = 1 ] && [ "$ok_strict" = 1 ]; then
  pass_check
else
  fail_check "T5 email-warn-strict" "warn=$ok_warn pass=$ok_pass strict=$ok_strict"
fi

# ---------------------------------------------------------------------------
# T6: author email in plugin.json → NOT flagged (intentional manifest field)
P="$(mkplugin authoremail)"
jq -nc --arg e "$EMAIL" '{name:"x",version:"1.0.0",author:{name:"Dev",email:$e}}' > "$P/.claude-plugin/plugin.json"
krun "$P"
if [ "$RC" -eq 0 ] && [ "$(jq -r '[.findings[]|select(.rule=="P03")]|length' <<<"$OUT")" = "0" ]; then
  pass_check
else
  fail_check "T6 author-email-exempt" "p03=$(jq -r '[.findings[]|select(.rule=="P03")]|length' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T7: .containment-allow suppresses a hit
P="$(mkplugin allowlisted)"
mkdir -p "$P/docs"
printf 'See %s in the tutorial.\n' "$HOMEPATH" > "$P/docs/tut.md"
printf '%s\n' '/home/realdev/' > "$P/.containment-allow"
krun "$P"
if [ "$RC" -eq 0 ] && [ "$(jq -r '[.findings[]|select(.rule=="P01")]|length' <<<"$OUT")" = "0" ]; then
  pass_check
else
  fail_check "T7 allowlist-suppress" "p01=$(jq -r '[.findings[]|select(.rule=="P01")]|length' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T8: missing dir → result ERROR, rc 2
krun "$TMP/does-not-exist"
if [ "$RC" -eq 2 ] && [ "$(jq -r '.result' <<<"$OUT")" = "ERROR" ]; then
  pass_check
else
  fail_check "T8 missing-dir" "result=$(jq -r '.result' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T9: structural — JSON built with jq (no string-concatenated JSON)
if grep -q 'jq -nc' "$SUT" && ! grep -qE 'printf .*\{.*"rule"' "$SUT"; then
  pass_check
else
  fail_check "T9 jq-built-json" "expected jq -nc record construction"
fi

# ---------------------------------------------------------------------------
# T10: relative subpath containing "home/" (e.g. snapshots/home/x) → NOT flagged
P="$(mkplugin relpath)"
mkdir -p "$P/tests"
echo 'diff=$(mk_rename "stash/x.snap" "snapshots/home/dark/x.snap")' > "$P/tests/oracle-spec.sh"
krun "$P"
if [ "$RC" -eq 0 ] && [ "$(jq -r '[.findings[]|select(.rule=="P01")]|length' <<<"$OUT")" = "0" ]; then
  pass_check
else
  fail_check "T10 relative-subpath-not-leak" "p01=$(jq -r '[.findings[]|select(.rule=="P01")]|length' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
# T11: benign emails (.test TLD, company.com, git@ SSH user) → NOT flagged
P="$(mkplugin benignmail)"
mkdir -p "$P/docs"
{ echo 'Clone via git@git.example-host.org:foo/bar.git'
  echo 'Set author to team@company.com in the example.'
  echo 'Fixture uses t@t.test as a throwaway.'; } > "$P/docs/notes.md"
krun "$P"
if [ "$RC" -eq 0 ] && [ "$(jq -r '[.findings[]|select(.rule=="P03")]|length' <<<"$OUT")" = "0" ]; then
  pass_check
else
  fail_check "T11 benign-emails-exempt" "p03=$(jq -r '[.findings[]|select(.rule=="P03")]|length' <<<"$OUT" 2>/dev/null) rc=$RC"
fi

# ---------------------------------------------------------------------------
echo "----"
echo "containment-scan-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
