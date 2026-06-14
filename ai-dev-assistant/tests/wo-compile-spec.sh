#!/usr/bin/env bash
# wo-compile-spec.sh — unit spec for scripts/wo-compile.sh (the C2 safety kernel).
#
# The kernel is parser-grade determinism where a divergent re-implementation is a
# SAFETY bug, so every branch is exercised here. Covers all 7 sub-commands:
#   coverage-slice  — empty-slice⇒false (the C1 fail-open guard), poison⇒false
#                     (C-1), AND semantics, poisoned>uncovered>covered precedence
#   build-graph     — 2-cycle collapse, clean-DAG no-collapse + NO topo order,
#                     over-bound / cross-AC / self-dependency HALT (non-zero)
#   drift-guard     — missing path⇒false, absent codePath⇒"skipped", acceptance
#   lockfile-sha    — body-sha from cache, excerpt_sha, compiled_from SHAs
#   assert-dispatchable — the full fail-closed dispatch matrix + override
#   collect-handle  — checkpoint_after==null ⟺ produced_changes==false; the
#                     handle has no verdict/next/status; built with zero transcript
#   emit-frontmatter — round-trips as valid YAML (key order preserved)
# Plus an RCE/no-eval security smoke (the kernel parses untrusted WO files).
#
# Run pre-PR: bash tests/wo-compile-spec.sh

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUT="${PLUGIN_ROOT}/scripts/wo-compile.sh"

if [ ! -f "$SUT" ]; then
  printf 'FAIL: %s not found\n' "$SUT" >&2
  exit 1
fi

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# krun <stdin-string> <subcmd> [args...]  → sets OUT (stdout) and RC (exit code).
# `|| RC=$?` keeps `set -e` from aborting on the kernel's intentional non-zero
# halts (build-graph / assert-dispatchable).
krun() {
  local input="$1"; shift
  RC=0
  OUT=$(printf '%s' "$input" | bash "$SUT" "$@" 2>/dev/null) || RC=$?
}

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then pass_check "$1"; else fail_check "$1 — expected [$2] got [$3]"; fi
}
# assert_jq <label> <jq-filter> <expected> <json>
assert_jq() {
  local got; got=$(printf '%s' "$4" | jq -r "$2" 2>/dev/null || true)
  assert_eq "$1" "$3" "$got"
}

# ═══════════════════════════════════════════════════════════════════════════
# (b) coverage-slice
# ═══════════════════════════════════════════════════════════════════════════

# === Test 1: EMPTY covered slice ⇒ verified:false (THE C1 fail-open guard) ===
# WO owns aspect "z"; the map has an entry for "a" only (verified:true) and lists
# "z" as uncovered. The slice is empty ⇒ MUST be verified:false, NOT AND([])==true.
EMPTY_MAP='{"coverage_map":{"schema_version":"1.0","task_aspects":["a","z"],
  "entries":[{"aspect":"a","kind":"guide","ref":"g","relevance":"high","via":"residual-guide-search","provenance":"upstream","verified":true}],
  "uncovered_aspects":["z"],"warnings":[]},"aspects":["z"]}'
krun "$EMPTY_MAP" coverage-slice
assert_jq "empty covered slice ⇒ verified:false (C1)"        '.verified'        'false' "$OUT"
assert_jq "empty covered slice ⇒ coverage_status uncovered"  '.coverage_status' 'uncovered' "$OUT"
assert_jq "empty covered slice ⇒ covered_count 0"            '.covered_count'   '0' "$OUT"

# === Test 2: a poison warning ⇒ verified:false (C-1, global poison) ===
# A clean verified:true covered entry, but a slug_not_in_catalog warning exists
# (no aspect key ⇒ GLOBAL poison ⇒ every WO false).
POISON_SLUG='{"coverage_map":{"schema_version":"1.0","task_aspects":["a"],
  "entries":[{"aspect":"a","kind":"recipe","ref":"cap","relevance":"high","via":"recipe:cap","provenance":"upstream","verified":true}],
  "uncovered_aspects":[],"warnings":["slug_not_in_catalog:ghost_recipe"]},"aspects":["a"]}'
krun "$POISON_SLUG" coverage-slice
assert_jq "slug_not_in_catalog poison ⇒ verified:false"        '.verified'        'false'    "$OUT"
assert_jq "slug_not_in_catalog poison ⇒ status poisoned"       '.coverage_status' 'poisoned' "$OUT"
assert_jq "slug_not_in_catalog poison ⇒ poison_warnings len 1" '.poison_warnings | length' '1' "$OUT"

POISON_BODY='{"coverage_map":{"schema_version":"1.0","task_aspects":["a"],
  "entries":[{"aspect":"a","kind":"recipe","ref":"cap","relevance":"high","via":"recipe:cap","provenance":"upstream","verified":true}],
  "uncovered_aspects":[],"warnings":["recipe_body_unverified:some_recipe"]},"aspects":["a"]}'
krun "$POISON_BODY" coverage-slice
assert_jq "recipe_body_unverified poison ⇒ verified:false"  '.verified'        'false'    "$OUT"
assert_jq "recipe_body_unverified poison ⇒ status poisoned" '.coverage_status' 'poisoned' "$OUT"

# === Test 3: all covered verified:true, no poison ⇒ verified:true ===
ALL_OK='{"coverage_map":{"schema_version":"1.0","task_aspects":["a","b"],
  "entries":[{"aspect":"a","kind":"guide","ref":"g1","relevance":"high","via":"residual-guide-search","provenance":"upstream","verified":true},
             {"aspect":"b","kind":"recipe","ref":"cap","relevance":"high","via":"recipe:cap","provenance":"upstream","verified":true}],
  "uncovered_aspects":[],"warnings":["navigator_unavailable"]},"aspects":["a","b"]}'
krun "$ALL_OK" coverage-slice
assert_jq "all covered verified:true + non-poison warning ⇒ verified:true" '.verified'        'true'    "$OUT"
assert_jq "all covered ⇒ status covered"                                   '.coverage_status' 'covered' "$OUT"
assert_jq "non-poison warning (navigator_unavailable) is NOT poison"       '.poison_warnings | length' '0' "$OUT"
assert_jq "all covered ⇒ covered_count 2 (both aspects sliced in)"         '.covered_count'   '2' "$OUT"
assert_jq "all covered ⇒ covered_entries carry both refs"                  '[.covered_entries[].ref] | sort | join(",")' 'cap,g1' "$OUT"
assert_jq "all covered ⇒ slice excludes nothing extraneous"               '.covered_entries | length' '2' "$OUT"

# === Test 4: one covered entry verified:false ⇒ AND ⇒ verified:false ===
ONE_FALSE='{"coverage_map":{"schema_version":"1.0","task_aspects":["a","b"],
  "entries":[{"aspect":"a","kind":"guide","ref":"g1","relevance":"high","via":"x","provenance":"upstream","verified":true},
             {"aspect":"b","kind":"guide","ref":"g2","relevance":"low","via":"x","provenance":"local","verified":false}],
  "uncovered_aspects":[],"warnings":[]},"aspects":["a","b"]}'
krun "$ONE_FALSE" coverage-slice
assert_jq "covered set with one verified:false ⇒ verified:false (AND)" '.verified'        'false'   "$OUT"
assert_jq "covered set with one verified:false ⇒ status covered"      '.coverage_status' 'covered' "$OUT"

# === Test 5: precedence poisoned > uncovered > covered ===
# (a) poisoned beats covered: covered entries present + poison ⇒ poisoned.
PREC_PC='{"coverage_map":{"schema_version":"1.0","task_aspects":["a"],
  "entries":[{"aspect":"a","kind":"guide","ref":"g","relevance":"high","via":"x","provenance":"upstream","verified":true}],
  "uncovered_aspects":[],"warnings":["slug_not_in_catalog:x"]},"aspects":["a"]}'
krun "$PREC_PC" coverage-slice
assert_jq "precedence: poison beats covered ⇒ poisoned" '.coverage_status' 'poisoned' "$OUT"
# (b) poisoned beats uncovered: empty covered + poison ⇒ poisoned (not uncovered).
PREC_PU='{"coverage_map":{"schema_version":"1.0","task_aspects":["a","z"],
  "entries":[{"aspect":"a","kind":"guide","ref":"g","relevance":"high","via":"x","provenance":"upstream","verified":true}],
  "uncovered_aspects":["z"],"warnings":["recipe_body_unverified:x"]},"aspects":["z"]}'
krun "$PREC_PU" coverage-slice
assert_jq "precedence: poison beats uncovered ⇒ poisoned" '.coverage_status' 'poisoned' "$OUT"
# (c) uncovered beats covered when slice empty + no poison (already Test 1) — re-confirm label.
krun "$EMPTY_MAP" coverage-slice
assert_jq "precedence: empty + no poison ⇒ uncovered" '.coverage_status' 'uncovered' "$OUT"

# === Test 6: missing coverage_map ⇒ fail-closed (verified:false) ===
krun '{"aspects":["a"]}' coverage-slice
assert_jq "missing coverage_map ⇒ verified:false"             '.verified'        'false'     "$OUT"
assert_jq "missing coverage_map ⇒ coverage_map_missing warn"  '.warnings | index("coverage_map_missing") != null' 'true' "$OUT"
assert_eq "coverage-slice always exits 0 (total)" "0" "$RC"

# === CRITICAL-1 regression: a non-array `aspects` must FAIL-CLOSED ===
# The repro: a STRING aspects made jq `index` do a SUBSTRING match → fail-OPEN
# (a "auth" entry matched the string "auth_login"). Must be verified:false.
CRIT='{"coverage_map":{"entries":[{"aspect":"auth","verified":true}],"warnings":[]},"aspects":"auth_login"}'
krun "$CRIT" coverage-slice
assert_jq "CRITICAL-1: aspects as STRING ⇒ verified:false (no substring fail-open)" '.verified' 'false' "$OUT"
assert_jq "CRITICAL-1: aspects as STRING ⇒ coverage_status uncovered" '.coverage_status' 'uncovered' "$OUT"
assert_jq "CRITICAL-1: aspects as STRING ⇒ aspects_not_array warning"  '.warnings | index("aspects_not_array") != null' 'true' "$OUT"
assert_eq "CRITICAL-1: aspects as STRING ⇒ still exits 0 (total)" "0" "$RC"
# aspects as number → fail-closed
krun '{"coverage_map":{"entries":[{"aspect":"auth","verified":true}],"warnings":[]},"aspects":7}' coverage-slice
assert_jq "CRITICAL-1: aspects as NUMBER ⇒ verified:false" '.verified' 'false' "$OUT"
assert_jq "CRITICAL-1: aspects as NUMBER ⇒ aspects_not_array" '.warnings | index("aspects_not_array") != null' 'true' "$OUT"
# aspects as object → fail-closed
krun '{"coverage_map":{"entries":[{"aspect":"auth","verified":true}],"warnings":[]},"aspects":{"a":1}}' coverage-slice
assert_jq "CRITICAL-1: aspects as OBJECT ⇒ verified:false" '.verified' 'false' "$OUT"
# a 1-element array ["auth_login"] with only an "auth" entry ⇒ correctly uncovered
krun '{"coverage_map":{"entries":[{"aspect":"auth","verified":true}],"warnings":[]},"aspects":["auth_login"]}' coverage-slice
assert_jq "CRITICAL-1: array [auth_login] vs entry auth ⇒ uncovered (membership, not substring)" '.coverage_status' 'uncovered' "$OUT"
assert_jq "CRITICAL-1: array [auth_login] ⇒ verified:false" '.verified' 'false' "$OUT"
# a non-string array element is filtered, doesn't match
krun '{"coverage_map":{"entries":[{"aspect":"auth","verified":true}],"warnings":[]},"aspects":["auth",123]}' coverage-slice
assert_jq "CRITICAL-1: array [auth,123] ⇒ covered (string aspect matches, 123 ignored)" '.coverage_status' 'covered' "$OUT"

