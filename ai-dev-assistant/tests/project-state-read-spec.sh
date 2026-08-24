#!/usr/bin/env bash
# project-state-read-spec.sh — verify scripts/project-state-read.sh parsing invariants (v4.1.0+).
#
# Tests:
#   - Case-insensitive header matrix for all 6 fields (works without IGNORECASE,
#     since some awk implementations don't honor it)
#   - Boolean variant matrix (truthy/falsy/garbage/empty) for both bool fields
#   - RCE regression (no eval; adversarial Code path doesn't execute)
#
# Run pre-PR; complements tests/upgrade-project-spec.sh.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
READER="${PLUGIN_ROOT}/scripts/project-state-read.sh"

if [ ! -f "$READER" ]; then
  printf 'FAIL: %s not found\n' "$READER" >&2
  exit 1
fi

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# === Test 1: case-insensitive header matrix ===
# Each field with 2-3 case variants should yield the same parse result.
# Variants: lowercase, Title Case, Mixed Case (e.g., **code path:** vs **Code Path:**)

test_header_case() {
  local field_human="$1"      # display name (e.g., "Worktree By Default")
  local field_value="$2"      # value to set (e.g., "true")
  local field_jq="$3"         # jq path to extract (e.g., ".worktreeByDefault")
  local expected="$4"         # expected jq output (e.g., "true")

  for variant in "$field_human" "$(printf '%s' "$field_human" | tr '[:upper:]' '[:lower:]')"; do
    cat > "$TMPDIR/project_state.md" <<EOF
# Test
**$variant:** $field_value
EOF
    actual=$(bash "$READER" "$TMPDIR" 2>/dev/null | jq -r "$field_jq")
    if [ "$actual" = "$expected" ]; then
      pass_check "header case '$variant' parses correctly ($field_jq=$expected)"
    else
      fail_check "header case '$variant' returned '$actual' (expected '$expected')"
    fi
  done
}

test_header_case "Worktree By Default" "true"  ".worktreeByDefault" "true"
test_header_case "Review Required"     "true"  ".reviewRequired"    "true"
# Code path, Playbook Sets etc. would need actual values; skip the matrix on those
# for v1 spec — broader audit landed in same PR but full matrix testing belongs
# to a future iteration of this spec file.

# === Test 2: boolean variant matrix ===
# parse_bool() should handle truthy variants for both bool fields.

test_bool_variants() {
  local field_human="$1"
  local field_jq="$2"
  local empty_expected="$3"   # "null" for Review Required (legacy default applied in /complete);
                              # "false" for Worktree By Default (boolean-compat for consumers).

  for val_expected in "true=true" "True=true" "TRUE=true" "yes=true" "Yes=true" "y=true" "1=true" "on=true" "false=false" "False=false" "0=false" "no=false" "garbage=false"; do
    val="${val_expected%=*}"
    expected="${val_expected#*=}"
    cat > "$TMPDIR/project_state.md" <<EOF
# Test
**$field_human:** $val
EOF
    actual=$(bash "$READER" "$TMPDIR" 2>/dev/null | jq -r "$field_jq")
    if [ "$actual" = "$expected" ]; then
      pass_check "$field_human=$val → $expected"
    else
      fail_check "$field_human=$val returned '$actual' (expected '$expected')"
    fi
  done

  cat > "$TMPDIR/project_state.md" <<EOF
# Test
**$field_human:**
EOF
  actual=$(bash "$READER" "$TMPDIR" 2>/dev/null | jq -r "$field_jq")
  if [ "$actual" = "$empty_expected" ]; then
    pass_check "$field_human=(empty) → $empty_expected"
  else
    fail_check "$field_human=(empty) returned '$actual' (expected '$empty_expected')"
  fi
}

# Review Required: absent → null (legacy default applied downstream in /complete)
test_bool_variants "Review Required" ".reviewRequired" "null"
# Worktree By Default: absent → false (boolean-compat per v3.16.0 contract)
test_bool_variants "Worktree By Default" ".worktreeByDefault" "false"

# === Test 3: RCE regression ===
RCE_MARKER=/tmp/.psr-spec-RCE-MARKER
rm -f "$RCE_MARKER"

cat > "$TMPDIR/project_state.md" <<EOF
# Test
**Code path:** \$(touch $RCE_MARKER)
EOF
bash "$READER" "$TMPDIR" >/dev/null 2>&1 || true

if [ -f "$RCE_MARKER" ]; then
  fail_check "RCE smoke FAILED — Code path command-substitution executed"
  rm -f "$RCE_MARKER"
else
  pass_check "RCE smoke passed — adversarial Code path NOT executed"
fi

