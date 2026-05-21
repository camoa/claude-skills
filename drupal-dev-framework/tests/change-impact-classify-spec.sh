#!/usr/bin/env bash
# change-impact-classify-spec.sh — verify scripts/change-impact-classify.sh (v4.11.0+).
#
# Covers: every default glob row, multi-match union, no-match default,
# --files-from, missing/malformed/absent project override, exit-0-always.
# Uses --files-from exclusively — no git fixture needed.
#
# Run pre-PR. Companion to tests/project-state-read-spec.sh.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/change-impact-classify.sh"

if [ ! -f "$SCRIPT" ]; then
  printf 'FAIL: %s not found\n' "$SCRIPT" >&2
  exit 1
fi

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# classify <label> <files-newline-string> <jq-filter> <expected> [task_folder]
classify() {
  local label="$1" files="$2" filter="$3" expected="$4" task="${5:-/nonexistent-task}"
  printf '%s\n' "$files" > "$TMPDIR/files.txt"
  local actual rc
  actual=$(bash "$SCRIPT" "$task" --files-from "$TMPDIR/files.txt" 2>/dev/null | jq -c "$filter")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_check "$label — script exited $rc (expected 0)"
    return
  fi
  if [ "$actual" = "$expected" ]; then
    pass_check "$label ($filter = $expected)"
  else
    fail_check "$label — $filter returned $actual (expected $expected)"
  fi
}

# === Test 1: every default glob row → gates_recommended ===
classify "css → visual_regression"   "web/style.css"          '.gates_recommended' '["visual_regression"]'
classify "scss → visual_regression"  "theme/_x.scss"          '.gates_recommended' '["visual_regression"]'
classify "twig → visual_regression"  "templates/node.twig"    '.gates_recommended' '["visual_regression"]'
classify "js → e2e+vr"               "js/app.js"              '.gates_recommended' '["e2e","visual_regression"]'
classify "ts → e2e+vr"               "src/app.ts"             '.gates_recommended' '["e2e","visual_regression"]'
classify "php → e2e+vr"              "src/Foo.php"            '.gates_recommended' '["e2e","visual_regression"]'
classify "yml → e2e+vr"              "config/foo.yml"         '.gates_recommended' '["e2e","visual_regression"]'
classify "module → e2e"              "my_module.module"       '.gates_recommended' '["e2e"]'

# === Test 2: multi-match union ===
# *.info.yml matches BOTH **/*.yml (e2e,vr) AND **/*.info.yml (e2e) → union.
classify "info.yml → union(e2e,vr)"  "my_module.info.yml"     '.gates_recommended' '["e2e","visual_regression"]'

# === Test 3: no-match → default_gates ([]) ===
classify "README → no gates"         "README.md"              '.gates_recommended' '[]'
classify "no-match files_classified" "README.md"              '.files_classified'  '1'

# === Test 4: mixed diff — union across files + diff_signature ===
classify "css+php → union"           "$(printf 'a.css\nb.php')" '.gates_recommended' '["e2e","visual_regression"]'
classify "css+php diff_signature"    "$(printf 'a.css\nb.php')" '.diff_signature'    '["**/*.css","**/*.php"]'
classify "css+php files_classified"  "$(printf 'a.css\nb.php')" '.files_classified'  '2'

# === Test 5: depth-independence (leading **/ means any depth) ===
classify "deep css matches"          "a/b/c/d/deep.css"       '.gates_recommended' '["visual_regression"]'
classify "root css matches"          "root.css"               '.gates_recommended' '["visual_regression"]'

# === Test 6: rule_source default ===
classify "rule_source default"       "x.css"                  '.rule_source'       '"default"'

# === Test 7: --files-from missing ===
rc=0
out=$(bash "$SCRIPT" /nonexistent-task --files-from "$TMPDIR/does-not-exist.txt" 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ] \
   && [ "$(echo "$out" | jq -r '.files_classified')" = "0" ] \
   && [ "$(echo "$out" | jq -r '.gates_recommended | length')" = "0" ] \
   && echo "$out" | jq -e '.warnings[] | select(startswith("files_from_missing"))' >/dev/null; then
  pass_check "missing --files-from → 0 files, [] gates, files_from_missing warning, exit 0"
else
  fail_check "missing --files-from handling — got: $out (rc=$rc)"
fi

# === Test 8: empty --files-from file ===
: > "$TMPDIR/empty.txt"
out=$(bash "$SCRIPT" /nonexistent-task --files-from "$TMPDIR/empty.txt" 2>/dev/null)
if [ "$(echo "$out" | jq -r '.files_classified')" = "0" ] \
   && [ "$(echo "$out" | jq -c '.gates_recommended')" = "[]" ]; then
  pass_check "empty --files-from file → 0 files, [] gates"
else
  fail_check "empty --files-from file — got: $out"
fi

