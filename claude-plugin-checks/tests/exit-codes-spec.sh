#!/usr/bin/env bash
# The exit contract, end to end. The unit tests under tests/*.py cover what each
# rule decides; this covers what a caller reading only an exit code is told.
#
# Zero has to mean "everything looked and everything was clean". The defect this
# spec exists for: the old runner exited 0 when five of its six checks could not
# look, because one passing check satisfied its "did anything run" test.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
ROOT="$(dirname "$HERE")"
CHECK="$ROOT/scripts/check.py"
RUNNER="$ROOT/scripts/run-checks.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1: $2"; }

mkfx() { # name, manifest json  -> path
  local d="$TMP/$1"; mkdir -p "$d/.claude-plugin"
  printf '%s' "$2" > "$d/.claude-plugin/plugin.json"
  echo "$d"
}
run()  { OUT="$(python3 "$CHECK" "$@" 2>/dev/null)"; RC=$?; }
field() { python3 -c "import json,sys; print(json.load(sys.stdin).get('$1'))" <<<"$OUT" 2>/dev/null; }

# --- a clean plugin exits 0 --------------------------------------------------
P="$(mkfx clean '{"name":"clean","version":"1.0.0"}')"
mkdir -p "$P/skills/s"; printf -- '---\nname: s\ndescription: x\n---\nbody\n' > "$P/skills/s/SKILL.md"
run "$P"
[ "$RC" -eq 0 ] && [ "$(field result)" = "PASS" ] && ok || bad clean "rc=$RC result=$(field result)"

# --- a finding exits 1 -------------------------------------------------------
P="$(mkfx finding '{"name":"f","version":"1.0.0","outputStyles":"/etc/passwd"}')"
mkdir -p "$P/skills/s"; printf -- '---\nname: s\ndescription: x\n---\nbody\n' > "$P/skills/s/SKILL.md"
run "$P"
[ "$RC" -eq 1 ] && [ "$(field result)" = "FAIL" ] && ok || bad finding "rc=$RC result=$(field result)"

# --- a missing directory exits 2, distinct from could-not-look ---------------
run "$TMP/does-not-exist"
[ "$RC" -eq 2 ] && ok || bad missing-dir "rc=$RC"

# --- nothing to examine exits 3, never 0 -------------------------------------
D="$TMP/empty"; mkdir -p "$D"
run "$D"
[ "$RC" -eq 3 ] && [ "$(field result)" = "UNCHECKED" ] && ok || bad empty "rc=$RC result=$(field result)"

# --- a warning alone passes, and fails under --strict ------------------------
P="$(mkfx warnonly '{"name":"w","version":"1.0.0","experimental":{"monitors":"./m.json"}}')"
echo '[]' > "$P/m.json"
mkdir -p "$P/skills/s"; printf -- '---\nname: s\ndescription: x\n---\nbody\n' > "$P/skills/s/SKILL.md"
run "$P"
[ "$RC" -eq 0 ] && [ "$(field warnings)" = "1" ] && ok || bad warn-passes "rc=$RC warnings=$(field warnings)"
run "$P" --strict
[ "$RC" -eq 1 ] && ok || bad warn-strict-fails "rc=$RC"

# --- --only runs a subset, and an unknown selector is a usage error ----------
P="$(mkfx subset '{"name":"s","version":"1.0.0","outputStyles":"/etc/passwd"}')"
mkdir -p "$P/skills/s"; printf -- '---\nname: s\ndescription: x\n---\nbody\n' > "$P/skills/s/SKILL.md"
run "$P" --only S
[ "$RC" -eq 0 ] && ok || bad only-skips-others "rc=$RC"
run "$P" --only E01
[ "$RC" -eq 1 ] && ok || bad only-selects-by-id "rc=$RC"
run "$P" --only Z9
[ "$RC" -eq 2 ] && ok || bad only-unknown "rc=$RC"

# --- an excerpt cannot carry a terminal escape into the readable summary -----
# The summary is printed to a terminal and an excerpt quotes a file this tool
# did not write. The JSON half of this used to be the assertion, and it could not
# fail: json.dumps escapes control characters on its own.
P="$(mkfx control '{"name":"c","version":"1.0.0"}')"
mkdir -p "$P/skills/s"; printf -- '---\nname: s\ndescription: x\n---\nbody\n' > "$P/skills/s/SKILL.md"
# Assembled at run time so this spec does not itself carry a leak-shaped literal
# that the containment rule would (correctly) report when run over its own plugin.
LEAK="/home/""realuser/x"
printf 'leak %s with a \a bell and a \t tab\n' "$LEAK" > "$P/skills/s/notes.md"
printf 'hostile \033[2K\033[1;31mALL CHECKS PASSED\007 %s\n' "$LEAK" >> "$P/skills/s/notes.md"
SUMMARY="$(python3 "$CHECK" "$P" 2>&1 >/dev/null)"; RC=$?
# Tab is kept on purpose, so it is excluded from the class rather than the check
# being loosened to whatever happens to pass.
if printf '%s' "$SUMMARY" | LC_ALL=C grep -q '[^[:print:][:space:]]'; then
  bad terminal-escape "a control character reached the readable summary"
else ok; fi
run "$P"
if python3 -c "import json,sys; json.load(sys.stdin)" <<<"$OUT" 2>/dev/null; then ok
else bad json-parsable "output was not valid JSON"; fi

# --- the runner tells a caller the same three things -------------------------
# Only the exit code is asserted here; what each foreign tool says is its own
# business and this plugin does not grade it.
P="$(mkfx runner '{"name":"r","version":"1.0.0"}')"
mkdir -p "$P/skills/s"; printf -- '---\nname: s\ndescription: x\n---\nbody\n' > "$P/skills/s/SKILL.md"
bash "$RUNNER" "$P" >/dev/null 2>&1; RRC=$?
[ "$RRC" -eq 0 ] || [ "$RRC" -eq 3 ] && ok || bad runner-clean "rc=$RRC"

bash "$RUNNER" "$TMP/does-not-exist" >/dev/null 2>&1; RRC=$?
[ "$RRC" -eq 2 ] && ok || bad runner-missing-dir "rc=$RRC"

# A run where our own check cannot look must not come back zero, however many
# other checks passed.
P="$(mkfx runnerblind '{"name":"rb","version":"1.0.0"}')"
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
for t in bash find sort ls dirname readlink cat mktemp rm mkdir head tail printf sed grep; do
  src="$(command -v $t 2>/dev/null)"; [ -n "$src" ] && ln -sf "$src" "$FAKEBIN/$t"
done
PATH="$FAKEBIN" bash "$RUNNER" "$P" >/dev/null 2>&1; RRC=$?
[ "$RRC" -eq 3 ] && ok || bad runner-all-blind "expected 3, got $RRC"

echo "----"
echo "exit-codes-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
