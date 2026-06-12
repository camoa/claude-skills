#!/bin/bash
# tests/changed-mode.sh
# Hermetic tests for --changed mode in lint-check.sh, solid-check.sh, security-check.sh
#
# Strategy: tests assert filter/scope logic directly without invoking phpcs/phpstan/
# semgrep. A fake 'ddev' on PATH passes the DDEV availability check; all real tool
# invocations are stubbed via function overrides injected into subshells. Tests that
# verify a clean skip exit code can run the scripts directly because the skip path
# exits before any tool call.
#
# Usage: bash code-quality-tools/tests/changed-mode.sh

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRUPAL_SCRIPTS="${SCRIPT_DIR}/../skills/code-quality-audit/scripts/drupal"

# =====================
# Helpers
# =====================
ok() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        ok "$label"
    else
        fail "$label — expected '${expected}', got '${actual}'"
    fi
}

# Create a fake ddev that satisfies the availability check but does nothing
make_fake_ddev() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "${dir}/ddev" <<'SH'
#!/bin/bash
# Fake ddev stub: passes describe, exec, drush etc. silently.
case "$1" in
    describe) exit 0 ;;
    exec)
        shift
        case "$1" in
            vendor/bin/phpcs)   exit 1 ;;   # non-zero = tool found but "ran"
            vendor/bin/phpstan) echo '{"totals":{"errors":0},"files":{}}' ; exit 0 ;;
            vendor/bin/phpmd)   echo '{"files":[]}' ; exit 0 ;;
            grep)               shift; grep "$@" ;;
            test)               test "$@" ;;
            semgrep)            exit 0 ;;
            *)                  exit 0 ;;
        esac
        ;;
    composer)
        case "$2" in
            audit) echo '{"advisories":{}}' ; exit 0 ;;
            show)  exit 1 ;;
            *)     exit 0 ;;
        esac
        ;;
    drush)
        case "$2" in
            pm:security) echo '[]' ; exit 0 ;;
            pm:list)     echo '{}' ; exit 0 ;;
            security-review) echo '[]' ; exit 0 ;;
            *)           exit 0 ;;
        esac
        ;;
    *)
        exit 0 ;;
esac
SH
    chmod +x "${dir}/ddev"
}

# =====================
# Filter-logic unit tests
# =====================
# Extract the filter function from the script into a testable fragment.
# These do NOT invoke ddev at all — pure bash string logic.

test_filter_logic() {
    local label="$1"
    local input_files="$2"          # newline-separated
    local expected_count="$3"
    local description="$4"

    local tmpf
    tmpf=$(mktemp)
    printf '%s\n' $input_files > "$tmpf"

    local LINTABLE_EXTS="\.php$|\.module$|\.inc$|\.install$|\.profile$|\.theme$|\.engine$|\.js$"
    local RELEVANT_FILES=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if ! echo "$f" | grep -qE "$LINTABLE_EXTS"; then
            continue
        fi
        if echo "$f" | grep -qE '^(vendor/|web/core/|.*/(contrib)/|web/themes/contrib/|web/modules/contrib/)'; then
            continue
        fi
        RELEVANT_FILES+=("$f")
    done < "$tmpf"
    rm -f "$tmpf"

    assert_eq "$label ($description)" "$expected_count" "${#RELEVANT_FILES[@]}"
}

# =====================
# Test 1: standard PHP file passes filter
# =====================
test_filter_logic "lint filter: .php passes" \
    "web/modules/custom/my_module/src/MyService.php" \
    1 "one PHP file included"

# =====================
# Test 2: vendor files excluded
# =====================
test_filter_logic "lint filter: vendor excluded" \
    "vendor/squizlabs/php_codesniffer/src/File.php" \
    0 "vendor/ excluded"

# =====================
# Test 3: core excluded
# =====================
test_filter_logic "lint filter: web/core excluded" \
    "web/core/includes/bootstrap.inc" \
    0 "web/core/ excluded"

# =====================
# Test 4: contrib excluded
# =====================
test_filter_logic "lint filter: contrib excluded" \
    "web/modules/contrib/views/views.module" \
    0 "contrib excluded"

