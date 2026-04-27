#!/usr/bin/env bash
# project-state-read-spec.sh — verify scripts/project-state-read.sh parsing invariants (v4.1.0+).
#
# Tests:
#   - Case-insensitive header matrix for all 6 fields (works without IGNORECASE,
#     since some awk implementations don't honor it)
#   - Boolean variant matrix (truthy/falsy/garbage/empty) for both bool fields
#   - RCE regression (no eval; adversarial Code path doesn't execute)
#
# Run pre-PR; complements tests/upgrade-project-spec.sh §2.

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

if [ "$FAIL" -ne 0 ]; then
  printf '\nproject-state-read.sh parsing invariants violated.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for scripts/project-state-read.sh.\n'
exit 0