# Literal-byte: no eval anywhere in script
EVAL_COUNT=$(grep -cE '^[[:space:]]*eval[[:space:]]' "$READER" 2>/dev/null || true)
EVAL_COUNT=${EVAL_COUNT:-0}
if [ "$EVAL_COUNT" -eq 0 ] 2>/dev/null; then
  pass_check "no eval in script (literal-byte check)"
else
  fail_check "eval present in script ($EVAL_COUNT instances) — RCE regression"
fi

# === Test 4: Visual Review field (v4.11.0+) ===

vr_check() {
  local label="$1" line="$2" filter="$3" expected="$4"
  printf '# Test\n%s\n' "$line" > "$TMPDIR/project_state.md"
  local actual
  actual=$(bash "$READER" "$TMPDIR" 2>/dev/null | jq -c "$filter")
  if [ "$actual" = "$expected" ]; then
    pass_check "$label ($filter = $expected)"
  else
    fail_check "$label — $filter returned '$actual' (expected '$expected')"
  fi
}

# enabled + path
vr_check "VR enabled" "**Visual Review:** enabled .visual-review/registry.yml" \
  '.visualReview' '{"enabled":true,"registryPath":".visual-review/registry.yml"}'
# disabled + path
vr_check "VR disabled" "**Visual Review:** disabled .visual-review/registry.yml" \
  '.visualReview.enabled' 'false'
# case-insensitive header
vr_check "VR header lowercase" "**visual review:** enabled .visual-review/registry.yml" \
  '.visualReview.enabled' 'true'
# absent → null
printf '# Test\n' > "$TMPDIR/project_state.md"
if [ "$(bash "$READER" "$TMPDIR" 2>/dev/null | jq -c '.visualReview')" = "null" ]; then
  pass_check "VR absent → visualReview: null"
else
  fail_check "VR absent did not yield null"
fi
# bad state → warning + enabled:false
vr_check "VR bad state → enabled false" "**Visual Review:** bogus .visual-review/registry.yml" \
  '.visualReview.enabled' 'false'
out=$(bash "$READER" "$TMPDIR" 2>/dev/null)  # last write was the bad-state file
if echo "$out" | jq -e '.warnings[] | select(.code == "visual_review_bad_state")' >/dev/null; then
  pass_check "VR bad state → visual_review_bad_state warning"
else
  fail_check "VR bad state did not emit visual_review_bad_state warning"
fi
# no path → warning + registryPath null
printf '# Test\n**Visual Review:** enabled\n' > "$TMPDIR/project_state.md"
out=$(bash "$READER" "$TMPDIR" 2>/dev/null)
if [ "$(echo "$out" | jq -c '.visualReview.registryPath')" = "null" ] \
   && echo "$out" | jq -e '.warnings[] | select(.code == "visual_review_no_path")' >/dev/null; then
  pass_check "VR no path → registryPath null + visual_review_no_path warning"
else
  fail_check "VR no path handling — got: $(echo "$out" | jq -c '.visualReview, .warnings')"
fi
# path escape → warning + visualReview null
printf '# Test\n**Visual Review:** enabled ../../../../etc/passwd\n' > "$TMPDIR/project_state.md"
out=$(bash "$READER" "$TMPDIR" 2>/dev/null)
if [ "$(echo "$out" | jq -c '.visualReview')" = "null" ] \
   && echo "$out" | jq -e '.warnings[] | select(.code == "visual_review_path_escape")' >/dev/null; then
  pass_check "VR path escape → visualReview null + visual_review_path_escape warning"
else
  fail_check "VR path escape handling — got: $(echo "$out" | jq -c '.visualReview, .warnings')"
fi
# absolute path → rejected (F-04 regression — would otherwise survive the prefix guard)
printf '# Test\n**Visual Review:** enabled /etc/passwd\n' > "$TMPDIR/project_state.md"
out=$(bash "$READER" "$TMPDIR" 2>/dev/null)
if [ "$(echo "$out" | jq -c '.visualReview')" = "null" ] \
   && echo "$out" | jq -e '.warnings[] | select(.code == "visual_review_path_escape")' >/dev/null; then
  pass_check "VR absolute path → visualReview null + visual_review_path_escape warning"
else
  fail_check "VR absolute path handling — got: $(echo "$out" | jq -c '.visualReview, .warnings')"
fi
# '.' path → rejected (F-10 regression — resolves to the project folder itself)
printf '# Test\n**Visual Review:** enabled .\n' > "$TMPDIR/project_state.md"
out=$(bash "$READER" "$TMPDIR" 2>/dev/null)
if [ "$(echo "$out" | jq -c '.visualReview')" = "null" ] \
   && echo "$out" | jq -e '.warnings[] | select(.code == "visual_review_path_escape")' >/dev/null; then
  pass_check "VR '.' path → visualReview null + visual_review_path_escape warning"
else
  fail_check "VR '.' path handling — got: $(echo "$out" | jq -c '.visualReview, .warnings')"
fi