# === L-1 regression: poison detection is case-insensitive + non-string-tolerant ===
L1MIX='{"coverage_map":{"entries":[{"aspect":"a","verified":true}],"warnings":["Slug_Not_In_Catalog:x", 42]},"aspects":["a"]}'
krun "$L1MIX" coverage-slice
assert_jq "L-1: mixed-case poison code ⇒ detected ⇒ verified:false" '.verified' 'false' "$OUT"
assert_jq "L-1: mixed-case poison code ⇒ status poisoned"          '.coverage_status' 'poisoned' "$OUT"
assert_jq "L-1: a non-string warning is tolerated (skipped safely)" '.poison_warnings | length' '1' "$OUT"

# === R2-CRITICAL regression: the ENTRY-side aspect type (subsequence bypass) ===
# jq `index` with an ARRAY arg does SUBSEQUENCE matching: an entry aspect:["x"]
# vs aspects:["x"] previously matched → fail-OPEN verified:true. The entry aspect
# must be a STRING to be sliced in.
R2C='{"coverage_map":{"entries":[{"aspect":["x"],"verified":true}],"warnings":[]},"aspects":["x"]}'
krun "$R2C" coverage-slice
assert_jq "R2-CRIT: entry aspect as ARRAY ⇒ excluded ⇒ verified:false" '.verified' 'false' "$OUT"
assert_jq "R2-CRIT: entry aspect as ARRAY ⇒ uncovered (covered_count 0)" '.coverage_status' 'uncovered' "$OUT"
assert_jq "R2-CRIT: entry aspect as ARRAY ⇒ covered_count 0" '.covered_count' '0' "$OUT"
# entry aspect as object / number / null ⇒ excluded
krun '{"coverage_map":{"entries":[{"aspect":{},"verified":true}],"warnings":[]},"aspects":["x"]}' coverage-slice
assert_jq "R2-CRIT: entry aspect as OBJECT ⇒ verified:false" '.verified' 'false' "$OUT"
krun '{"coverage_map":{"entries":[{"aspect":5,"verified":true}],"warnings":[]},"aspects":[5]}' coverage-slice
assert_jq "R2-CRIT: entry aspect as NUMBER (vs aspects [5]) ⇒ verified:false" '.verified' 'false' "$OUT"
krun '{"coverage_map":{"entries":[{"aspect":null,"verified":true}],"warnings":[]},"aspects":["x"]}' coverage-slice
assert_jq "R2-CRIT: entry aspect as NULL ⇒ verified:false" '.verified' 'false' "$OUT"
# a STRING entry aspect still matches normally (no regression)
krun '{"coverage_map":{"entries":[{"aspect":"x","verified":true}],"warnings":[]},"aspects":["x"]}' coverage-slice
assert_jq "R2-CRIT: a STRING entry aspect still matches (no regression)" '.verified' 'true' "$OUT"

# === R2-HIGH regression: poison guard catches whitespace / object-wrapped / case ===
# whitespace-prefixed
krun '{"coverage_map":{"entries":[{"aspect":"a","verified":true}],"warnings":["   slug_not_in_catalog:x"]},"aspects":["a"]}' coverage-slice
assert_jq "R2-HIGH: whitespace-prefixed poison ⇒ verified:false" '.verified' 'false' "$OUT"
assert_jq "R2-HIGH: whitespace-prefixed poison ⇒ poisoned"       '.coverage_status' 'poisoned' "$OUT"
# object-wrapped
krun '{"coverage_map":{"entries":[{"aspect":"a","verified":true}],"warnings":[{"x":"slug_not_in_catalog:y"}]},"aspects":["a"]}' coverage-slice
assert_jq "R2-HIGH: object-wrapped poison ⇒ verified:false" '.verified' 'false' "$OUT"
assert_jq "R2-HIGH: object-wrapped poison ⇒ poisoned"       '.coverage_status' 'poisoned' "$OUT"
# recipe_body_unverified object-wrapped too
krun '{"coverage_map":{"entries":[{"aspect":"a","verified":true}],"warnings":[{"k":"RECIPE_BODY_UNVERIFIED:z"}]},"aspects":["a"]}' coverage-slice
assert_jq "R2-HIGH: object-wrapped UPPERCASE recipe_body_unverified ⇒ poisoned" '.coverage_status' 'poisoned' "$OUT"
# a CLEAN map is NOT over-poisoned (the fail-closed bias does not false-positive)
krun '{"coverage_map":{"entries":[{"aspect":"a","verified":true}],"warnings":["navigator_unavailable","recipe_cache_missing"]},"aspects":["a"]}' coverage-slice
assert_jq "R2-HIGH: a clean map (non-poison warnings) still verified:true" '.verified' 'true' "$OUT"

# ═══════════════════════════════════════════════════════════════════════════
# (a) build-graph
# ═══════════════════════════════════════════════════════════════════════════

# === Test 7: a 2-cycle (mutual blocked_by, same AC) ⇒ collapse + acyclic ===
TWO_CYCLE='{"units":[
  {"id":"wo-01","ac":"AUTH-01","blocked_by":["wo-02"]},
  {"id":"wo-02","ac":"AUTH-01","blocked_by":["wo-01"]}]}'
krun "$TWO_CYCLE" build-graph
assert_eq "2-cycle build-graph exits 0"                 "0"    "$RC"
assert_jq "2-cycle ⇒ ok:true"                            '.ok'                       'true' "$OUT"
assert_jq "2-cycle ⇒ acyclic:true after collapse"        '.acyclic'                  'true' "$OUT"
assert_jq "2-cycle ⇒ exactly one unit"                   '.units | length'           '1'    "$OUT"
assert_jq "2-cycle ⇒ collapsed_scc:true"                 '.units[0].collapsed_scc'   'true' "$OUT"
assert_jq "2-cycle ⇒ both members merged"                '.units[0].members | join(",")' 'wo-01,wo-02' "$OUT"
assert_jq "2-cycle ⇒ collapsed count 1"                  '.collapsed'                '1'    "$OUT"
assert_jq "2-cycle ⇒ no self-blocked_by on the merged unit" '.units[0].blocked_by | length' '0' "$OUT"

# === Test 8: a clean DAG ⇒ passes, no collapse, NO topo order emitted ===
# Input order is wo-02 then wo-01 (wo-02 blocked_by wo-01) — reverse-topo. The
# output MUST preserve INPUT order (no topo sort) and carry no order/sequence key.
CLEAN_DAG='{"units":[
  {"id":"wo-02","ac":"A","blocked_by":["wo-01"]},
  {"id":"wo-01","ac":"A","blocked_by":[]}]}'
krun "$CLEAN_DAG" build-graph
assert_eq "clean DAG exits 0"                         "0"    "$RC"
assert_jq "clean DAG ⇒ two units"                      '.units | length'           '2'      "$OUT"
assert_jq "clean DAG ⇒ no collapse"                    '.collapsed'                '0'      "$OUT"
assert_jq "clean DAG ⇒ no unit collapsed_scc"          '[.units[].collapsed_scc] | any' 'false' "$OUT"
assert_jq "clean DAG ⇒ INPUT order preserved (units[0]=wo-02, not topo)" '.units[0].id' 'wo-02' "$OUT"
assert_jq "clean DAG ⇒ wo-02 blocked_by [wo-01] (edge set, not order)"   '.units[0].blocked_by | join(",")' 'wo-01' "$OUT"
assert_jq "clean DAG ⇒ NO topo/order/sequence key emitted" 'has("order") or has("topo_order") or has("sequence")' 'false' "$OUT"

# === Test 9: an SCC of >2 units ⇒ HALT non-zero (no mega-WO) ===
THREE_CYCLE='{"units":[
  {"id":"wo-01","ac":"A","blocked_by":["wo-03"]},
  {"id":"wo-02","ac":"A","blocked_by":["wo-01"]},
  {"id":"wo-03","ac":"A","blocked_by":["wo-02"]}]}'
krun "$THREE_CYCLE" build-graph
assert_eq "3-cycle ⇒ exits non-zero (HALT)" "1" "$RC"
assert_jq "3-cycle ⇒ ok:false"               '.ok'          'false' "$OUT"
assert_jq "3-cycle ⇒ halt_reason cites the over-bound cycle" '.halt_reason | startswith("uncollapsible_cycle:size_3")' 'true' "$OUT"
assert_jq "3-cycle ⇒ emits no units (no mega-WO)" '.units | length' '0' "$OUT"

# === Test 10: a 2-cycle spanning >1 AC ⇒ HALT non-zero ===
CROSS_AC='{"units":[
  {"id":"wo-01","ac":"AUTH-01","blocked_by":["wo-02"]},
  {"id":"wo-02","ac":"DATA-09","blocked_by":["wo-01"]}]}'
krun "$CROSS_AC" build-graph
assert_eq "cross-AC 2-cycle ⇒ exits non-zero (HALT)" "1" "$RC"
assert_jq "cross-AC 2-cycle ⇒ halt_reason cites spanning ACs" '.halt_reason | startswith("uncollapsible_cycle:spans_2_acs")' 'true' "$OUT"

# === Test 11: a self-dependency ⇒ HALT non-zero ===
SELF_DEP='{"units":[{"id":"wo-01","ac":"A","blocked_by":["wo-01"]}]}'
krun "$SELF_DEP" build-graph
assert_eq "self-dependency ⇒ exits non-zero (HALT)" "1" "$RC"
assert_jq "self-dependency ⇒ halt_reason self_dependency" '.halt_reason | startswith("self_dependency")' 'true' "$OUT"

# === Test 12: empty graph ⇒ total (ok:true, zero units) ===
krun '{"units":[]}' build-graph
assert_eq "empty graph exits 0"          "0"    "$RC"
assert_jq "empty graph ⇒ ok:true"         '.ok'             'true' "$OUT"
assert_jq "empty graph ⇒ zero units"      '.units | length' '0'    "$OUT"

# === Test 13: a dangling blocked_by edge is dropped + warned (cannot hide a cycle) ===
DANGLING='{"units":[{"id":"wo-01","ac":"A","blocked_by":["ghost"]}]}'
krun "$DANGLING" build-graph
assert_eq "dangling edge ⇒ exits 0"       "0"    "$RC"
assert_jq "dangling edge ⇒ ok:true"        '.ok'  'true' "$OUT"
assert_jq "dangling edge ⇒ warned"         '[.warnings[] | select(startswith("dangling_edge"))] | length >= 1' 'true' "$OUT"

