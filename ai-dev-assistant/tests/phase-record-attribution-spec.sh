#!/usr/bin/env bash
# Spec for the two records every phase contract attributes by phase, and for the
# type guard on recipe-load method_fit.
#
# Found by a live research run that reached its end-of-phase records check with three
# required records missing:
#
#   - _playbook-load.json was never written. playbook-load-deterministic.sh PRINTS the
#     gate_specific object (it takes a project folder and cannot know the active task),
#     while /research, /design and /implement all said it "writes _playbook-load.json
#     audit". Nothing told the caller to pass that stdout to gate-audit-write.sh, so the
#     payload went to the terminal and the record did not exist. /upgrade-project, the
#     retrofit path, had the wrapping right all along.
#   - _dev-guides-load.json was written without `phase` and read as unattributed. The
#     schema documents phase as the first gate_specific field and the record contract
#     attributes by it, but the writer did not demand it — so the failure surfaced at the
#     end of the phase instead of at the write.
#   - The recipe-load method_fit check crashed with a jq internal error ("Cannot index
#     string with string") when method_fit arrived as a bare string instead of the
#     {verdict, reason} object, and reported that raw message to a person.
#
# Exit: 0 = all checks pass.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"
W="$ROOT/scripts/gate-audit-write.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '  %s\n' "$2" >&2; }

run() { # $1=dir $2=gate $3=payload  → sets OUT
  mkdir -p "$TMP/$1"
  OUT="$(bash "$W" "$TMP/$1" "$2" "$3" 2>&1)" || true
}

# --- phase is demanded at write time for the two attributed records ---
run d1 dev-guides-load '{"methodology_floor":["plugin:solid"],"guides_actually_loaded":["plugin:solid"]}'
if printf '%s' "$OUT" | grep -q 'missing documented key(s).*phase'; then
  ok "dev-guides-load without phase is named at the write, not at the records check"
else
  bad "dev-guides-load without phase is named at the write, not at the records check" "$OUT"
fi

run d2 dev-guides-load '{"phase":"research","methodology_floor":["plugin:solid"],"guides_actually_loaded":["plugin:solid"]}'
if ! printf '%s' "$OUT" | grep -q 'missing documented key'; then
  ok "dev-guides-load with phase writes without a missing-key warning"
else
  bad "dev-guides-load with phase writes without a missing-key warning" "$OUT"
fi

run p1 playbook-load '{"playbook_sets_loaded":[],"playbook_sets_source":"default"}'
if printf '%s' "$OUT" | grep -q 'missing documented key(s).*phase'; then
  ok "playbook-load without phase is named at the write"
else
  bad "playbook-load without phase is named at the write" "$OUT"
fi

run p2 playbook-load '{"phase":"research","playbook_sets_loaded":[],"playbook_sets_source":"default"}'
if ! printf '%s' "$OUT" | grep -q 'missing documented key'; then
  ok "playbook-load with phase writes without a missing-key warning"
else
  bad "playbook-load with phase writes without a missing-key warning" "$OUT"
fi

# --- method_fit type guard: a wrong type is named, never a jq internal error ---
run m1 recipe-load '{"phase":"research","resolved_count":1,"frameworks":[{"framework":"drupal","available":true,"method_fit":"partial"}]}'
if printf '%s' "$OUT" | grep -q 'method_fit is a string, not the {verdict, reason} object' \
   && ! printf '%s' "$OUT" | grep -qi 'Cannot index\|jq: error'; then
  ok "a string method_fit is named plainly, with no jq internals shown to a person"
else
  bad "a string method_fit is named plainly, with no jq internals shown to a person" "$OUT"
fi

run m2 recipe-load '{"phase":"research","resolved_count":1,"frameworks":[{"framework":"drupal","available":true,"method_fit":{"verdict":"partial","reason":"covers three of four aspects"}}]}'
if ! printf '%s' "$OUT" | grep -q 'method_fit'; then
  ok "a well-formed method_fit object raises nothing"
else
  bad "a well-formed method_fit object raises nothing" "$OUT"
fi

# --- the commands wire the loader's stdout to the writer ---
for f in research design implement; do
  C="$ROOT/commands/$f.md"
  if grep -q 'does not write the audit' "$C" && grep -q 'gate-audit-write.sh .*playbook-load' "$C"; then
    ok "/$f says the loader prints and wires its output to the writer"
  else
    bad "/$f says the loader prints and wires its output to the writer"
  fi
done

if grep -q 'It does NOT write _playbook-load.json' "$ROOT/scripts/playbook-load-deterministic.sh"; then
  ok "the loader's own header says it prints rather than writes"
else
  bad "the loader's own header says it prints rather than writes"
fi

echo "----"
echo "phase-record-attribution-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
