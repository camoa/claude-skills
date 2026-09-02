#!/usr/bin/env bash
# Behavioral spec for scripts/oracle-globs.sh (glob-source, review_ladder): where --test-globs come from,
# and the origin recorded beside them. Cells: a recipe with the block yields its test_delete globs, origin
# recipe; a recipe without it yields the fallback, origin convention; without block and without fallback
# the origin is undetermined and globs are [], never a positive empty claim; the markdown table beside the
# fence is not read, so when the two disagree the JSON wins; a heading inside a fence is not a heading;
# bad arguments exit 2 with nothing on stdout.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/oracle-globs.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: got '$2' want '$3'"; fi; }

cat > "$TMP/with.md" <<'MD'
## Goal
prose
## Oracle files
| Oracle file | Watches |
|---|---|
| `**/tests/**/*Test.php` and `**/legacy/*Test.php` (the table is stale) | delete |
```json
[
  { "type": "test_delete", "globs": ["**/tests/**/*Test.php", "**/test/**/*Test.php"], "changes": ["D"], "oracle_class": "test-delete", "severity": "halt" },
  { "type": "lint_config", "globs": ["phpcs.xml"], "changes": ["M"], "oracle_class": "lint-config", "severity": "flag" }
]
```
## References
MD
cat > "$TMP/without.md" <<'MD'
## Goal
```markdown
## Oracle files
```
prose that mentions ## Oracle files inside a fence only
MD
cat > "$TMP/norow.md" <<'MD'
## Oracle files
```json
[ { "type": "lint_config", "globs": ["phpcs.xml"], "changes": ["M"], "oracle_class": "lint-config", "severity": "flag" } ]
```
MD

out="$(bash "$K" --body "$TMP/with.md")"
check "recipe origin"         "$(jq -r .origin <<<"$out")" "recipe"
check "json globs, not table" "$(jq -c .globs <<<"$out")" '["**/tests/**/*Test.php","**/test/**/*Test.php"]'
check "type echoed"           "$(jq -r .type <<<"$out")" "test_delete"
out="$(bash "$K" --body "$TMP/without.md" --fallback-globs '["*/tests/*.sh"]')"
check "convention origin"     "$(jq -r .origin <<<"$out")" "convention"
check "fallback globs"        "$(jq -c .globs <<<"$out")" '["*/tests/*.sh"]'
out="$(bash "$K" --body "$TMP/without.md")"
check "undetermined origin"   "$(jq -r .origin <<<"$out")" "undetermined"
check "undetermined globs []" "$(jq -c .globs <<<"$out")" '[]'
check "reason recorded"       "$(jq -r '.reason != null' <<<"$out")" "true"
out="$(bash "$K" --body "$TMP/norow.md" --fallback-globs '["x"]')"
check "block without the row falls to convention" "$(jq -r .origin <<<"$out")" "convention"
out="$(bash "$K" --body "$TMP/with.md" --type lint_config)"
check "--type selects another row" "$(jq -c .globs <<<"$out")" '["phpcs.xml"]'
for args in "" "--body" "--body $TMP/nope.md" "--body $TMP/with.md --fallback-globs nope" "--body $TMP/with.md --fallback-globs []" "--body $TMP/with.md --bogus"; do
  # shellcheck disable=SC2086
  o="$(bash "$K" $args 2>/dev/null)"; rc=$?
  check "bad args ($args): exit 2, no stdout" "$rc/${o:-empty}" "2/empty"
done
[ "$((PASS + FAIL))" -gt 0 ] || { echo "oracle-globs-spec: checked nothing"; exit 2; }
echo "----"; echo "oracle-globs-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