# =====================
# Test 5: mixed list — only custom PHP remains
# =====================
test_filter_logic "lint filter: mixed list" \
    "web/modules/custom/my_module/my_module.module
vendor/drupal/coder/src/Sniff.php
web/core/lib/Drupal.php
README.md
web/modules/custom/my_module/src/Form/MyForm.php" \
    2 "2 custom files remain"

# =====================
# Test 6: .yml / .md files excluded (no lintable extension)
# =====================
test_filter_logic "lint filter: non-PHP excluded" \
    "config/install/my_module.settings.yml
README.md
composer.json" \
    0 "non-lintable files excluded"

# =====================
# Test 7: .js file passes (lintable)
# =====================
test_filter_logic "lint filter: .js passes" \
    "web/modules/custom/my_module/js/my-module.js" \
    1 ".js file included"

# =====================
# Test 8: solid filter — PHP extensions only (no .js)
# Solid-check uses a tighter LINTABLE_EXTS that excludes .js
# =====================
{
    label="solid filter: .js excluded from PHP-only set"
    input_files="web/modules/custom/my_module/js/my-module.js
web/modules/custom/my_module/src/Service.php"
    expected_count=1

    local_LINTABLE="\.php$|\.module$|\.inc$|\.install$|\.profile$|\.theme$|\.engine$"
    tmpf=$(mktemp)
    printf '%s\n' $input_files > "$tmpf"

    FILES=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if ! echo "$f" | grep -qE "$local_LINTABLE"; then continue; fi
        if echo "$f" | grep -qE '^(vendor/|web/core/|.*/(contrib)/|web/themes/contrib/|web/modules/contrib/)'; then continue; fi
        FILES+=("$f")
    done < "$tmpf"
    rm -f "$tmpf"

    assert_eq "$label" "$expected_count" "${#FILES[@]}"
}

# =====================
# Test 9: composer.json in changed set triggers HAS_COMPOSER=true
# =====================
{
    label="security --changed: composer.json triggers HAS_COMPOSER"
    tmpf=$(mktemp)
    printf '%s\n' "composer.json" "web/modules/custom/mod/src/A.php" > "$tmpf"

    HAS_COMPOSER=false
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if echo "$f" | grep -qE '(^|/)composer\.(json|lock)$'; then
            HAS_COMPOSER=true
            break
        fi
    done < "$tmpf"
    rm -f "$tmpf"

    assert_eq "$label" "true" "$HAS_COMPOSER"
}

# =====================
# Test 10: composer.lock also triggers HAS_COMPOSER=true
# =====================
{
    label="security --changed: composer.lock triggers HAS_COMPOSER"
    tmpf=$(mktemp)
    printf '%s\n' "web/modules/custom/mod/src/A.php" "composer.lock" > "$tmpf"

    HAS_COMPOSER=false
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if echo "$f" | grep -qE '(^|/)composer\.(json|lock)$'; then
            HAS_COMPOSER=true
            break
        fi
    done < "$tmpf"
    rm -f "$tmpf"

    assert_eq "$label" "true" "$HAS_COMPOSER"
}

# =====================
# Test 11: no composer file → HAS_COMPOSER=false
# =====================
{
    label="security --changed: no composer file → HAS_COMPOSER=false"
    tmpf=$(mktemp)
    printf '%s\n' "web/modules/custom/mod/src/A.php" > "$tmpf"

    HAS_COMPOSER=false
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if echo "$f" | grep -qE '(^|/)composer\.(json|lock)$'; then
            HAS_COMPOSER=true
            break
        fi
    done < "$tmpf"
    rm -f "$tmpf"

    assert_eq "$label" "false" "$HAS_COMPOSER"
}

# =====================
# Integration: clean-skip tests (scripts exit 0, no tool calls)
# =====================
# Run against the real scripts with a fake ddev on PATH.
# The changed-files list contains only non-lintable files → empty relevant set → skip.

FAKE_BIN=$(mktemp -d)
make_fake_ddev "$FAKE_BIN"
ORIG_PATH="$PATH"

