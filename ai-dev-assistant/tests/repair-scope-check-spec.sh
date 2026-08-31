#!/usr/bin/env bash
# Behavioral spec for scripts/repair-scope-check.sh (D6 of
# ../../projects/ai_dev_assistant/.../finding_contract/design/finding-contract.md). A set-comparison
# kernel: does every file a repair touched fall inside the finding's named where[] sites (or an
# --allow glob)? No model judgment, no diff computed here.
#
# The load-bearing cells:
#   - empty --finding-sites (nothing named)      → cannot_judge, NEVER in_scope. Folding an absent
#     site list into in_scope is the exact defect this repo keeps re-finding (mechanism-disposition.sh's
#     `not_searched`, proportionality-check.sh's `cannot_judge`).
#   - --touched-files-source undetermined        → cannot_judge, REGARDLESS of what --touched-files
#     holds — asserted with both an empty and a non-empty touched array, because a naive
#     implementation only guards the empty case (that was the actual gap wo-b.md's build report
#     records: `--touched-files '[]'` alone used to mean both "touched nothing" and "don't know",
#     and both collapsed into in_scope before the flag existed).
#   - every bad-argument form                    → exit 2, nothing on stdout (fail-closed, no verdict)
#   - --allow covers the only unnamed file        → in_scope (the glob exemption works)
#   - a path with a space and a path with a quote character round-trip through jq's own JSON
#     encoding intact — neither breaks parsing or gets silently dropped from `unnamed`.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/repair-scope-check.sh"
PASS=0; FAIL=0