# === codeMap (v5.26.0+) ================================================================
# The load-bearing distinction: an ABSENT line means "no answer recorded, the map
# conversation may run"; `(none)` means "the user said no, never ask again". Collapsing
# them re-asks a question the user already answered, on every single task.
printf '# Test\n**Code path:** /tmp\n' > "$TMPDIR/project_state.md"
[ "$(bash "$READER" "$TMPDIR" | jq -r '.codeMap')" = "null" ] \
  && pass_check "codeMap: absent line parses to null (the map conversation may run)" \
  || fail_check "codeMap: an absent Code Map line should parse to null"

printf '# Test\n**Code path:** /tmp\n**Code Map:** (none)\n' > "$TMPDIR/project_state.md"
[ "$(bash "$READER" "$TMPDIR" | jq -r '.codeMap.declined')" = "true" ] \
  && pass_check "codeMap: (none) records an explicit decline, so it is never re-asked" \
  || fail_check "codeMap: (none) should parse to declined:true, distinct from absent"

printf '# Test\n**Code Map:** graphify-out/graph.json\n' > "$TMPDIR/project_state.md"
[ "$(bash "$READER" "$TMPDIR" | jq -r '.codeMap.path')" = "graphify-out/graph.json" ] \
  && pass_check "codeMap: a relative path is recorded" \
  || fail_check "codeMap: relative path was not recorded"
[ "$(bash "$READER" "$TMPDIR" | jq -r '.codeMap.declined')" = "false" ] \
  && pass_check "codeMap: a recorded path is not a decline" \
  || fail_check "codeMap: declined should be false when a path is set"

# Containment: this value steers where the internal prior-art search reads, so an escaping
# path is dropped with a warning rather than returned. Mirrors the visual-review registry.
for bad in "../../etc/passwd" "/etc/passwd" ".."; do
  printf '# Test\n**Code Map:** %s\n' "$bad" > "$TMPDIR/project_state.md"
  CM_OUT_T="$(bash "$READER" "$TMPDIR")"
  [ "$(jq -r '.codeMap' <<<"$CM_OUT_T")" = "null" ] \
    && pass_check "codeMap: escaping path '$bad' dropped" \
    || fail_check "codeMap: escaping path '$bad' was accepted"
  jq -e '.warnings | any(.code == "code_map_path_escape")' >/dev/null <<<"$CM_OUT_T" \
    && pass_check "codeMap: escape '$bad' warned rather than dropped silently" \
    || fail_check "codeMap: escaping path '$bad' was dropped with no warning"
done


if [ "$FAIL" -ne 0 ]; then
  printf '\nproject-state-read.sh parsing invariants violated.\n' >&2
  exit 1
fi

# === Process Recipes: the hand-written variant must parse ======================================
# The kernel writes `→ source=x`. A model composing the block by hand writes
# `→ `name` (source: x, verified: true, sha: …) — recorded <date>`. Observed on a real project: two
# recorded recipes came back with a null source and two warnings, so every phase re-resolved from
# scratch while the record sat there looking complete. Both forms must parse.
PR_DIR="$(mktemp -d)"; mkdir -p "$PR_DIR/p"
cat > "$PR_DIR/p/project_state.md" <<'PRMD'
# Test

**Code path:** /tmp

**Process Recipes:**
- research × drupal → `some_recipe` (source: dev-guides, verified: true, sha: 290c6081) — recorded 2026-08-14
- e2e-setup/nextjs/playwright → source=local
- design/drupal/x → (source: research)
PRMD
PR_OUT="$("$READER" "$PR_DIR/p" 2>/dev/null)"
[ "$(printf '%s' "$PR_OUT" | jq -r '.processRecipes[0].source')" = "dev-guides" ] \
  && pass_check "hand-written '(source: x, ...)' parses" \
  || fail_check "hand-written '(source: x, ...)' must parse, got null"
[ "$(printf '%s' "$PR_OUT" | jq -r '.processRecipes[1].source')" = "local" ] \
  && pass_check "kernel-written 'source=x' still parses" \
  || fail_check "kernel-written 'source=x' regressed"
[ "$(printf '%s' "$PR_OUT" | jq -r '.processRecipes[2].source')" = "research" ] \
  && pass_check "parenthesised '(source: x)' parses" \
  || fail_check "parenthesised '(source: x)' must parse"
[ "$(printf '%s' "$PR_OUT" | jq -r '[.warnings[].code] | index("process_recipe_bad_source") // "none"')" = "none" ] \
  && pass_check "a parsed source raises no bad-source warning" \
  || fail_check "a source that parses must not warn"
rm -rf "$PR_DIR"

if [ "$FAIL" -ne 0 ]; then
  printf '\nSome invariants FAILED for scripts/project-state-read.sh.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for scripts/project-state-read.sh.\n'
exit 0