# === HIGH-1 regression: a non-list edge field must HALT (cycle-hiding repro) ===
# blocked_by as STRING — the repro: Python char-iterated "wo-bb" → dropped the
# real edge, returning ok:true,acyclic:true (HIDING a genuine 2-cycle).
H1_STR='{"units":[{"id":"wo-aa","ac":"A","blocked_by":"wo-bb"},{"id":"wo-bb","ac":"A","blocked_by":["wo-aa"]}]}'
krun "$H1_STR" build-graph
assert_eq "HIGH-1: blocked_by as STRING ⇒ exits non-zero (HALT, not acyclic:true)" "1" "$RC"
assert_jq "HIGH-1: blocked_by as STRING ⇒ ok:false" '.ok' 'false' "$OUT"
assert_jq "HIGH-1: blocked_by as STRING ⇒ malformed_edge_field reason" '.halt_reason | startswith("malformed_edge_field:wo-aa:blocked_by")' 'true' "$OUT"
assert_jq "HIGH-1: blocked_by as STRING ⇒ NOT acyclic:true" '.acyclic' 'false' "$OUT"
# blocks as STRING ⇒ HALT
krun '{"units":[{"id":"wo-aa","ac":"A","blocks":"wo-bb"}]}' build-graph
assert_eq "HIGH-1: blocks as STRING ⇒ HALT" "1" "$RC"
assert_jq "HIGH-1: blocks as STRING ⇒ malformed_edge_field:wo-aa:blocks" '.halt_reason' 'malformed_edge_field:wo-aa:blocks' "$OUT"
# blocked_by as NUMBER ⇒ HALT with a clean reason (NOT a Python traceback)
krun '{"units":[{"id":"wo-aa","ac":"A","blocked_by":5}]}' build-graph
assert_eq "HIGH-1: blocked_by as NUMBER ⇒ HALT" "1" "$RC"
assert_jq "HIGH-1: blocked_by as NUMBER ⇒ clean malformed_edge_field reason" '.halt_reason' 'malformed_edge_field:wo-aa:blocked_by' "$OUT"
# blocked_by:null is a legitimate "no edges" sentinel ⇒ NOT a halt
krun '{"units":[{"id":"wo-aa","ac":"A","blocked_by":null}]}' build-graph
assert_jq "HIGH-1: blocked_by:null ⇒ ok:true (null is a legit no-edges sentinel)" '.ok' 'true' "$OUT"

# === MEDIUM-C regression: a duplicate unit id HALTs (no silent edge absorption) ===
krun '{"units":[{"id":"wo-01","ac":"A"},{"id":"wo-01","ac":"A","blocked_by":["wo-02"]}]}' build-graph
assert_eq "MEDIUM-C: duplicate unit id ⇒ exits non-zero (HALT)" "1" "$RC"
assert_jq "MEDIUM-C: duplicate unit id ⇒ ok:false" '.ok' 'false' "$OUT"
assert_jq "MEDIUM-C: duplicate unit id ⇒ halt_reason duplicate_unit_id:wo-01" '.halt_reason' 'duplicate_unit_id:wo-01' "$OUT"

# === LOW-F regression: `units` non-list ⇒ clean fail-closed halt (no leak) ===
krun '{"units":"abc"}' build-graph
assert_eq "LOW-F: units as STRING ⇒ HALT" "1" "$RC"
assert_jq "LOW-F: units as STRING ⇒ malformed_units_field (NOT vacuous ok:true)" '.halt_reason' 'malformed_units_field:not_a_list' "$OUT"
krun '{"units":5}' build-graph
assert_eq "LOW-F: units as NUMBER ⇒ HALT" "1" "$RC"
assert_jq "LOW-F: units as NUMBER ⇒ clean malformed_units_field (NOT leaked internal_error)" '.halt_reason' 'malformed_units_field:not_a_list' "$OUT"

# === LOW-E regression: a structured `ac` inside an SCC ⇒ clean (no TypeError) ===
krun '{"units":[{"id":"wo-01","ac":{},"blocked_by":["wo-02"]},{"id":"wo-02","ac":{},"blocked_by":["wo-01"]}]}' build-graph
assert_eq "LOW-E: 2-cycle with object ac ⇒ exits 0 (no unhashable TypeError)" "0" "$RC"
assert_jq "LOW-E: 2-cycle with object ac ⇒ collapses cleanly" '.collapsed' '1' "$OUT"
assert_jq "LOW-E: 2-cycle with object ac ⇒ ac preserved as the original value" '.units[0].ac' '{}' "$OUT"
# two DIFFERENT structured ac values in a cycle ⇒ spans>1 AC ⇒ HALT (not TypeError)
krun '{"units":[{"id":"wo-01","ac":{"x":1},"blocked_by":["wo-02"]},{"id":"wo-02","ac":{"x":2},"blocked_by":["wo-01"]}]}' build-graph
assert_eq "LOW-E: cycle with two distinct object acs ⇒ HALT (spans ACs)" "1" "$RC"
assert_jq "LOW-E: distinct object acs ⇒ clean spans_2_acs reason" '.halt_reason | startswith("uncollapsible_cycle:spans_2_acs")' 'true' "$OUT"

# === HIGH-B regression: a >128 KB build-graph input ⇒ legal JSON, never empty ===
BIG_GRAPH=$(python3 -c 'import json; print(json.dumps({"units":[{"id":"wo-%05d"%i,"ac":"A"} for i in range(4000)]}))')
krun "$BIG_GRAPH" build-graph
assert_jq "HIGH-B: 200KB build-graph input ⇒ ok:true (temp-file, not E2BIG empty)" '.ok' 'true' "$OUT"
assert_jq "HIGH-B: 200KB build-graph input ⇒ all 4000 units returned" '.units | length' '4000' "$OUT"
# output is never empty (a legal object even on the fallback path)
assert_eq "HIGH-B: build-graph large input ⇒ non-empty stdout" "ok" "$([ -n "$OUT" ] && echo ok || echo EMPTY)"

# ═══════════════════════════════════════════════════════════════════════════
# (c) drift-guard
# ═══════════════════════════════════════════════════════════════════════════
CODE="$TMPDIR/code"
mkdir -p "$CODE/src"
printf 'class Foo { function bar() {} }\n' > "$CODE/src/Foo.php"

# === Test 14: a MISSING cited path ⇒ symbols_resolved:false ===
DG_MISS=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:["src/Foo.php","src/Gone.php"],
  requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_MISS" drift-guard
assert_jq "missing cited path ⇒ symbols_resolved:false" '.drift_guard.symbols_resolved' 'false' "$OUT"
assert_jq "missing cited path is listed"                '.missing_paths | index("src/Gone.php") != null' 'true' "$OUT"

# === Test 15: all cited paths present ⇒ symbols_resolved:true ===
DG_OK=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:["src/Foo.php"],
  requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_OK" drift-guard
assert_jq "all cited paths present ⇒ symbols_resolved:true" '.drift_guard.symbols_resolved' 'true' "$OUT"

# === Test 16: absent codePath ⇒ symbols_resolved:"skipped" (soft-halt) ===
krun '{"cited_paths":["src/Foo.php"],"requirements":[{"id":"R-1","runnable":true}]}' drift-guard
assert_jq "absent codePath ⇒ symbols_resolved:skipped"  '.drift_guard.symbols_resolved' 'skipped' "$OUT"
DG_NULL='{"code_path":null,"cited_paths":["x"],"requirements":[{"id":"R-1","runnable":true}]}'
krun "$DG_NULL" drift-guard
assert_jq "null codePath ⇒ symbols_resolved:skipped"    '.drift_guard.symbols_resolved' 'skipped' "$OUT"

# === Test 17: acceptance_runnable — all true / one false / empty(false) ===
krun "$DG_OK" drift-guard
assert_jq "acceptance_runnable: all runnable ⇒ true" '.drift_guard.acceptance_runnable' 'true' "$OUT"
DG_AR_FALSE=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:["src/Foo.php"],
  requirements:[{"id":"R-1","runnable":true},{"id":"R-2","runnable":false}]}')
krun "$DG_AR_FALSE" drift-guard
assert_jq "acceptance_runnable: one not-runnable ⇒ false" '.drift_guard.acceptance_runnable' 'false' "$OUT"
DG_AR_EMPTY=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:["src/Foo.php"], requirements:[]}')
krun "$DG_AR_EMPTY" drift-guard
assert_jq "acceptance_runnable: empty requirements ⇒ false (fail-closed)" '.drift_guard.acceptance_runnable' 'false' "$OUT"

# === Test 18: a cited symbol resolves / does not resolve ===
DG_SYM_OK=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:[],
  cited_symbols:[{"path":"src/Foo.php","pattern":"function bar"}], requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_SYM_OK" drift-guard
assert_jq "present cited symbol ⇒ symbols_resolved:true" '.drift_guard.symbols_resolved' 'true' "$OUT"
DG_SYM_NO=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:[],
  cited_symbols:[{"path":"src/Foo.php","pattern":"function nonexistent"}], requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_SYM_NO" drift-guard
assert_jq "absent cited symbol ⇒ symbols_resolved:false" '.drift_guard.symbols_resolved' 'false' "$OUT"

# === L-3 regression: a path-traversal cited path is treated as MISSING ===
# ../../etc/passwd escapes code_path → must NOT resolve true.
DG_TRAV=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:["../../../../etc/passwd"],
  requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_TRAV" drift-guard
assert_jq "L-3: traversal path ⇒ symbols_resolved:false" '.drift_guard.symbols_resolved' 'false' "$OUT"
assert_jq "L-3: traversal path ⇒ listed as missing"      '.missing_paths | index("../../../../etc/passwd") != null' 'true' "$OUT"
# an absolute cited path also escapes ⇒ missing
DG_ABS=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:["/etc/passwd"],
  requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_ABS" drift-guard
assert_jq "L-3: absolute path ⇒ symbols_resolved:false" '.drift_guard.symbols_resolved' 'false' "$OUT"
# a legitimate in-tree path with a harmless .. that stays under code_path still resolves
mkdir -p "$CODE/src/sub"
printf 'x\n' > "$CODE/src/keep.txt"
DG_INTREE=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:["src/sub/../keep.txt"],
  requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_INTREE" drift-guard
assert_jq "L-3: in-tree path with a contained .. still resolves ⇒ symbols_resolved:true" '.drift_guard.symbols_resolved' 'true' "$OUT"

# === L-2 regression: a WO citing NOTHING surfaces a no_citations warning ===
DG_NOCITE=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:[], cited_symbols:[],
  requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_NOCITE" drift-guard
assert_jq "L-2: empty citations ⇒ no_citations warning present" '.warnings | index("no_citations") != null' 'true' "$OUT"
assert_jq "L-2: empty citations ⇒ symbols_resolved still true (vacuously)" '.drift_guard.symbols_resolved' 'true' "$OUT"

# === HIGH-A regression: a non-array citation field ⇒ fail-closed (no vacuous pass) ===
# cited_paths as a STRING — the repro: `[]?` swallowed the iterate-error ⇒ 0
# iterations ⇒ vacuous symbols_resolved:true. Must be false + a warning.
DG_PSTR=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:"src/Gone.php",
  requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_PSTR" drift-guard