# === Test 9: project override (full replacement) ===
PROJ="$TMPDIR/proj"
mkdir -p "$PROJ/.visual-review" "$PROJ/impl/task_x"
echo "# Test Project" > "$PROJ/project_state.md"
cat > "$PROJ/.visual-review/change-impact.json" <<'EOF'
{ "schema_version": "1.0",
  "rules": [ { "glob": "**/*.css", "gates": ["e2e"] } ],
  "default_gates": [] }
EOF
classify "override applies (css→e2e)" "x.css" '.gates_recommended' '["e2e"]' "$PROJ/impl/task_x"
classify "override sets rule_source"  "x.css" '.rule_source' '"project-override"' "$PROJ/impl/task_x"

# A real one-line file list, reused below (process substitution is not a
# regular file, so [ -f ] on it is false — the script would warn).
echo "x.css" > "$TMPDIR/onecss.txt"

# === Test 10: malformed override → fall back to defaults + warning ===
echo 'not json at all {{{' > "$PROJ/.visual-review/change-impact.json"
out=$(bash "$SCRIPT" "$PROJ/impl/task_x" --files-from "$TMPDIR/onecss.txt" 2>/dev/null)
if [ "$(echo "$out" | jq -r '.rule_source')" = "default" ] \
   && echo "$out" | jq -e '.warnings[] | select(startswith("override_malformed"))' >/dev/null; then
  pass_check "malformed override → defaults + override_malformed warning"
else
  fail_check "malformed override handling — got: $out"
fi

# === Test 11: absent override (project exists, no override file) → defaults, no warning ===
rm -f "$PROJ/.visual-review/change-impact.json"
out=$(bash "$SCRIPT" "$PROJ/impl/task_x" --files-from "$TMPDIR/onecss.txt" 2>/dev/null)
if [ "$(echo "$out" | jq -r '.rule_source')" = "default" ] \
   && [ "$(echo "$out" | jq -c '.warnings')" = "[]" ]; then
  pass_check "absent override → defaults, no warning"
else
  fail_check "absent override handling — got: $out"
fi

# === Test 12: exit 0 even with a bogus task folder ===
rc=0
bash "$SCRIPT" /bogus/task/path --files-from "$TMPDIR/onecss.txt" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  pass_check "exit 0 with bogus task folder"
else
  fail_check "expected exit 0 with bogus task folder, got $rc"
fi

# === Test 13: output is always valid JSON with the required keys ===
out=$(bash "$SCRIPT" /nonexistent --files-from "$TMPDIR/onecss.txt" 2>/dev/null)
if echo "$out" | jq -e \
     'has("schema_version") and has("diff_signature") and has("gates_recommended")
      and has("rule_source") and has("files_classified") and has("warnings")' >/dev/null; then
  pass_check "output JSON carries all six required keys"
else
  fail_check "output JSON missing required keys — got: $out"
fi

# === Test 14: CRLF line endings in --files-from (F-01 regression) ===
printf 'web/style.css\r\n' > "$TMPDIR/crlf.txt"
out=$(bash "$SCRIPT" /nonexistent-task --files-from "$TMPDIR/crlf.txt" 2>/dev/null)
if [ "$(echo "$out" | jq -c '.gates_recommended')" = '["visual_regression"]' ]; then
  pass_check "CRLF --files-from → trailing CR stripped, .css classified"
else
  fail_check "CRLF handling — got: $out"
fi

# === Test 15: override with `rules` as a JSON object → rejected (F-02 regression) ===
cat > "$PROJ/.visual-review/change-impact.json" <<'EOF'
{ "schema_version": "1.0", "rules": {"css": "**/*.css"}, "default_gates": [] }
EOF
out=$(bash "$SCRIPT" "$PROJ/impl/task_x" --files-from "$TMPDIR/onecss.txt" 2>/dev/null)
if [ "$(echo "$out" | jq -r '.rule_source')" = "default" ] \
   && echo "$out" | jq -e '.warnings[] | select(startswith("override_malformed"))' >/dev/null; then
  pass_check "override rules-as-object → rejected, defaults + override_malformed warning"
else
  fail_check "rules-as-object handling — got: $out"
fi

# === Test 16: a rule with `gates` as a string does not poison sibling rules (F-03 regression) ===
cat > "$PROJ/.visual-review/change-impact.json" <<'EOF'
{ "schema_version": "1.0",
  "rules": [ { "glob": "**/*.css", "gates": "visual_regression" },
             { "glob": "**/*.php", "gates": ["e2e"] } ],
  "default_gates": [] }
EOF
printf 'a.php\n' > "$TMPDIR/onephp.txt"
out=$(bash "$SCRIPT" "$PROJ/impl/task_x" --files-from "$TMPDIR/onephp.txt" 2>/dev/null)
if [ "$(echo "$out" | jq -c '.gates_recommended')" = '["e2e"]' ]; then
  pass_check "malformed rule (gates as string) does not poison the sibling .php rule"
else
  fail_check "malformed-rule isolation — got: $out"
fi
rm -f "$PROJ/.visual-review/change-impact.json"

if [ "$FAIL" -ne 0 ]; then
  printf '\nchange-impact-classify.sh invariants violated.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for scripts/change-impact-classify.sh.\n'
exit 0