# assert <label> <want action> <want blocks> <want decided_by> <want unnamed json> -- <K args...>
assert() {
  local label="$1" ea="$2" eb="$3" ed="$4" eu="$5"; shift 5
  [ "$1" = "--" ] && shift
  local out; out="$(bash "$K" "$@" 2>/dev/null)"
  local a b d u euc
  a="$(jq -r '.action' <<<"$out" 2>/dev/null)"
  b="$(jq -r '.blocks' <<<"$out" 2>/dev/null)"
  d="$(jq -r '.decided_by' <<<"$out" 2>/dev/null)"
  u="$(jq -c '.unnamed' <<<"$out" 2>/dev/null)"
  euc="$(jq -c . <<<"$eu")"
  if [ "$a" = "$ea" ] && [ "$b" = "$eb" ] && [ "$d" = "$ed" ] && [ "$u" = "$euc" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL $label: got {action=$a blocks=$b decided_by=$d unnamed=$u} want {$ea,$eb,$ed,$euc}"
    echo "  raw: $out"
  fi
}

# bad <label> <K args...> — must exit 2 with nothing at all on stdout (fail-closed, no verdict)
bad() {
  local label="$1"; shift
  local out ec
  out="$(bash "$K" "$@" 2>/dev/null)"; ec=$?
  if [ "$ec" -eq 2 ] && [ -z "$out" ]; then PASS=$((PASS+1))
  else FAIL=$((FAIL+1)); echo "FAIL $label: exit=$ec stdout='$out' (want exit=2, empty stdout)"; fi
}

# --- in_scope: repair entirely inside the named sites ---
assert "in_scope, two named, two touched" in_scope false sets '[]' \
  -- --finding-sites '["a.php","b.php"]' --touched-files '["a.php","b.php"]'

# --- out_of_scope: repair touches one file the finding never named, it lands in unnamed ---
assert "out_of_scope, one unnamed file listed" out_of_scope false sets '["c.php"]' \
  -- --finding-sites '["a.php"]' --touched-files '["a.php","c.php"]'

# --- --allow covers the unnamed file ---
assert "allow glob covers the unnamed file -> in_scope" in_scope false sets '[]' \
  -- --finding-sites '["a.php"]' --touched-files '["a.php","tests/c-spec.sh"]' --allow 'tests/*'

# --- cannot_judge on empty finding sites, never in_scope (the absence-reads-as-answer defect) ---
assert "cannot_judge: empty finding-sites, non-empty touched" cannot_judge false none '[]' \
  -- --finding-sites '[]' --touched-files '["a.php"]'
assert "cannot_judge: empty finding-sites, empty touched too" cannot_judge false none '[]' \
  -- --finding-sites '[]' --touched-files '[]'

# --- --touched-files-source undetermined forces cannot_judge regardless of --touched-files,
# asserted with BOTH an empty and a non-empty touched array: a naive implementation guards only
# the empty case, since an empty touched array happens to look like "nothing to compare" on its
# own — the non-empty case is what actually proves the guard runs before the comparison, not as a
# side effect of the set difference already being empty. ---
assert "undetermined + empty touched -> cannot_judge" cannot_judge false none '[]' \
  -- --finding-sites '["a.php"]' --touched-files '[]' --touched-files-source undetermined
assert "undetermined + NON-empty touched -> still cannot_judge" cannot_judge false none '[]' \
  -- --finding-sites '["a.php"]' --touched-files '["a.php","c.php"]' --touched-files-source undetermined

# control: the same non-empty touched set, source determined (the default), must NOT be cannot_judge
assert "control: same touched set, source determined -> out_of_scope" out_of_scope false sets '["c.php"]' \
  -- --finding-sites '["a.php"]' --touched-files '["a.php","c.php"]'

# --- a path with a space, and a path with a quote character, round-trip intact ---
assert "path with a space -> out_of_scope, unnamed carries it" out_of_scope false sets '["my file.php"]' \
  -- --finding-sites '["a.php"]' --touched-files '["a.php","my file.php"]'
assert 'path with a quote char -> out_of_scope, unnamed carries it' out_of_scope false sets '["fo\"o.php"]' \
  -- --finding-sites '["a.php"]' --touched-files '["a.php","fo\"o.php"]'
# and the same characters when they ARE named: no false out-of-scope from the quoting itself
assert "space/quote paths, all named -> in_scope" in_scope false sets '[]' \
  -- --finding-sites '["my file.php","fo\"o.php"]' --touched-files '["my file.php","fo\"o.php"]'

# --- every bad-argument form: exit 2, nothing on stdout ---
bad "missing --finding-sites"                          --touched-files '["a.php"]'
bad "missing --touched-files"                           --finding-sites '["a.php"]'
bad "--finding-sites, no value, end of args"             --finding-sites
bad "--finding-sites, value starting with --"            --finding-sites --allow
bad "--touched-files, no value, end of args"             --finding-sites '["a.php"]' --touched-files
bad "--touched-files, value starting with --"            --finding-sites '["a.php"]' --touched-files --allow
bad "--allow, no value"                                  --finding-sites '["a.php"]' --touched-files '["a.php"]' --allow
bad "--touched-files-source, no value"                   --finding-sites '["a.php"]' --touched-files '["a.php"]' --touched-files-source
bad "--finding-sites malformed JSON"                     --finding-sites 'not-json' --touched-files '["a.php"]'
bad "--touched-files malformed JSON"                     --finding-sites '["a.php"]' --touched-files 'not-json'
bad "--finding-sites not an array (object)"              --finding-sites '{"a":1}' --touched-files '["a.php"]'
bad "--finding-sites array of non-strings"                --finding-sites '[1,2]' --touched-files '["a.php"]'
bad "--touched-files-source bad enum value"               --finding-sites '["a.php"]' --touched-files '["a.php"]' --touched-files-source bogus
bad "unknown arg"                                          --finding-sites '["a.php"]' --touched-files '["a.php"]' --bogus x

# --- exit code discipline: a valid call exits 0 ---
bash "$K" --finding-sites '["a.php"]' --touched-files '["a.php"]' >/dev/null 2>&1
[ $? -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: a valid call should exit 0"; }

# --- guard: this spec must have checked something ---
[ "$((PASS + FAIL))" -gt 0 ] || { echo "repair-scope-check-spec: checked nothing"; exit 2; }

echo "----"; echo "repair-scope-check-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
