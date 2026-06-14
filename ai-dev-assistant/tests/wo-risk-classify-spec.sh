#!/usr/bin/env bash
# TDD spec for scripts/wo-risk-classify.sh (C4) — architecture/kernels.md (AR-C corrected).
# Pure-function kernel; no live agents/git. Run: bash tests/wo-risk-classify-spec.sh
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
ROOT="$(dirname "$HERE")"                 # ai-dev-assistant SOURCE dir
export CLAUDE_PLUGIN_ROOT="$ROOT"          # honor the directive: test against SOURCE, never cache
KERNEL="$ROOT/scripts/wo-risk-classify.sh"
BASE="tdd,solid,dry,security,guides"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

assert() { # $1 label  $2 want_tier  $3 want_trigger_prefix  $4.. kernel args
  local label="$1" etier="$2" etrig="$3"; shift 3
  local out tier trig
  out="$(bash "$KERNEL" "$@")"
  tier="$(printf '%s' "$out" | jq -r '.risk_tier')"
  trig="$(printf '%s' "$out" | jq -r '.trigger')"
  if [ "$tier" = "$etier" ] && [[ "$trig" == "$etrig"* ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL $label: got tier=$tier trigger=$trig (want $etier / $etrig*)"; echo "     $out"
  fi
}
f() { printf '%s\n' "$@" > "$TMP/$1.txt"; echo "$TMP/$1.txt"; }  # not used; explicit per-case below

# T1 — realized-diff security glob (routing.yml) on a base floor, verified => HIGH/security_glob
printf 'web/modules/my/my.routing.yml\n' > "$TMP/t1.txt"
assert "T1 security-glob"        high security_glob     --files-from "$TMP/t1.txt" --gate-floor "$BASE" --verified true
# T1b — gate_floor ⊋ base (recipe added e2e), plain code, verified => HIGH/recipe_added_gate
printf 'src/Calculator.php\n' > "$TMP/t1b.txt"
assert "T1b recipe_added_gate"   high recipe_added_gate --files-from "$TMP/t1b.txt" --gate-floor "$BASE,e2e" --verified true
# T2 — base floor CONTAINS security, docs-only, verified => LOW (proves security∈floor is NOT a trigger)
printf 'README.md\n' > "$TMP/t2.txt"
assert "T2 security∈floor!=trigger" low none           --files-from "$TMP/t2.txt" --gate-floor "$BASE" --verified true
# T3 — verified:false is NO LONGER a trigger (F1 2026-06-12): a docs-only unverified WO is LOW.
# The coverage_override + flagged PR + human-merge is the control for unverified grounding, not the tier.
printf 'README.md\n' > "$TMP/t3.txt"
assert "T3 verified:false not a trigger" low none      --files-from "$TMP/t3.txt" --gate-floor "$BASE" --verified false
# T4 — collapsed_scc:true => HIGH/collapsed_scc
printf 'README.md\n' > "$TMP/t4.txt"
assert "T4 collapsed_scc"         high collapsed_scc    --files-from "$TMP/t4.txt" --gate-floor "$BASE" --verified true --collapsed-scc true
# T5 — empty diff (present, empty) => HIGH/unresolved
: > "$TMP/t5.txt"
assert "T5 empty diff"            high unresolved       --files-from "$TMP/t5.txt" --gate-floor "$BASE" --verified true
# T7 — one plain executable file => MEDIUM/executable_change
printf 'src/Calculator.php\n' > "$TMP/t7.txt"
assert "T7 executable"            medium executable_change --files-from "$TMP/t7.txt" --gate-floor "$BASE" --verified true
# T8 — docs only => LOW
printf 'a.md\nb.md\nc.md\n' > "$TMP/t8.txt"
assert "T8 docs only"             low none              --files-from "$TMP/t8.txt" --gate-floor "$BASE" --verified true
# T9 — docs + a shell script => MEDIUM/executable_change
printf 'README.md\nscripts/deploy.sh\n' > "$TMP/t9.txt"
assert "T9 docs+sh"               medium executable_change --files-from "$TMP/t9.txt" --gate-floor "$BASE" --verified true
# T10 — verified, no collapse, docs, base => LOW (autonomy_safe is structurally not a param/trigger)
printf 'docs/guide.md\n' > "$TMP/t10.txt"
assert "T10 autonomy_safe!=trigger" low none            --files-from "$TMP/t10.txt" --gate-floor "$BASE" --verified true
# T11 — missing files-from path => fail-closed HIGH/unresolved
assert "T11 files missing"        high unresolved       --files-from "$TMP/nope.txt" --gate-floor "$BASE" --verified true
# Tx — plain non-security non-executable yml => LOW
printf 'config/foo.yml\n' > "$TMP/tx.txt"
assert "Tx plain yml"             low none              --files-from "$TMP/tx.txt" --gate-floor "$BASE" --verified true
# Tg — missing gate-floor => fail-closed HIGH/unresolved
printf 'README.md\n' > "$TMP/tg.txt"
assert "Tg gate_floor missing"    high unresolved       --files-from "$TMP/tg.txt" --verified true
# Tsec — an access-control php (security glob *Access*.php) => HIGH/security_glob
printf 'src/Access/NodeAccessControlHandler.php\n' > "$TMP/tsec.txt"
assert "Tsec access php"          high security_glob    --files-from "$TMP/tsec.txt" --gate-floor "$BASE" --verified true
# MED-10 — permission-granting config + lowercase access/auth must reach HIGH (rules-data coverage)
printf 'config/install/user.role.administrator.yml\n' > "$TMP/m10.txt"
assert "M10 role config"          high security_glob    --files-from "$TMP/m10.txt" --gate-floor "$BASE" --verified true
printf 'web/modules/my/src/access_check.php\n' > "$TMP/m10b.txt"
assert "M10b lowercase access"    high security_glob    --files-from "$TMP/m10b.txt" --gate-floor "$BASE" --verified true
printf 'src/SessionManager.php\n' > "$TMP/m10c.txt"
assert "M10c session"             high security_glob    --files-from "$TMP/m10c.txt" --gate-floor "$BASE" --verified true
# H1 — read verified/gate_floor/collapsed_scc from the WO FILE via the safe parser (NOT flags).
# collapsed_scc:true (read from the file) drives HIGH; verified:false is ALSO in the file but is NO LONGER
# a trigger (F1) — so the trigger being `collapsed_scc` (not `verified_false`) proves both: file-reading
# works AND verified:false no longer escalates.
printf -- '---\nid: local:t#wo-09\ngate_floor: [tdd, solid, dry, security, guides]\nverified: false\ncollapsed_scc: true\n---\n# wo\n' > "$TMP/wo-hi.md"
printf 'README.md\n' > "$TMP/h1.txt"
assert "H1 file collapsed_scc:true (verified:false not trigger)" high collapsed_scc --files-from "$TMP/h1.txt" "$TMP/wo-hi.md"
printf -- '---\nid: local:t#wo-10\ngate_floor: [tdd, solid, dry, security, guides]\nverified: true\ncollapsed_scc: false\n---\n# wo\n' > "$TMP/wo-lo.md"
printf 'docs/x.md\n' > "$TMP/h1b.txt"
assert "H1 file verified:true low" low none             --files-from "$TMP/h1b.txt" "$TMP/wo-lo.md"

echo "----"
echo "wo-risk-classify-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