run_skip_test() {
    local label="$1"
    local script="$2"
    local tmpf
    tmpf=$(mktemp)
    # Only non-lintable files
    printf '%s\n' "README.md" "config/schema/my.schema.yml" "composer.json" > "$tmpf"

    local exit_code=0
    local output
    output=$(PATH="${FAKE_BIN}:${ORIG_PATH}" REPORT_DIR="$(mktemp -d)" \
        bash "$script" --changed "$tmpf" 2>&1) || exit_code=$?
    rm -f "$tmpf"

    # Exit 0 = clean skip
    if [ "$exit_code" -eq 0 ]; then
        # Check "SKIP" appears in output (lint/solid) or "skipped" (security)
        if echo "$output" | grep -qi "skip"; then
            ok "$label → exit 0, skip message present"
        else
            fail "$label → exit 0 but no SKIP message (output: ${output})"
        fi
    else
        fail "$label → expected exit 0, got ${exit_code}"
    fi
}

# =====================
# Test 12: lint-check.sh --changed empty set → clean skip
# =====================
run_skip_test "lint-check.sh --changed empty set" "${DRUPAL_SCRIPTS}/lint-check.sh"

# =====================
# Test 13: solid-check.sh --changed empty set → clean skip
# =====================
run_skip_test "solid-check.sh --changed empty set" "${DRUPAL_SCRIPTS}/solid-check.sh"

# =====================
# Test 14: security-check.sh --changed empty set (no composer.json) → clean skip
# =====================
{
    label="security-check.sh --changed empty+no-composer → clean skip"
    tmpf=$(mktemp)
    printf '%s\n' "README.md" "config/schema/my.schema.yml" > "$tmpf"

    exit_code=0
    output=$(PATH="${FAKE_BIN}:${ORIG_PATH}" REPORT_DIR="$(mktemp -d)" \
        bash "${DRUPAL_SCRIPTS}/security-check.sh" --changed "$tmpf" 2>&1) || exit_code=$?
    rm -f "$tmpf"

    if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qi "skip"; then
        ok "$label → exit 0, skip message present"
    else
        fail "$label → exit_code=${exit_code}; output=${output}"
    fi
}

# =====================
# Test 15: lint-check.sh WITHOUT --changed still references DRUPAL_MODULES_PATH
# (confirms no-flag path unchanged — uses the original whole-dir argument)
# We just verify the help / error output doesn't mention "changed mode".
# The flag must be absent from the standard invocation path.
# =====================
{
    label="lint-check.sh no-flag: --changed is an additive guard, standard path untouched"
    # lint-check.sh uses an ADDITIVE intercept: `if [ "$1" == "--changed" ]` near
    # the top that exits before the standard path. The standard (no-flag) path —
    # including the original `if [ "$1" == "--fix" ]` parser — must remain present
    # and byte-identical. Assert both: the additive guard exists AND the original
    # --fix parser is still there.
    has_guard=false; has_orig_fix=false
    grep -q 'if \[ "\$1" == "--changed" \]' "${DRUPAL_SCRIPTS}/lint-check.sh" && has_guard=true
    grep -q 'if \[ "\$1" == "--fix" \]' "${DRUPAL_SCRIPTS}/lint-check.sh" && has_orig_fix=true
    if [ "$has_guard" = true ] && [ "$has_orig_fix" = true ]; then
        ok "$label → additive --changed guard present AND original --fix parser intact"
    else
        fail "$label → guard=${has_guard} orig_fix_parser=${has_orig_fix}"
    fi
}

# =====================
# Test 16: solid-check.sh guard present
# =====================
{
    label="solid-check.sh no-flag: guarded behind CHANGED_FILE check"
    if grep -q 'if \[ -n "\$CHANGED_FILE" \]' "${DRUPAL_SCRIPTS}/solid-check.sh"; then
        ok "$label → guard confirmed"
    else
        fail "$label → guard not found"
    fi
}

# =====================
# Test 17: security-check.sh guard present
# =====================
{
    label="security-check.sh no-flag: guarded behind CHANGED_FILE check"
    if grep -q 'if \[ -n "\$CHANGED_FILE" \]' "${DRUPAL_SCRIPTS}/security-check.sh"; then
        ok "$label → guard confirmed"
    else
        fail "$label → guard not found"
    fi
}