assert_jq "HIGH-A: cited_paths as STRING ⇒ symbols_resolved:false (no vacuous pass)" '.drift_guard.symbols_resolved' 'false' "$OUT"
assert_jq "HIGH-A: cited_paths as STRING ⇒ cited_paths_not_array warning" '.warnings | index("cited_paths_not_array") != null' 'true' "$OUT"
# cited_paths as a NUMBER ⇒ fail-closed
DG_PNUM=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:5,
  requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_PNUM" drift-guard
assert_jq "HIGH-A: cited_paths as NUMBER ⇒ symbols_resolved:false" '.drift_guard.symbols_resolved' 'false' "$OUT"
# cited_symbols as a STRING ⇒ fail-closed + its own warning
DG_SSTR=$(jq -nc --arg cp "$CODE" '{code_path:$cp, cited_paths:["src/Foo.php"], cited_symbols:"bar",
  requirements:[{"id":"R-1","runnable":true}]}')
krun "$DG_SSTR" drift-guard
assert_jq "HIGH-A: cited_symbols as STRING ⇒ symbols_resolved:false" '.drift_guard.symbols_resolved' 'false' "$OUT"
assert_jq "HIGH-A: cited_symbols as STRING ⇒ cited_symbols_not_array warning" '.warnings | index("cited_symbols_not_array") != null' 'true' "$OUT"
# a valid array still works (no regression)
krun "$DG_OK" drift-guard
assert_jq "HIGH-A: valid array cited_paths still resolves true (no regression)" '.drift_guard.symbols_resolved' 'true' "$OUT"

# ═══════════════════════════════════════════════════════════════════════════
# (d) lockfile-sha
# ═══════════════════════════════════════════════════════════════════════════
CACHE="$TMPDIR/recipes-cache.json"
cat > "$CACHE" <<'EOF'
{
  "recipes": { "my_recipe": { "sha": "deadbeefsha", "content": "body" } },
  "index": { "content": "## Domain\n- my_recipe [my-cap] (sha:deadbeefsha): when-to-use — http://x\n- idx_only [c2] (sha:cafe1234idx): w — http://y\n" }
}
EOF
printf 'architecture body\n' > "$TMPDIR/architecture.md"
printf 'alignment body\n'    > "$TMPDIR/alignment.md"
printf 'research body\n'     > "$TMPDIR/research.md"
EXCERPT_A="the inlined excerpt for recipe A"
EXPECT_EXC_SHA=$(printf '%s' "$EXCERPT_A" | python3 -c 'import sys,hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')

LOCK_IN=$(jq -nc --arg cf "$CACHE" --arg arch "$TMPDIR/architecture.md" \
  --arg align "$TMPDIR/alignment.md" --arg res "$TMPDIR/research.md" --arg exc "$EXCERPT_A" '{
  cache_file: $cf,
  refs: [ {ref:"my_recipe@1.0", name:"my_recipe", kind:"recipe", excerpt:$exc},
          {ref:"idx_only",       kind:"guide",  excerpt:"e2"},
          {ref:"absent_one",     kind:"play",   excerpt:"e3"} ],
  compiled_from: { architecture:$arch, alignment:$align, research:$res } }')
krun "$LOCK_IN" lockfile-sha
assert_eq "lockfile-sha exits 0 (total)" "0" "$RC"
assert_jq "body-sha read from .recipes[name].sha"            '.lockfile[0].sha'         'deadbeefsha' "$OUT"
assert_jq "excerpt_sha = sha256 of the inlined excerpt"      '.lockfile[0].excerpt_sha' "$EXPECT_EXC_SHA" "$OUT"
assert_jq "body-sha fallback to the index (sha:…) per-line"  '.lockfile[1].sha'         'cafe1234idx' "$OUT"
assert_jq "absent ref ⇒ sha null"                            '.lockfile[2].sha'         'null' "$OUT"
assert_jq "absent ref ⇒ sha_not_in_cache warning"            '[.warnings[] | select(startswith("sha_not_in_cache"))] | length >= 1' 'true' "$OUT"
assert_jq "compiled_from architecture file basename"         '.compiled_from.architecture.file' 'architecture.md' "$OUT"
assert_jq "compiled_from architecture sha is 64-hex"         '.compiled_from.architecture.sha | test("^[0-9a-f]{64}$")' 'true' "$OUT"
assert_jq "compiled_from research sha present"               '.compiled_from.research.sha != null' 'true' "$OUT"

# === missing compiled_from file ⇒ sha null + warning ===
LOCK_MISS=$(jq -nc '{cache_file:null, refs:[], compiled_from:{architecture:"/nope/architecture.md"}}')
krun "$LOCK_MISS" lockfile-sha
assert_jq "missing compiled_from file ⇒ sha null" '.compiled_from.architecture.sha' 'null' "$OUT"
assert_jq "missing alignment key ⇒ compiled_from_missing warning" '[.warnings[] | select(startswith("compiled_from_missing"))] | length >= 1' 'true' "$OUT"

# === HIGH-B regression: a >128 KB lockfile-sha input ⇒ legal JSON, NEVER empty ===
# A ~210 KB inlined excerpt would exceed MAX_ARG_STRLEN via the old env-var path
# ⇒ E2BIG ⇒ empty-stdout-at-0. The temp-file path + rc-check guarantee an object.
# Build the payload in PYTHON (not `jq --arg` — that puts 210 KB on jq's own argv
# ⇒ the same E2BIG, in the test harness). krun pipes it via stdin (no ARG_MAX).
EXP_BIG_SHA=$(python3 -c 'import hashlib; print(hashlib.sha256(("x"*210000).encode("utf-8")).hexdigest())')
BIG_LOCK=$(python3 -c 'import json; print(json.dumps({"cache_file":None,"refs":[{"ref":"r@1","excerpt":"x"*210000}],"compiled_from":{}}))')
krun "$BIG_LOCK" lockfile-sha
assert_eq "HIGH-B: 210KB lockfile-sha input ⇒ non-empty stdout" "ok" "$([ -n "$OUT" ] && echo ok || echo EMPTY)"
assert_jq "HIGH-B: 210KB lockfile-sha input ⇒ ok:true (legal object)" '.ok' 'true' "$OUT"
assert_jq "HIGH-B: 210KB excerpt_sha computed correctly over the full payload" '.lockfile[0].excerpt_sha' "$EXP_BIG_SHA" "$OUT"
assert_eq "HIGH-B: lockfile-sha always exits 0 (total)" "0" "$RC"

# === LOW-F regression: lockfile-sha `refs` non-list ⇒ fail-closed ===
krun '{"refs":5}' lockfile-sha
assert_jq "LOW-F: refs as NUMBER ⇒ ok:false (clean, not leaked internal_error)" '.ok' 'false' "$OUT"
assert_jq "LOW-F: refs as NUMBER ⇒ refs_not_array warning" '.warnings | index("refs_not_array") != null' 'true' "$OUT"
krun '{"refs":"abc"}' lockfile-sha
assert_jq "LOW-F: refs as STRING ⇒ refs_not_array" '.warnings | index("refs_not_array") != null' 'true' "$OUT"

# ═══════════════════════════════════════════════════════════════════════════
# (e) emit-frontmatter
# ═══════════════════════════════════════════════════════════════════════════
# === Test: a full WO field object round-trips as valid YAML, key order kept ===
FM_IN='{"id":"local:t#wo-01","kind":"work-order","schema_version":"1.0","status":"ready",
  "verified":false,"coverage_status":"uncovered","blocked_by":["local:t#wo-00"],
  "lockfile":[{"ref":"r@1","sha":"abc","excerpt_sha":"def","kind":"recipe"}],
  "drift_guard":{"symbols_resolved":true,"acceptance_runnable":false},
  "coverage_override":null,"autonomy_safe":false}'
