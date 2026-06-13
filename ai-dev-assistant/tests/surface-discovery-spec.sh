#!/usr/bin/env bash
# surface-discovery-spec.sh — verify scripts/surface-discovery.sh (v4.13.0, Task C).
#
# Covers: builtin home + admin surfaces, View config scan, exit-0-always,
# JSON shape, --drush-path none (no content-type rows without drush).
# Run pre-PR.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/surface-discovery.sh"
[ -f "$SCRIPT" ] || { printf 'FAIL: %s not found\n' "$SCRIPT" >&2; exit 1; }

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# === Test 1: empty codePath → home + 3 admin surfaces, exit 0 ===
CP="$TMPDIR/cp"; mkdir -p "$CP"
RC=0; OUT=$(bash "$SCRIPT" "$CP" --drush-path none) || RC=$?
if [ "$RC" -eq 0 ] \
   && echo "$OUT" | jq -e '.frontend[] | select(.id == "home" and .url == "/")' >/dev/null \
   && [ "$(echo "$OUT" | jq '.admin | length')" = "3" ]; then
  pass_check "empty codePath → home frontend + 3 admin surfaces, exit 0"
else
  fail_check "empty codePath — rc=$RC out=$OUT"
fi

# === Test 2: View page-display config scan ===
mkdir -p "$CP/config/sync"
cat > "$CP/config/sync/views.view.blog.yml" <<'EOF'
display:
  page_1:
    display_options:
      path: blog
EOF
OUT=$(bash "$SCRIPT" "$CP" --drush-path none)
if echo "$OUT" | jq -e '.frontend[] | select(.url == "/blog" and (.source | startswith("view:")))' >/dev/null; then
  pass_check "View config scan → /blog frontend surface"
else
  fail_check "View config scan — out=$OUT"
fi

# === Test 3: --drush-path none → no content-type surfaces ===
if ! echo "$OUT" | jq -e '.frontend[] | select(.source | startswith("content-type:"))' >/dev/null; then
  pass_check "--drush-path none → no content-type rows (drush disabled)"
else
  fail_check "--drush-path none still produced content-type rows — out=$OUT"
fi

# === Test 4: output JSON shape (frontend + admin keys) ===
if echo "$OUT" | jq -e 'has("frontend") and has("admin") and (.frontend | type == "array") and (.admin | type == "array")' >/dev/null; then
  pass_check "output has frontend[] + admin[]"
else
  fail_check "output shape — out=$OUT"
fi

# === Test 5: missing codePath → empty groups, exit 0 ===
RC=0; OUT=$(bash "$SCRIPT" "$TMPDIR/does-not-exist") || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -c '.frontend')" = "[]" ]; then
  pass_check "missing codePath → empty groups, exit 0"
else
  fail_check "missing codePath — rc=$RC out=$OUT"
fi

# === Test 6: surface ids are kebab-case ===
OUT=$(bash "$SCRIPT" "$CP" --drush-path none)
BAD=$(echo "$OUT" | jq -r '(.frontend + .admin)[].id' | grep -vE '^[a-z0-9][a-z0-9-]*$' || true)
if [ -z "$BAD" ]; then
  pass_check "all surface ids are kebab-case"
else
  fail_check "non-kebab surface ids: $BAD"
fi

# === Test 7 (regression, paper-test RT-3): --drush-path with shell ===
# metacharacters → rejected (empty groups, no command injection).
RC=0; OUT=$(bash "$SCRIPT" "$CP" --drush-path 'ddev drush; rm -rf ~') || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -c '.frontend')" = "[]" ] \
   && [ "$(echo "$OUT" | jq -c '.admin')" = "[]" ]; then
  pass_check "--drush-path with metacharacters → rejected, empty groups"
else
  fail_check "--drush-path injection guard — rc=$RC out=$OUT"
fi
# A clean drush path is still accepted (does not get rejected by the guard).
OUT=$(bash "$SCRIPT" "$CP" --drush-path 'ddev drush')
if echo "$OUT" | jq -e '.frontend[] | select(.id == "home")' >/dev/null; then
  pass_check "--drush-path 'ddev drush' (clean) accepted"
else
  fail_check "clean --drush-path wrongly rejected — out=$OUT"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nsurface-discovery.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/surface-discovery.sh.\n'
exit 0