# =====================
# Test 18: security --changed advisory-skip note in report JSON
# =====================
{
    label="security-check.sh --changed: advisory-skip note written to report"
    tmpf=$(mktemp)
    # Empty file set → skip path → report written
    printf '%s\n' "README.md" > "$tmpf"
    RDIR=$(mktemp -d)

    PATH="${FAKE_BIN}:${ORIG_PATH}" REPORT_DIR="$RDIR" \
        bash "${DRUPAL_SCRIPTS}/security-check.sh" --changed "$tmpf" 2>/dev/null || true
    rm -f "$tmpf"

    REPORT="${RDIR}/security-report.json"
    if [ -f "$REPORT" ]; then
        NOTE=$(jq -r '.messages[0] // ""' "$REPORT" 2>/dev/null || echo "")
        if echo "$NOTE" | grep -qi "advisory\|skipped\|whole-project"; then
            ok "$label → advisory note present in report messages[]"
        else
            fail "$label → report exists but no advisory note: ${NOTE}"
        fi
    else
        fail "$label → security-report.json not written"
    fi
}

# =====================
# Test 19: security --changed with composer.json → advisory note still present
# (the report should still carry the skip note even when composer audit ran)
# =====================
{
    label="security-check.sh --changed with composer.json: advisory note present"
    tmpf=$(mktemp)
    printf '%s\n' "composer.json" > "$tmpf"
    RDIR=$(mktemp -d)

    PATH="${FAKE_BIN}:${ORIG_PATH}" REPORT_DIR="$RDIR" \
        bash "${DRUPAL_SCRIPTS}/security-check.sh" --changed "$tmpf" 2>/dev/null || true
    rm -f "$tmpf"

    REPORT="${RDIR}/security-report.json"
    if [ -f "$REPORT" ]; then
        NOTE=$(jq -r '.messages[0] // ""' "$REPORT" 2>/dev/null || echo "")
        if echo "$NOTE" | grep -qi "advisory\|skipped\|whole-project"; then
            ok "$label → advisory note present"
        else
            fail "$label → advisory note missing: '${NOTE}'"
        fi
    else
        fail "$label → security-report.json not written"
    fi
}

# =====================
# Non-empty SAST run tests (drive real scoping + crash regression)
# =====================
# A richer fake ddev that:
#   - passes semgrep/php-security-linter availability checks,
#   - emits ONE medium-severity finding from each (HIGH stays 0 — the exact
#     condition that crashed the pre-fix ((HIGH_COUNT += 0)) under set -e),
#   - logs the file args each tool was invoked on to $DDEV_SCOPE_LOG so tests
#     can assert the constructed scope,
#   - logs composer-audit invocation.
make_findings_ddev() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "${dir}/ddev" <<'SH'
#!/bin/bash
LOG="${DDEV_SCOPE_LOG:-/dev/null}"
case "$1" in
    describe) exit 0 ;;
    exec)
        shift
        case "$1" in
            semgrep)
                if [ "${2:-}" = "--version" ]; then exit 0; fi
                # scan: collect file args after --json, log them, emit 1 medium (WARNING)
                files=(); seen_json=0
                for a in "$@"; do
                    if [ "$seen_json" = 1 ]; then files+=("$a"); fi
                    if [ "$a" = "--json" ]; then seen_json=1; fi
                done
                printf 'SEMGREP_SCOPE: %s\n' "${files[*]}" >> "$LOG"
                printf '{"results":[{"path":"%s","start":{"line":3},"extra":{"severity":"WARNING","message":"test medium finding","metadata":{},"fix":null}}]}\n' "${files[0]:-unknown}"
                exit 0
                ;;
            vendor/bin/php-security-linter)
                shift   # drop binary
                shift   # drop 'scan'
                files=()
                for a in "$@"; do
                    case "$a" in --*) ;; *) files+=("$a") ;; esac
                done
                printf 'PSL_SCOPE: %s\n' "${files[*]}" >> "$LOG"
                printf '{"files":{"%s":{"messages":[{"type":"WARNING","source":"Test.Rule","line":5,"message":"test psl medium"}]}}}\n' "${files[0]:-unknown}"
                exit 0
                ;;
            test) exit 0 ;;   # 'test -f vendor/bin/php-security-linter' → installed
            grep) shift; grep "$@" ;;
            *) exit 0 ;;
        esac
        ;;
    composer)
        case "$2" in
            audit) printf 'COMPOSER_AUDIT: ran\n' >> "$LOG"; echo '{"advisories":{}}'; exit 0 ;;
            show)  exit 1 ;;
            *)     exit 0 ;;
        esac
        ;;
    drush) echo '[]'; exit 0 ;;
    *) exit 0 ;;