RC=0
OUT=$(printf '%s' "$FM_IN" | bash "$SUT" emit-frontmatter 2>/dev/null) || RC=$?
assert_eq "emit-frontmatter exits 0 on a valid object" "0" "$RC"
RT=$(printf '%s' "$OUT" | FM_EXPECT="$FM_IN" python3 -c '
import sys, os, json, yaml
lines = sys.stdin.read().splitlines()
if not lines or lines[0].strip() != "---":
    print("NO_LEADING"); sys.exit(0)
end = None
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        end = i; break
if end is None:
    print("NO_CLOSING"); sys.exit(0)
body = "\n".join(lines[1:end])
data = yaml.safe_load(body)
expected = json.loads(os.environ["FM_EXPECT"])
first_key = (list(data.keys())[0] if isinstance(data, dict) and data else None)
print(("MATCH" if data == expected else "DIFF") + "|" + str(first_key))')
assert_eq "emit-frontmatter round-trips as valid YAML (deep-equal)" "MATCH" "${RT%%|*}"
assert_eq "emit-frontmatter preserves key order (sort_keys=False)"  "id"    "${RT##*|}"

# === emit-frontmatter rejects non-object stdin (exit 2) ===
RC=0; OUT=$(printf '%s' '["not","an","object"]' | bash "$SUT" emit-frontmatter 2>/dev/null) || RC=$?
assert_eq "emit-frontmatter rejects a non-object (exit 2)" "2" "$RC"

# === MEDIUM-D regression: empty / whitespace-only stdin ⇒ exit 2, no traceback ===
RC=0; ERR=$(printf '' | bash "$SUT" emit-frontmatter 2>&1 >/dev/null) || RC=$?
assert_eq "MEDIUM-D: empty stdin ⇒ exit 2 (not a json.load traceback rc=1)" "2" "$RC"
assert_eq "MEDIUM-D: empty stdin ⇒ documented message, no Traceback" "ok" "$(printf '%s' "$ERR" | grep -q 'Traceback' && echo TRACEBACK || echo ok)"
RC=0; OUT2=$(printf '   \n\t  \n' | bash "$SUT" emit-frontmatter 2>/dev/null) || RC=$?
assert_eq "MEDIUM-D: whitespace-only stdin ⇒ exit 2" "2" "$RC"
assert_eq "MEDIUM-D: whitespace-only stdin ⇒ no stdout emitted" "" "$OUT2"

# ═══════════════════════════════════════════════════════════════════════════
# (f) assert-dispatchable — the fail-closed dispatch matrix
# ═══════════════════════════════════════════════════════════════════════════
# write_wo <path> <frontmatter-body-without-delimiters>
write_wo() { local p="$1"; shift; { printf -- '---\n'; printf '%s\n' "$1"; printf -- '---\n\n# Work Order\n'; } > "$p"; }

# all-green ⇒ dispatch (now must carry clean lockfile + drift receipt too)
WO_GREEN="$TMPDIR/wo-green.md"
write_wo "$WO_GREEN" 'id: local:t#wo-01
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
lockfile:
  - {ref: r@1, sha: abc123, excerpt_sha: def456, kind: recipe}
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
coverage_override: null'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_GREEN" 2>/dev/null) || RC=$?
assert_eq "all-green WO ⇒ exit 0 (dispatch)"            "0"    "$RC"
assert_jq "all-green WO ⇒ dispatchable:true"            '.dispatchable' 'true'  "$OUT"
assert_jq "all-green WO ⇒ override_used:false"          '.override_used' 'false' "$OUT"
assert_jq "all-green WO ⇒ reason dispatchable"          '.reason' 'dispatchable' "$OUT"

# verified:false ⇒ halt
WO_VF="$TMPDIR/wo-vf.md"
write_wo "$WO_VF" 'id: local:t#wo-02
status: ready
verified: false
autonomy_safe: true
coverage_status: uncovered
coverage_override: null'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_VF" 2>/dev/null) || RC=$?
assert_eq "verified:false WO ⇒ exit non-zero (halt)"   "1"    "$RC"
assert_jq "verified:false WO ⇒ dispatchable:false"     '.dispatchable' 'false' "$OUT"
assert_jq "verified:false WO ⇒ reason from coverage_status (uncovered)" '.reason' 'uncovered' "$OUT"

# status != ready ⇒ halt (verified:true + covered so status is the ONLY failure)
WO_ST="$TMPDIR/wo-st.md"
write_wo "$WO_ST" 'id: local:t#wo-03
status: blocked
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
coverage_override: null'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_ST" 2>/dev/null) || RC=$?
assert_eq "status!=ready WO ⇒ exit non-zero (halt)"    "1"    "$RC"
assert_jq "status!=ready WO ⇒ reason status_not_ready" '.reason | startswith("status_not_ready")' 'true' "$OUT"

# 2026-06-11: autonomy_safe is NO LONGER a dispatch gate. A grounded WO with
# autonomy_safe:false still dispatches (autonomy is mode-keyed recipe behavior, not a flag).
WO_AS="$TMPDIR/wo-as.md"
write_wo "$WO_AS" 'id: local:t#wo-04
status: ready
verified: true
autonomy_safe: false
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
coverage_override: null'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_AS" 2>/dev/null) || RC=$?
assert_eq "2026-06-11: autonomy_safe:false but grounded ⇒ exit 0 (dispatch)" "0" "$RC"
assert_jq "2026-06-11: autonomy_safe:false but grounded ⇒ dispatchable:true" '.dispatchable' 'true' "$OUT"
assert_jq "2026-06-11: autonomy_safe:false but grounded ⇒ reason dispatchable" '.reason' 'dispatchable' "$OUT"

# 2026-06-11: autonomy_safe ABSENT (the no-recipe / guides-only case) ⇒ still dispatches when grounded.
WO_NOAS="$TMPDIR/wo-noas.md"
write_wo "$WO_NOAS" 'id: local:t#wo-05
status: ready
verified: true
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
coverage_override: null'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_NOAS" 2>/dev/null) || RC=$?
assert_eq "2026-06-11: absent autonomy_safe (guides-only) but grounded ⇒ exit 0 (dispatch)" "0" "$RC"
assert_jq "2026-06-11: absent autonomy_safe but grounded ⇒ dispatchable:true" '.dispatchable' 'true' "$OUT"

# valid coverage_override on a verified:false WO ⇒ dispatch + override_used:true
WO_OV="$TMPDIR/wo-ov.md"
write_wo "$WO_OV" 'id: local:t#wo-06
status: ready
verified: false
autonomy_safe: true
coverage_status: uncovered
coverage_override:
  reason: human approved the uncovered slice
  by: carlos
  at: 2026-06-08T00:00:00Z'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_OV" 2>/dev/null) || RC=$?
assert_eq "valid override on verified:false ⇒ exit 0 (dispatch)" "0" "$RC"
assert_jq "valid override ⇒ dispatchable:true"  '.dispatchable'  'true' "$OUT"
assert_jq "valid override ⇒ override_used:true" '.override_used' 'true' "$OUT"

# an empty {} override does NOT bypass (no .reason) ⇒ still halt
WO_OVEMPTY="$TMPDIR/wo-ovempty.md"
write_wo "$WO_OVEMPTY" 'id: local:t#wo-07
status: ready
verified: false
autonomy_safe: true
coverage_status: uncovered
coverage_override: {}'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_OVEMPTY" 2>/dev/null) || RC=$?
assert_eq "empty {} override (no reason) ⇒ still halts" "1" "$RC"
assert_jq "empty {} override ⇒ override_used:false"     '.override_used' 'false' "$OUT"

# === MEDIUM-1 regression: a PARTIAL override (missing by / at) does NOT bypass ===
# reason-only (no by, no at)
WO_OVR="$TMPDIR/wo-ovr.md"
write_wo "$WO_OVR" 'id: local:t#wo-08a
status: ready
verified: false
autonomy_safe: true
coverage_status: uncovered
coverage_override:
  reason: only a reason, no by/at'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_OVR" 2>/dev/null) || RC=$?
assert_eq "MEDIUM-1: override {reason} only ⇒ NOT dispatchable" "1" "$RC"
assert_jq "MEDIUM-1: override {reason} only ⇒ override_used:false" '.override_used' 'false' "$OUT"
# missing by
WO_OVNB="$TMPDIR/wo-ovnb.md"
write_wo "$WO_OVNB" 'id: local:t#wo-08b
status: ready
verified: false
autonomy_safe: true
coverage_status: uncovered
coverage_override:
  reason: approved
  at: 2026-06-08T00:00:00Z'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_OVNB" 2>/dev/null) || RC=$?
assert_eq "MEDIUM-1: override missing .by ⇒ NOT dispatchable" "1" "$RC"
# missing at
WO_OVNA="$TMPDIR/wo-ovna.md"
write_wo "$WO_OVNA" 'id: local:t#wo-08c
status: ready
verified: false
autonomy_safe: true
coverage_status: uncovered
coverage_override:
  reason: approved
  by: carlos'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_OVNA" 2>/dev/null) || RC=$?
assert_eq "MEDIUM-1: override missing .at ⇒ NOT dispatchable" "1" "$RC"
# full {reason,by,at} ⇒ dispatchable + override_used:true (re-run WO_OV, assert the REAL result)
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_OV" 2>/dev/null) || RC=$?
assert_eq "MEDIUM-1: full {reason,by,at} override ⇒ dispatch (exit 0)" "0" "$RC"
assert_jq "MEDIUM-1: full {reason,by,at} override ⇒ dispatchable:true"  '.dispatchable'  'true' "$OUT"
assert_jq "MEDIUM-1: full {reason,by,at} override ⇒ override_used:true" '.override_used' 'true' "$OUT"

# === MEDIUM-2 regression: verified:true must AGREE with coverage_status ===
# verified:true but coverage_status:poisoned, NO override ⇒ NOT dispatchable, reason "poisoned"
WO_VTP="$TMPDIR/wo-vtp.md"
write_wo "$WO_VTP" 'id: local:t#wo-08d
status: ready
verified: true
autonomy_safe: true
coverage_status: poisoned
coverage_override: null'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_VTP" 2>/dev/null) || RC=$?
assert_eq "MEDIUM-2: verified:true + poisoned, no override ⇒ NOT dispatchable" "1" "$RC"
assert_jq "MEDIUM-2: verified:true + poisoned ⇒ reason poisoned" '.reason' 'poisoned' "$OUT"
assert_jq "MEDIUM-2: verified:true + poisoned ⇒ dispatchable:false" '.dispatchable' 'false' "$OUT"
# verified:true + covered ⇒ dispatchable (the claim is honored when coverage agrees)
WO_VTC="$TMPDIR/wo-vtc.md"
write_wo "$WO_VTC" 'id: local:t#wo-08e
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
coverage_override: null'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_VTC" 2>/dev/null) || RC=$?
assert_eq "MEDIUM-2: verified:true + covered ⇒ dispatchable" "0" "$RC"
assert_jq "MEDIUM-2: verified:true + covered ⇒ override_used:false" '.override_used' 'false' "$OUT"
# verified:false + full valid override + poisoned ⇒ dispatch + override_used:true (legit override preserved)
WO_OVP="$TMPDIR/wo-ovp.md"
write_wo "$WO_OVP" 'id: local:t#wo-08f
status: ready
verified: false
autonomy_safe: true
coverage_status: poisoned
coverage_override:
  reason: human accepted the poison risk
  by: carlos
  at: 2026-06-08T12:00:00Z'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_OVP" 2>/dev/null) || RC=$?
assert_eq "MEDIUM-2: verified:false + valid override + poisoned ⇒ dispatch (override preserved)" "0" "$RC"
assert_jq "MEDIUM-2: legit override on poisoned WO ⇒ override_used:true" '.override_used' 'true' "$OUT"

# ═══════════════════════════════════════════════════════════════════════════
# GROUNDING regression — assert-dispatchable now mechanically enforces the
# lockfile gate + the H2 drift-guard receipt (were prose-only before).
# ═══════════════════════════════════════════════════════════════════════════
# === lockfile gate: an unpinnable ref (lockfile entry sha==null) BLOCKS dispatch ===
WO_UNPIN="$TMPDIR/wo-unpin.md"
write_wo "$WO_UNPIN" 'id: local:t#wo-gr1
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
lockfile:
  - {ref: r1@1, sha: abc123, excerpt_sha: e1, kind: recipe}
  - {ref: r2@1, sha: null, excerpt_sha: e2, kind: guide}'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_UNPIN" 2>/dev/null) || RC=$?
assert_eq "GROUNDING: a null-sha lockfile entry ⇒ NOT dispatchable" "1" "$RC"
assert_jq "GROUNDING: null-sha lockfile entry ⇒ reason unpinned_ref" '.reason' 'unpinned_ref' "$OUT"
assert_jq "GROUNDING: null-sha lockfile entry ⇒ dispatchable:false" '.dispatchable' 'false' "$OUT"
# all non-null shas ⇒ the lockfile clause passes (drift clean too) ⇒ dispatch
WO_PINNED="$TMPDIR/wo-pinned.md"
write_wo "$WO_PINNED" 'id: local:t#wo-gr2
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
lockfile:
  - {ref: r1@1, sha: abc123, excerpt_sha: e1, kind: recipe}'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_PINNED" 2>/dev/null) || RC=$?
assert_eq "GROUNDING: all-pinned lockfile ⇒ dispatchable" "0" "$RC"

# === H2: the drift-guard receipt ("skipped" / false / missing all FAIL) ===
WO_DSKIP="$TMPDIR/wo-dskip.md"
write_wo "$WO_DSKIP" 'id: local:t#wo-gr3
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: skipped, acceptance_runnable: true}'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_DSKIP" 2>/dev/null) || RC=$?
assert_eq "GROUNDING: drift symbols_resolved:skipped ⇒ NOT dispatchable" "1" "$RC"
assert_jq "GROUNDING: drift skipped ⇒ reason drift_skipped" '.reason' 'drift_skipped' "$OUT"
WO_DFALSE="$TMPDIR/wo-dfalse.md"
write_wo "$WO_DFALSE" 'id: local:t#wo-gr4
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: false, acceptance_runnable: true}'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_DFALSE" 2>/dev/null) || RC=$?
assert_jq "GROUNDING: drift symbols_resolved:false ⇒ reason drift_unresolved" '.reason' 'drift_unresolved' "$OUT"
WO_DACC="$TMPDIR/wo-dacc.md"
write_wo "$WO_DACC" 'id: local:t#wo-gr5
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: false}'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_DACC" 2>/dev/null) || RC=$?
assert_jq "GROUNDING: drift acceptance_runnable:false ⇒ reason acceptance_not_runnable" '.reason' 'acceptance_not_runnable' "$OUT"
# a WO MISSING drift_guard entirely ⇒ NOT dispatchable (no receipt = fail-closed)
WO_NODRIFT="$TMPDIR/wo-nodrift.md"
write_wo "$WO_NODRIFT" 'id: local:t#wo-gr6
status: ready
verified: true
autonomy_safe: true
coverage_status: covered'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_NODRIFT" 2>/dev/null) || RC=$?
assert_eq "GROUNDING: missing drift_guard ⇒ NOT dispatchable (fail-closed)" "1" "$RC"
assert_jq "GROUNDING: missing drift_guard ⇒ dispatchable:false" '.dispatchable' 'false' "$OUT"

# === a FULLY-clean WO (all grounding gates green) ⇒ dispatch, override_used:false ===
WO_CLEAN="$TMPDIR/wo-clean.md"
write_wo "$WO_CLEAN" 'id: local:t#wo-gr7
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
lockfile:
  - {ref: r1@1, sha: a1, excerpt_sha: e1, kind: recipe}
  - {ref: g1, sha: b2, excerpt_sha: e2, kind: guide}
drift_guard: {symbols_resolved: true, acceptance_runnable: true}'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_CLEAN" 2>/dev/null) || RC=$?
assert_eq "GROUNDING: fully-clean WO ⇒ dispatchable" "0" "$RC"
assert_jq "GROUNDING: fully-clean WO ⇒ dispatchable:true" '.dispatchable' 'true' "$OUT"
assert_jq "GROUNDING: fully-clean WO ⇒ override_used:false" '.override_used' 'false' "$OUT"
assert_jq "GROUNDING: fully-clean WO ⇒ reason dispatchable" '.reason' 'dispatchable' "$OUT"

# === override bypasses ALL grounding (coverage+lockfile+drift) but NOT status ===
WO_OVGR="$TMPDIR/wo-ovgr.md"
write_wo "$WO_OVGR" 'id: local:t#wo-gr8
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
lockfile:
  - {ref: r1@1, sha: null, excerpt_sha: e1, kind: recipe}
coverage_override:
  reason: human pinned the ref out of band
  by: carlos
  at: 2026-06-08T00:00:00Z'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_OVGR" 2>/dev/null) || RC=$?
assert_eq "GROUNDING: valid override on an unpinned_ref WO ⇒ dispatch" "0" "$RC"
assert_jq "GROUNDING: override bypasses grounding ⇒ override_used:true" '.override_used' 'true' "$OUT"
# 2026-06-11: autonomy_safe:false no longer halts — override bypasses grounding, status is ready ⇒ dispatch.
WO_OVGRA="$TMPDIR/wo-ovgra.md"
write_wo "$WO_OVGRA" 'id: local:t#wo-gr9
status: ready
verified: true
autonomy_safe: false
coverage_status: covered
lockfile:
  - {ref: r1@1, sha: null, excerpt_sha: e1, kind: recipe}
coverage_override:
  reason: human pinned the ref out of band
  by: carlos
  at: 2026-06-08T00:00:00Z'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_OVGRA" 2>/dev/null) || RC=$?
assert_eq "2026-06-11: override on unpinned + autonomy_safe:false ⇒ dispatch (autonomy no longer gates)" "0" "$RC"
assert_jq "2026-06-11: override + autonomy_safe:false ⇒ dispatchable:true"  '.dispatchable'  'true' "$OUT"
assert_jq "2026-06-11: override + autonomy_safe:false ⇒ override_used:true" '.override_used' 'true' "$OUT"

# === a `lockfile` present-but-NON-ARRAY ⇒ fail-closed (treat as not-clean) ===
WO_LFNA="$TMPDIR/wo-lfna.md"
write_wo "$WO_LFNA" 'id: local:t#wo-gr10
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
lockfile: "not-an-array"'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_LFNA" 2>/dev/null) || RC=$?
assert_eq "GROUNDING: lockfile present-but-non-array ⇒ NOT dispatchable" "1" "$RC"
assert_jq "GROUNDING: non-array lockfile ⇒ reason unpinned_ref" '.reason' 'unpinned_ref' "$OUT"
# a non-object lockfile ELEMENT ⇒ fail-closed too
WO_LFNO="$TMPDIR/wo-lfno.md"
write_wo "$WO_LFNO" 'id: local:t#wo-gr11
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
lockfile: ["just-a-string"]'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_LFNO" 2>/dev/null) || RC=$?
assert_eq "GROUNDING: non-object lockfile element ⇒ NOT dispatchable" "1" "$RC"

# === reason precedence: coverage failures still rank BEFORE grounding receipts ===
# verified:false + a null-sha lockfile ⇒ reason is verified_false (coverage first), NOT unpinned_ref
WO_PREC="$TMPDIR/wo-prec.md"
write_wo "$WO_PREC" 'id: local:t#wo-gr12
status: ready
verified: false
autonomy_safe: true
coverage_status: uncovered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
lockfile:
  - {ref: r1@1, sha: null, excerpt_sha: e1, kind: recipe}'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$WO_PREC" 2>/dev/null) || RC=$?
assert_jq "GROUNDING: coverage reason (uncovered) ranks before unpinned_ref" '.reason' 'uncovered' "$OUT"

# a missing WO file ⇒ non-zero + dispatchable:false
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$TMPDIR/nope.md" 2>/dev/null) || RC=$?
assert_eq "missing WO file ⇒ non-zero"          "1"     "$RC"
assert_jq "missing WO file ⇒ dispatchable:false" '.dispatchable' 'false' "$OUT"

# ═══════════════════════════════════════════════════════════════════════════
# (g) collect-handle
# ═══════════════════════════════════════════════════════════════════════════
REPO="$TMPDIR/tree"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.test
git -C "$REPO" config user.name "t"
printf 'a\n' > "$REPO/a.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m base
CP_BEFORE=$(git -C "$REPO" rev-parse HEAD)

WO_HANDLE="$TMPDIR/wo-handle.md"
write_wo "$WO_HANDLE" 'id: local:t#wo-09
status: ready
verified: true
autonomy_safe: true'

# === Test: NO changes ⇒ produced_changes:false AND checkpoint_after:null ===
RC=0; OUT=$(bash "$SUT" collect-handle "$REPO" "$WO_HANDLE" --checkpoint-before "$CP_BEFORE" \
  --dispatched true --build-returned true 2>/dev/null) || RC=$?
assert_eq "collect-handle (no changes) exits 0" "0" "$RC"
assert_jq "no changes ⇒ produced_changes:false"  '.produced_changes' 'false' "$OUT"
assert_jq "no changes ⇒ checkpoint_after:null"   '.checkpoint_after' 'null'  "$OUT"
assert_jq "no changes ⇒ iff holds (after==null ⟺ produced==false)" \
  '(.checkpoint_after == null) == (.produced_changes == false)' 'true' "$OUT"
assert_jq "handle carries wo_id from disk"       '.wo_id' 'local:t#wo-09' "$OUT"
assert_jq "handle reflects --dispatched flag"    '.dispatched' 'true' "$OUT"

# === Test: real changes ⇒ produced_changes:true AND checkpoint_after==new HEAD ===
printf 'b\n' > "$REPO/b.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "wo-09: add b"
CP_AFTER=$(git -C "$REPO" rev-parse HEAD)
RC=0; OUT=$(bash "$SUT" collect-handle "$REPO" "$WO_HANDLE" --checkpoint-before "$CP_BEFORE" \
  --dispatched true --build-returned true 2>/dev/null) || RC=$?
assert_jq "changes ⇒ produced_changes:true"      '.produced_changes' 'true' "$OUT"
assert_jq "changes ⇒ checkpoint_after==new HEAD" '.checkpoint_after' "$CP_AFTER" "$OUT"
assert_jq "changes ⇒ iff holds (after!=null ⟺ produced==true)" \
  '(.checkpoint_after != null) == (.produced_changes == true)' 'true' "$OUT"
assert_jq "changes ⇒ artifacts list the changed file" '.artifacts | index("b.txt") != null' 'true' "$OUT"

# === Test: the handle has NO verdict / next / status key (siblings' concerns) ===
assert_jq "handle has no verdict/next/status key" 'has("verdict") or has("next") or has("status")' 'false' "$OUT"

# === Test: the handle is EXACTLY the 10 contract keys (zero transcript fields) ===
EXPECT_KEYS="artifacts,build_returned,checkpoint_after,checkpoint_before,dispatched,halt_reason,override_used,produced_changes,tree,wo_id"
assert_jq "handle is exactly the 10 contract keys (no transcript-derived field)" \
  'keys | join(",")' "$EXPECT_KEYS" "$OUT"

# === Test: a halt-before-spawn handle (not dispatched) is still well-formed ===
RC=0; OUT=$(bash "$SUT" collect-handle "$REPO" "$WO_HANDLE" --checkpoint-before "$CP_AFTER" \
  --dispatched false --halt-reason verified_false --build-returned false 2>/dev/null) || RC=$?
assert_jq "halt handle ⇒ dispatched:false"          '.dispatched' 'false' "$OUT"
assert_jq "halt handle ⇒ halt_reason carried"       '.halt_reason' 'verified_false' "$OUT"
assert_jq "halt handle ⇒ produced_changes:false"    '.produced_changes' 'false' "$OUT"

# === Test: missing positional args ⇒ exit 2 ===
RC=0; bash "$SUT" collect-handle "$REPO" >/dev/null 2>&1 || RC=$?
assert_eq "collect-handle with missing <wo-file> ⇒ exit 2" "2" "$RC"

# === MEDIUM-4 regression: git arg-injection via --checkpoint-before ===
# An option-shaped checkpoint ('--output=…') must NOT reach git (arbitrary file
# write); the file is NOT created AND the 10-key handle is still emitted.
PWN="$TMPDIR/.wo-pwn"
rm -f "$PWN"
RC=0; OUT=$(bash "$SUT" collect-handle "$REPO" "$WO_HANDLE" --checkpoint-before "--output=$PWN" 2>/dev/null) || RC=$?
if [ -f "$PWN" ]; then
  fail_check "MEDIUM-4: arg-injection FAILED — git wrote $PWN via --output="
  rm -f "$PWN"
else
  pass_check "MEDIUM-4: --output= arg-injection neutralized (no file written)"
fi
assert_jq "MEDIUM-4: handle still has exactly the 10 contract keys" \
  'keys | join(",")' "$EXPECT_KEYS" "$OUT"
assert_jq "MEDIUM-4: a non-sha checkpoint ⇒ produced_changes:false (no baseline)" '.produced_changes' 'false' "$OUT"
# a normal short-sha checkpoint still works (regex allows 7-40 hex)
SHORT=$(git -C "$REPO" rev-parse --short=8 HEAD)
RC=0; OUT=$(bash "$SUT" collect-handle "$REPO" "$WO_HANDLE" --checkpoint-before "$SHORT" 2>/dev/null) || RC=$?
assert_jq "MEDIUM-4: a valid short sha is still accepted (10-key handle)" 'keys | length' '10' "$OUT"
# R2-LOW: a MULTILINE checkpoint-before (line-oriented regex bypass) ⇒ rejected,
# checkpoint_before not polluted into the handle (the write is already blocked by
# --end-of-options; this stops the second line passing the per-line sha regex).
PWN2="$TMPDIR/.wo-pwn-ml"
rm -f "$PWN2"
ML_CPB=$(printf -- '--output=%s\n%s' "$PWN2" "$CP_BEFORE")
RC=0; OUT=$(bash "$SUT" collect-handle "$REPO" "$WO_HANDLE" --checkpoint-before "$ML_CPB" 2>/dev/null) || RC=$?
if [ -f "$PWN2" ]; then
  fail_check "R2-LOW: multiline checkpoint FAILED — git wrote $PWN2"
  rm -f "$PWN2"