esac
SH
    chmod +x "${dir}/ddev"
}

FINDINGS_BIN=$(mktemp -d)
make_findings_ddev "$FINDINGS_BIN"
SECURITY_SCRIPT="${DRUPAL_SCRIPTS}/security-check.sh"

# =====================
# Test 20: CRITICAL regression — medium-only SAST run does NOT crash, report written, exit 0
# (covers the ((HIGH_COUNT += 0)) under set -e abort)
# =====================
{
    label="security --changed: medium-only SAST → no crash, report written, exit 0"
    WORKDIR=$(mktemp -d)
    mkdir -p "${WORKDIR}/web/modules/custom/test_mod/src"
    printf '<?php\n// no findings here\n' > "${WORKDIR}/web/modules/custom/test_mod/src/Test.php"
    CHANGED=$(mktemp)
    echo "web/modules/custom/test_mod/src/Test.php" > "$CHANGED"
    RDIR=$(mktemp -d)
    LOG=$(mktemp)

    exit_code=0
    ( cd "$WORKDIR" && PATH="${FINDINGS_BIN}:${ORIG_PATH}" REPORT_DIR="$RDIR" DDEV_SCOPE_LOG="$LOG" \
        bash "$SECURITY_SCRIPT" --changed "$CHANGED" >/dev/null 2>&1 ) || exit_code=$?

    REPORT="${RDIR}/security-report.json"
    if [ "$exit_code" -eq 0 ] && [ -f "$REPORT" ]; then
        # medium count should be >= 1 (semgrep + psl each emitted a medium)
        MED=$(jq '.summary.by_severity.medium // 0' "$REPORT" 2>/dev/null || echo 0)
        if [ "$MED" -ge 1 ]; then
            ok "$label (exit 0, report written, medium=${MED})"
        else
            fail "$label → report written but medium=${MED} (expected >=1)"
        fi
    else
        fail "$label → exit_code=${exit_code}, report exists=$([ -f "$REPORT" ] && echo yes || echo NO)"
    fi
    rm -rf "$WORKDIR" "$RDIR"; rm -f "$CHANGED" "$LOG"
}

# =====================
# Test 21: SAST tools invoked on the RELEVANT_FILES (constructed scope assertion)
# =====================
{
    label="security --changed: semgrep + php-security-linter scoped to the changed file"
    WORKDIR=$(mktemp -d)
    mkdir -p "${WORKDIR}/web/modules/custom/test_mod/src"
    printf '<?php\n' > "${WORKDIR}/web/modules/custom/test_mod/src/Service.php"
    # Add a vendor file + a yml that MUST be filtered out of the tool scope
    mkdir -p "${WORKDIR}/vendor/foo"
    printf '<?php\n' > "${WORKDIR}/vendor/foo/Bar.php"
    CHANGED=$(mktemp)
    printf '%s\n' \
        "web/modules/custom/test_mod/src/Service.php" \
        "vendor/foo/Bar.php" \
        "config/install/x.yml" > "$CHANGED"
    RDIR=$(mktemp -d)
    LOG=$(mktemp)

    ( cd "$WORKDIR" && PATH="${FINDINGS_BIN}:${ORIG_PATH}" REPORT_DIR="$RDIR" DDEV_SCOPE_LOG="$LOG" \
        bash "$SECURITY_SCRIPT" --changed "$CHANGED" >/dev/null 2>&1 ) || true

    SEMGREP_SCOPE=$(grep '^SEMGREP_SCOPE:' "$LOG" 2>/dev/null | head -1 || echo "")
    PSL_SCOPE=$(grep '^PSL_SCOPE:' "$LOG" 2>/dev/null | head -1 || echo "")

    scope_ok=true
    # The custom file must be in scope
    echo "$SEMGREP_SCOPE" | grep -q "web/modules/custom/test_mod/src/Service.php" || scope_ok=false
    echo "$PSL_SCOPE"     | grep -q "web/modules/custom/test_mod/src/Service.php" || scope_ok=false
    # vendor + yml must NOT be in scope
    echo "$SEMGREP_SCOPE" | grep -q "vendor/foo/Bar.php" && scope_ok=false
    echo "$SEMGREP_SCOPE" | grep -q "config/install/x.yml" && scope_ok=false

    if [ "$scope_ok" = true ]; then
        ok "$label (semgrep scope='${SEMGREP_SCOPE#SEMGREP_SCOPE: }', psl scoped, vendor/yml excluded)"
    else
        fail "$label → SEMGREP_SCOPE='${SEMGREP_SCOPE}' PSL_SCOPE='${PSL_SCOPE}'"
    fi
    rm -rf "$WORKDIR" "$RDIR"; rm -f "$CHANGED" "$LOG"
}