else
  pass_check "R2-LOW: multiline checkpoint neutralized (no file written)"
fi
assert_jq "R2-LOW: multiline checkpoint ⇒ checkpoint_before NOT polluted (null)" '.checkpoint_before' 'null' "$OUT"
assert_jq "R2-LOW: multiline checkpoint ⇒ still a 10-key handle" 'keys | length' '10' "$OUT"

# ═══════════════════════════════════════════════════════════════════════════
# Security: RCE / injection smoke + no-eval literal-byte check
# ═══════════════════════════════════════════════════════════════════════════
RCE_MARKER="$TMPDIR/.wo-RCE-MARKER"
rm -f "$RCE_MARKER"
# An adversarial WO file whose UNTRUSTED fields carry command-substitution and
# shell metacharacters. The kernel must parse them as DATA (yaml.safe_load + jq
# --arg), never execute them. Quoted heredoc ⇒ no expansion when WRITING.
WO_EVIL="$TMPDIR/wo-evil.md"
cat > "$WO_EVIL" <<EOF
---
id: 'local:t#wo-evil \$(touch $RCE_MARKER)'
status: ready
verified: true
autonomy_safe: true
title: "\$(touch $RCE_MARKER); rm -rf /tmp/x; \`touch $RCE_MARKER\`"
coverage_override:
  reason: "; touch $RCE_MARKER #"
coverage_status: covered
---

# Evil WO
EOF
bash "$SUT" assert-dispatchable "$WO_EVIL" >/dev/null 2>&1 || true
bash "$SUT" collect-handle "$REPO" "$WO_EVIL" --checkpoint-before "$CP_BEFORE" >/dev/null 2>&1 || true
if [ -f "$RCE_MARKER" ]; then
  fail_check "RCE smoke FAILED — adversarial WO field executed a command"
  rm -f "$RCE_MARKER"
else
  pass_check "RCE smoke passed — adversarial WO fields NOT executed (parsed as data)"
fi

# No-eval literal-byte check (the kernel must never eval).
EVAL_COUNT=$(grep -cE '^[[:space:]]*eval[[:space:]]' "$SUT" 2>/dev/null || true)
EVAL_COUNT=${EVAL_COUNT:-0}
if [ "$EVAL_COUNT" -eq 0 ] 2>/dev/null; then
  pass_check "no eval in wo-compile.sh (literal-byte check)"
else
  fail_check "eval present in wo-compile.sh ($EVAL_COUNT) — RCE regression"
fi

# === MEDIUM-3 regression: a YAML alias/anchor bomb yields a FAST __error__ ===
# An 8-level billion-laughs (small input) would expand to GBs at json.dumps time
# ⇒ OOM/hang, breaking the kernel's TOTAL guarantee. Rejecting aliases makes it
# error immediately. Guarded by `timeout 5` (no hang) + `ulimit -v` (bounded mem).
BOMB="$TMPDIR/wo-bomb.md"
cat > "$BOMB" <<'EOF'
---
a: &a ["x","x","x","x","x","x","x","x","x","x"]
b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a,*a]
c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b,*b]
d: &d [*c,*c,*c,*c,*c,*c,*c,*c,*c,*c]
e: &e [*d,*d,*d,*d,*d,*d,*d,*d,*d,*d]
f: &f [*e,*e,*e,*e,*e,*e,*e,*e,*e,*e]
g: &g [*f,*f,*f,*f,*f,*f,*f,*f,*f,*f]
h: &h [*g,*g,*g,*g,*g,*g,*g,*g,*g,*g]
status: ready
id: local:t#wo-bomb
---
EOF
BRC=0
BOUT=$(timeout 5 bash -c 'ulimit -v 2000000 2>/dev/null; bash "$1" assert-dispatchable "$2" 2>/dev/null' _ "$SUT" "$BOMB") || BRC=$?
if [ "$BRC" -ne 124 ] 2>/dev/null; then
  pass_check "MEDIUM-3: alias bomb does NOT hang/OOM (exit $BRC, not 124 timeout)"
else
  fail_check "MEDIUM-3: alias bomb TIMED OUT/hung (exit 124) — TOTAL guarantee broken"
fi
assert_jq "MEDIUM-3: alias bomb ⇒ frontmatter_unreadable (alias rejected), parsed-not-hung" \
  '.reason | startswith("frontmatter_unreadable")' 'true' "$BOUT"
# a normal WO WITH ISO timestamps still parses fine (no false positive from the loader)
TSWO="$TMPDIR/wo-ts.md"
write_wo "$TSWO" 'id: local:t#wo-ts
status: ready
verified: true
autonomy_safe: true
coverage_status: covered
drift_guard: {symbols_resolved: true, acceptance_runnable: true}
compiled_at: 2026-06-08T00:00:00Z'
RC=0; OUT=$(bash "$SUT" assert-dispatchable "$TSWO" 2>/dev/null) || RC=$?
assert_eq "MEDIUM-3: a normal timestamped WO still parses + dispatches" "0" "$RC"

# ═══════════════════════════════════════════════════════════════════════════
# (h) set-status — K1 TDD test table (T1–T18)
# ═══════════════════════════════════════════════════════════════════════════
SSDIR="$TMPDIR/ss"
mkdir -p "$SSDIR"

# Fixtures are written with write_wo (already defined above) for simple cases
# and inline cat for multi-line YAML (blocked_by lists, duplicate status keys).

# === T1: ready → in_progress (legal dispatch transition) ===
WO_SS1="$SSDIR/wo-ss1.md"
write_wo "$WO_SS1" 'id: local:t#wo-ss1
status: ready
verified: true
autonomy_safe: true'
krun "" set-status "$WO_SS1" in_progress
assert_eq "T1: ready→in_progress exit 0"               "0"           "$RC"
assert_jq "T1: ready→in_progress ok:true"              '.ok'         'true'        "$OUT"
assert_jq "T1: ready→in_progress changed:true"         '.changed'    'true'        "$OUT"
assert_jq "T1: ready→in_progress previous_status"      '.previous_status' 'ready'  "$OUT"
assert_jq "T1: ready→in_progress new_status"           '.new_status' 'in_progress' "$OUT"
assert_jq "T1: ready→in_progress reason:dispatch"      '.reason'     'dispatch'    "$OUT"

# === T2: in_progress → done ===
WO_SS2="$SSDIR/wo-ss2.md"
write_wo "$WO_SS2" 'id: local:t#wo-ss2
status: in_progress'
krun "" set-status "$WO_SS2" done
assert_eq "T2: in_progress→done exit 0"   "0"    "$RC"
assert_jq "T2: in_progress→done ok:true"  '.ok'  'true' "$OUT"
assert_jq "T2: in_progress→done reason"   '.reason' 'ok' "$OUT"

# === T3: in_progress → needs_rework ===
WO_SS3="$SSDIR/wo-ss3.md"
write_wo "$WO_SS3" 'id: local:t#wo-ss3
status: in_progress'
krun "" set-status "$WO_SS3" needs_rework
assert_eq "T3: in_progress→needs_rework exit 0"  "0"    "$RC"
assert_jq "T3: in_progress→needs_rework ok:true" '.ok'  'true' "$OUT"
assert_jq "T3: in_progress→needs_rework reason"  '.reason' 'ok' "$OUT"

# === T4: needs_rework → ready (the C2 return edge) ===
WO_SS4="$SSDIR/wo-ss4.md"
write_wo "$WO_SS4" 'id: local:t#wo-ss4
status: needs_rework'
krun "" set-status "$WO_SS4" ready
assert_eq "T4: needs_rework→ready exit 0"       "0"    "$RC"
assert_jq "T4: needs_rework→ready ok:true"      '.ok'  'true'    "$OUT"
assert_jq "T4: needs_rework→ready reason:requeue" '.reason' 'requeue' "$OUT"

# === T5: blocked → ready (all blocked_by siblings done — deps_cleared) ===
WO_SS5_DEP="$SSDIR/wo-01-dep.md"
write_wo "$WO_SS5_DEP" 'id: local:t#wo-01
status: done'
WO_SS5="$SSDIR/wo-02-main.md"
cat > "$WO_SS5" <<'SS5EOF'
---
id: local:t#wo-02
status: blocked
blocked_by:
  - local:t#wo-01
---

# Work Order
SS5EOF
krun "" set-status "$WO_SS5" ready
assert_eq "T5: blocked→ready (deps done) exit 0"        "0"    "$RC"
assert_jq "T5: blocked→ready ok:true"                   '.ok'  'true'         "$OUT"
assert_jq "T5: blocked→ready reason:deps_cleared"       '.reason' 'deps_cleared' "$OUT"
assert_jq "T5: blocked→ready changed:true"              '.changed' 'true'      "$OUT"

# === T6: done → ready (terminal; illegal_transition) ===
WO_SS6="$SSDIR/wo-ss6.md"
write_wo "$WO_SS6" 'id: local:t#wo-ss6
status: done'
krun "" set-status "$WO_SS6" ready
assert_eq "T6: done→ready exit non-zero"                        "1"     "$RC"
assert_jq "T6: done→ready ok:false"                             '.ok'   'false' "$OUT"
assert_jq "T6: done→ready reason illegal_transition:done->ready" '.reason' 'illegal_transition:done->ready' "$OUT"

# === T7: ready → done (illegal_transition) ===
WO_SS7="$SSDIR/wo-ss7.md"
write_wo "$WO_SS7" 'id: local:t#wo-ss7
status: ready'
krun "" set-status "$WO_SS7" done
assert_eq "T7: ready→done exit non-zero"                         "1"     "$RC"
assert_jq "T7: ready→done ok:false"                              '.ok'   'false' "$OUT"
assert_jq "T7: ready→done reason illegal_transition:ready->done" '.reason' 'illegal_transition:ready->done' "$OUT"

# === T8: in_progress → in_progress (same-status noop; changed:false) ===
WO_SS8="$SSDIR/wo-ss8.md"
write_wo "$WO_SS8" 'id: local:t#wo-ss8
status: in_progress'
krun "" set-status "$WO_SS8" in_progress
assert_eq "T8: in_progress→in_progress exit 0 (noop)" "0"    "$RC"
assert_jq "T8: noop ok:true"                          '.ok'  'true'              "$OUT"
assert_jq "T8: noop changed:false"                    '.changed' 'false'         "$OUT"
assert_jq "T8: noop reason:noop_same_status"          '.reason' 'noop_same_status' "$OUT"

# === T9: ready → bogus (invalid new_status) ===
WO_SS9="$SSDIR/wo-ss9.md"
write_wo "$WO_SS9" 'id: local:t#wo-ss9
status: ready'
krun "" set-status "$WO_SS9" bogus
assert_eq "T9: invalid new_status exit non-zero"               "1"    "$RC"
assert_jq "T9: invalid new_status ok:false"                    '.ok'  'false' "$OUT"
assert_jq "T9: invalid new_status reason invalid_status:bogus" '.reason' 'invalid_status:bogus' "$OUT"

# === T10: file status: foobar → ready (invalid current status) ===
WO_SS10="$SSDIR/wo-ss10.md"
write_wo "$WO_SS10" 'id: local:t#wo-ss10
status: foobar'
krun "" set-status "$WO_SS10" ready
assert_eq "T10: invalid current status exit non-zero"                  "1"    "$RC"
assert_jq "T10: invalid current status ok:false"                       '.ok'  'false' "$OUT"
assert_jq "T10: invalid current status reason invalid_status:foobar"   '.reason' 'invalid_status:foobar' "$OUT"

# === T11: FM with TWO status: lines ⇒ ambiguous_status_field (fail-closed) ===
WO_SS11="$SSDIR/wo-ss11.md"
cat > "$WO_SS11" <<'SS11EOF'
---
id: local:t#wo-ss11
status: ready
status: ready
verified: true
---

# Work Order
SS11EOF
krun "" set-status "$WO_SS11" in_progress
assert_eq "T11: two status: lines exit non-zero"     "1"    "$RC"
assert_jq "T11: ambiguous_status_field ok:false"     '.ok'  'false'                  "$OUT"
assert_jq "T11: ambiguous_status_field reason"       '.reason' 'ambiguous_status_field' "$OUT"

# === T12: missing wo-file arg ⇒ exit 2 ===
krun "" set-status
assert_eq "T12: missing wo-file arg ⇒ exit 2" "2" "$RC"

# === T13: metachar new_status (adversarial; no eval, no write, inert) ===
WO_SS13="$SSDIR/wo-ss13.md"
write_wo "$WO_SS13" 'id: local:t#wo-ss13
status: ready'
ORIG_SS13=$(cat "$WO_SS13")
SS_EVIL='; rm -rf ~'
krun "" set-status "$WO_SS13" "$SS_EVIL"
assert_eq "T13: metachar status exit non-zero (invalid_status)"  "1"    "$RC"
assert_jq "T13: metachar status ok:false"                        '.ok'  'false' "$OUT"
assert_jq "T13: metachar status reason starts with invalid_status" '.reason | startswith("invalid_status")' 'true' "$OUT"
AFTER_SS13=$(cat "$WO_SS13")
assert_eq "T13: metachar status — file NOT modified (inert)"     "$ORIG_SS13" "$AFTER_SS13"

# === T14: FM unreadable (__error__) ⇒ frontmatter_unreadable ===
# A YAML alias triggers the anchor rejection in wo_frontmatter_json → __error__.
WO_SS14="$SSDIR/wo-ss14.md"
cat > "$WO_SS14" <<'SS14EOF'
---
anchor: &a ready
status: *a
---

# Work Order
SS14EOF
krun "" set-status "$WO_SS14" ready
assert_eq "T14: FM unreadable exit non-zero"               "1"    "$RC"
assert_jq "T14: FM unreadable ok:false"                    '.ok'  'false' "$OUT"
assert_jq "T14: FM unreadable reason:frontmatter_unreadable" '.reason' 'frontmatter_unreadable' "$OUT"

# === T15: round-trip fidelity — only status: line changed, rest byte-identical ===
WO_SS15="$SSDIR/wo-ss15.md"
cat > "$WO_SS15" <<'SS15EOF'
---
id: local:t#wo-ss15
kind: work-order
status: ready
verified: true
autonomy_safe: true
extra_field: should_be_preserved
---

# Round-trip body
Body content preserved verbatim.
This line must survive the write unchanged.
SS15EOF
ORIG_SS15=$(cat "$WO_SS15")
krun "" set-status "$WO_SS15" in_progress
assert_eq "T15: round-trip exit 0"   "0"    "$RC"
assert_jq "T15: round-trip ok:true"  '.ok'  'true' "$OUT"
NEW_SS15=$(cat "$WO_SS15")
# The only changed line is `status: ready` → `status: in_progress`; everything else byte-identical.
EXPECTED_SS15=$(printf '%s' "$ORIG_SS15" | sed 's/^status: ready$/status: in_progress/')
assert_eq "T15: round-trip — body + other FM fields byte-identical; only status: changed" \
  "$EXPECTED_SS15" "$NEW_SS15"

# === T16: blocked (one blocked_by sibling still in_progress) → ready ⇒ deps_not_done ===
WO_SS16_DEP="$SSDIR/wo-10-inprog.md"
write_wo "$WO_SS16_DEP" 'id: local:t#wo-10
status: in_progress'
WO_SS16="$SSDIR/wo-11-blocked.md"
cat > "$WO_SS16" <<'SS16EOF'
---
id: local:t#wo-11
status: blocked
blocked_by:
  - local:t#wo-10
---

# Work Order
SS16EOF
ORIG_SS16=$(cat "$WO_SS16")
krun "" set-status "$WO_SS16" ready
assert_eq "T16: deps not done exit non-zero"                        "1"    "$RC"
assert_jq "T16: deps not done ok:false"                             '.ok'  'false' "$OUT"
assert_jq "T16: deps_not_done:<id> in reason"  '.reason | startswith("deps_not_done:")' 'true' "$OUT"
AFTER_SS16=$(cat "$WO_SS16")
assert_eq "T16: no write on deps failure — file unchanged" "$ORIG_SS16" "$AFTER_SS16"

# === T17: blocked (no matching sibling file) → ready ⇒ deps_unresolvable ===
WO_SS17="$SSDIR/wo-20-ghost.md"
cat > "$WO_SS17" <<'SS17EOF'
---
id: local:t#wo-20
status: blocked
blocked_by:
  - local:t#wo-99
---

# Work Order
SS17EOF
ORIG_SS17=$(cat "$WO_SS17")
krun "" set-status "$WO_SS17" ready
assert_eq "T17: unresolvable dep exit non-zero"                      "1"    "$RC"
assert_jq "T17: deps_unresolvable ok:false"                          '.ok'  'false' "$OUT"
assert_jq "T17: deps_unresolvable reason" '.reason | startswith("deps_unresolvable:")' 'true' "$OUT"
AFTER_SS17=$(cat "$WO_SS17")
assert_eq "T17: no write on unresolvable dep — file unchanged" "$ORIG_SS17" "$AFTER_SS17"

# === T18: blocked (blocked_by: []) → ready ⇒ deps_cleared (no deps) ===
WO_SS18="$SSDIR/wo-30-noblockers.md"
cat > "$WO_SS18" <<'SS18EOF'
---
id: local:t#wo-30
status: blocked
blocked_by: []
---

# Work Order
SS18EOF
krun "" set-status "$WO_SS18" ready
assert_eq "T18: empty blocked_by exit 0"               "0"    "$RC"
assert_jq "T18: empty blocked_by ok:true"              '.ok'  'true'         "$OUT"
assert_jq "T18: empty blocked_by reason:deps_cleared"  '.reason' 'deps_cleared' "$OUT"
assert_jq "T18: empty blocked_by changed:true"         '.changed' 'true'     "$OUT"

# === T19: CRLF file — set-status must preserve \r on the rewritten status line ===
# Verify byte-identical fidelity for CRLF-encoded WO files: every line (including
# the rewritten status: line) must still end with \r after the surgical write.
WO_SS19="$SSDIR/wo-ss19.md"
# Use '%s\r\n' to avoid the format-string-starting-with-'---' option-parse issue.
printf '%s\r\n' '---' 'id: local:t#wo-ss19' 'status: ready' 'autonomy_safe: true' '---' '' '# Body' > "$WO_SS19"
lines_total_pre=$(wc -l < "$WO_SS19")
lines_cr_pre=$(grep -cP '\r$' "$WO_SS19" 2>/dev/null || echo 0)
assert_eq "T19: pre-condition — fixture is CRLF (all lines end with \\r)" \
  "$lines_total_pre" "$lines_cr_pre"
krun "" set-status "$WO_SS19" in_progress
assert_eq "T19: CRLF set-status exit 0"    "0"    "$RC"
assert_jq "T19: CRLF set-status ok:true"  '.ok'  'true'        "$OUT"
assert_jq "T19: CRLF set-status changed"  '.changed' 'true'    "$OUT"
lines_total_after=$(wc -l < "$WO_SS19")
lines_cr_after=$(grep -cP '\r$' "$WO_SS19" 2>/dev/null || echo 0)
assert_eq "T19: CRLF preserved after set-status — all lines still CRLF (LOW-1)" \
  "$lines_total_after" "$lines_cr_after"
# Confirm the status VALUE was updated (not left as "ready")
T19_STATUS=$(grep -oP '(?<=^status: )\S+' "$WO_SS19" 2>/dev/null | tr -d '\r' || echo "")
assert_eq "T19: status value updated to in_progress" "in_progress" "$T19_STATUS"

# === T20: blocked_by fragment with metachar → deps_unresolvable, no write (LOW-2) ===
# A crafted fragment like "wo-*" must be rejected by grammar validation, not handed
# to find as a shell glob (which could match exactly one unintended sibling).
# Setup: controlled dir with ONE file matching "wo-*-*.md" and status:done, so
# before the fix find() resolves a single match and the call succeeds (wrong).
T20DIR="$TMPDIR/t20"
mkdir -p "$T20DIR"
# The lone sibling that the glob would match if not caught:
printf '%s\n' '---' 'id: local:t#wo-00' 'status: done' '---' '' '# Done sibling' > "$T20DIR/wo-00-done.md"
# The WO under test (named without "wo-NN-" prefix so it doesn't match the glob itself):
cat > "$T20DIR/blocker.md" <<'T20EOF'
---
id: local:t#wo-50
status: blocked
blocked_by:
  - local:t#wo-*
---

# Work Order
T20EOF
ORIG_T20=$(cat "$T20DIR/blocker.md")
krun "" set-status "$T20DIR/blocker.md" ready
assert_eq "T20: metachar fragment exit non-zero (LOW-2)"                            "1"    "$RC"
assert_jq "T20: metachar fragment ok:false"                                         '.ok'  'false' "$OUT"
assert_jq "T20: metachar fragment → deps_unresolvable" '.reason | startswith("deps_unresolvable:")' 'true' "$OUT"
AFTER_T20=$(cat "$T20DIR/blocker.md")
assert_eq "T20: metachar fragment — no write (file unchanged)" "$ORIG_T20" "$AFTER_T20"

# ═══════════════════════════════════════════════════════════════════════════
# Dispatch hygiene
# ═══════════════════════════════════════════════════════════════════════════
RC=0; bash "$SUT" no-such-subcommand >/dev/null 2>&1 || RC=$?
assert_eq "an unknown subcommand ⇒ exit 2" "2" "$RC"
RC=0; bash "$SUT" --help >/dev/null 2>&1 || RC=$?
assert_eq "--help ⇒ exit 0" "0" "$RC"

# ═══════════════════════════════════════════════════════════════════════════
if [ "$FAIL" -ne 0 ]; then
  printf '\nwo-compile.sh kernel invariants violated.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for scripts/wo-compile.sh.\n'
exit 0