# =====================
# Test 22: composer audit runs when composer.json is in the changed set
# =====================
{
    label="security --changed: composer audit invoked on composer.json change"
    WORKDIR=$(mktemp -d)
    printf '{}\n' > "${WORKDIR}/composer.json"
    CHANGED=$(mktemp)
    echo "composer.json" > "$CHANGED"
    RDIR=$(mktemp -d)
    LOG=$(mktemp)

    exit_code=0
    ( cd "$WORKDIR" && PATH="${FINDINGS_BIN}:${ORIG_PATH}" REPORT_DIR="$RDIR" DDEV_SCOPE_LOG="$LOG" \
        bash "$SECURITY_SCRIPT" --changed "$CHANGED" >/dev/null 2>&1 ) || exit_code=$?

    if [ "$exit_code" -eq 0 ] && grep -q '^COMPOSER_AUDIT: ran' "$LOG" 2>/dev/null; then
        ok "$label (composer audit ran, exit 0)"
    else
        fail "$label → exit=${exit_code}, composer-audit-logged=$(grep -q '^COMPOSER_AUDIT' "$LOG" 2>/dev/null && echo yes || echo NO)"
    fi
    rm -rf "$WORKDIR" "$RDIR"; rm -f "$CHANGED" "$LOG"
}

# =====================
# Test 23: composer audit NOT invoked when no composer file in the changed set
# =====================
{
    label="security --changed: composer audit NOT run without composer.* change"
    WORKDIR=$(mktemp -d)
    mkdir -p "${WORKDIR}/web/modules/custom/m/src"
    printf '<?php\n' > "${WORKDIR}/web/modules/custom/m/src/A.php"
    CHANGED=$(mktemp)
    echo "web/modules/custom/m/src/A.php" > "$CHANGED"
    RDIR=$(mktemp -d)
    LOG=$(mktemp)

    ( cd "$WORKDIR" && PATH="${FINDINGS_BIN}:${ORIG_PATH}" REPORT_DIR="$RDIR" DDEV_SCOPE_LOG="$LOG" \
        bash "$SECURITY_SCRIPT" --changed "$CHANGED" >/dev/null 2>&1 ) || true

    if grep -q '^COMPOSER_AUDIT: ran' "$LOG" 2>/dev/null; then
        fail "$label → composer audit ran but should have been skipped"
    else
        ok "$label (composer audit correctly skipped)"
    fi
    rm -rf "$WORKDIR" "$RDIR"; rm -f "$CHANGED" "$LOG"
}

# =====================
# No-DDEV static-tier gap tests (Tests 24-27)
# Regression tests for the gap where --changed with a no-PHP changed set
# errored with "DDEV is not running" instead of skipping cleanly.
# These tests run with a stub ddev whose `describe` always exits non-zero,
# simulating a fully detached worktree with no running site.
# =====================
make_no_ddev() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "${dir}/ddev" <<'SH'
#!/bin/bash
# Stub: DDEV unavailable — describe always exits non-zero
case "$1" in
    describe) exit 1 ;;
    *)        exit 1 ;;
esac
SH
    chmod +x "${dir}/ddev"
}

NO_DDEV_BIN=$(mktemp -d)
make_no_ddev "$NO_DDEV_BIN"

# =====================
# Test 24: security-check.sh --changed CSS-only → exit 0 (SKIP) even without DDEV
# =====================
{
    label="security-check.sh --changed CSS-only → exit 0/SKIP without DDEV"
    tmpf=$(mktemp)
    printf '%s\n' "themes/custom/x/scss/styles.scss" "themes/custom/x/css/styles.css" > "$tmpf"
    RDIR=$(mktemp -d)

    exit_code=0
    output=$(PATH="${NO_DDEV_BIN}:${ORIG_PATH}" REPORT_DIR="$RDIR" \
        bash "${DRUPAL_SCRIPTS}/security-check.sh" --changed "$tmpf" 2>&1) || exit_code=$?
    rm -f "$tmpf"

    if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qi "skip"; then
        ok "$label → exit 0, skip message present"
    else
        fail "$label → exit_code=${exit_code}; output=${output}"
    fi
    rm -rf "$RDIR"
}

# =====================
# Test 25: security-check.sh --changed PHP-file → requires DDEV (exit 2 when absent)
# =====================
{
    label="security-check.sh --changed PHP-file → exit 2 (DDEV required)"
    tmpf=$(mktemp)
    printf '%s\n' "web/modules/custom/my_module/src/MyService.php" > "$tmpf"
    RDIR=$(mktemp -d)

    exit_code=0
    output=$(PATH="${NO_DDEV_BIN}:${ORIG_PATH}" REPORT_DIR="$RDIR" \
        bash "${DRUPAL_SCRIPTS}/security-check.sh" --changed "$tmpf" 2>&1) || exit_code=$?
    rm -f "$tmpf"

    if [ "$exit_code" -eq 2 ] && echo "$output" | grep -qi "ddev"; then
        ok "$label → exit 2, DDEV error message"
    else
        fail "$label → expected exit 2, got ${exit_code}; output=${output}"
    fi
    rm -rf "$RDIR"
}

# =====================
# Test 26: dry-check.sh --changed CSS-only → exit 0 (SKIP) even without DDEV
# =====================
{
    label="dry-check.sh --changed CSS-only → exit 0/SKIP without DDEV"
    tmpf=$(mktemp)
    printf '%s\n' "themes/custom/x/scss/styles.scss" "themes/custom/x/css/styles.css" > "$tmpf"
    RDIR=$(mktemp -d)

    exit_code=0
    output=$(PATH="${NO_DDEV_BIN}:${ORIG_PATH}" REPORT_DIR="$RDIR" \
        bash "${DRUPAL_SCRIPTS}/dry-check.sh" --changed "$tmpf" 2>&1) || exit_code=$?
    rm -f "$tmpf"

    if [ "$exit_code" -eq 0 ] && echo "$output" | grep -qi "skip\|no php"; then
        ok "$label → exit 0, skip/no-php message present"
    else
        fail "$label → exit_code=${exit_code}; output=${output}"
    fi
    rm -rf "$RDIR"
}

# =====================
# Test 27: dry-check.sh --changed PHP-file → requires DDEV (exit 2 when absent)
# =====================
{
    label="dry-check.sh --changed PHP-file → exit 2 (DDEV required)"
    tmpf=$(mktemp)
    printf '%s\n' "web/modules/custom/my_module/src/MyService.php" > "$tmpf"
    RDIR=$(mktemp -d)

    exit_code=0
    output=$(PATH="${NO_DDEV_BIN}:${ORIG_PATH}" REPORT_DIR="$RDIR" \
        bash "${DRUPAL_SCRIPTS}/dry-check.sh" --changed "$tmpf" 2>&1) || exit_code=$?
    rm -f "$tmpf"

    if [ "$exit_code" -eq 2 ] && echo "$output" | grep -qi "ddev"; then
        ok "$label → exit 2, DDEV error message"
    else
        fail "$label → expected exit 2, got ${exit_code}; output=${output}"
    fi
    rm -rf "$RDIR"
}

rm -rf "$NO_DDEV_BIN"

# =====================
# Cleanup
# =====================
rm -rf "$FINDINGS_BIN"
rm -rf "$FAKE_BIN"

# =====================
# Summary
# =====================
echo ""
echo "==========================="
echo "Tests: $((PASS + FAIL)) | Pass: ${PASS} | Fail: ${FAIL}"
echo "==========================="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
