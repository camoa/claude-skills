#!/bin/bash
# install-verify.sh - assert that the toolchain that was just installed can actually fail.
# Part of code-quality-audit skill
#
# A SEPARATE PROCESS from cqt-install.sh, and that separation is the design rather than a
# file-layout preference. The boundary rule this task adopted says verification is a
# script and it is separate from execution, because a thing asking itself whether it
# worked verifies nothing.
#
#   install-verify.sh --config PATH [--json]
#   install-verify.sh --config -      reads the document from stdin, which is how the
#                                     shim verifies a config that never became a file
#
# Three checks. Each is a claim about the installed toolchain that is FALSE on a normal
# install today and that produces no error anywhere:
#
#   1. `phpcs -i` lists Drupal. drupal/coder is type: phpcodesniffer-standard - a rule
#      set, not a tool - registered by the dealerdirect Composer plugin. Without the
#      allow-plugins entry the plugin never activates, the standard is never registered,
#      and `phpcs --standard=Drupal,DrupalPractice` (five call sites in lint-check.sh,
#      plus grumphp.yml and two CI templates) has nothing to load.
#
#   2. extension-installer's GeneratedConfig.php names mglaman. The shipped phpstan.neon
#      carries no `includes:` block BY DESIGN, because extension-installer is supposed to
#      auto-register. When it did not activate there is nothing to fail: PHPStan starts,
#      loads zero Drupal rules, analyses Drupal as plain PHP, and exits 0. This check is
#      the only thing that can tell those two states apart.
#
#   3. A staged known violation drives the hook non-zero. This replaces
#      setup.md:220-222's `git commit --allow-empty -m "Test grumphp hook"`, which stages
#      no files; GrumPHP's pre-commit context is git-staged-files, so it inspected an
#      empty set and passed. A verification that cannot fail is this epic's thesis in one
#      line, and it lives in a script here rather than in prose because prose cannot exit
#      non-zero.
#
# A check that cannot APPLY reports `skipped` with a reason, never `passed`. Same
# three-state discipline check_version_drift() uses for `unchecked`, and for the same
# reason: a consumer has to be able to tell "we looked and it was fine" from "we never
# looked".
#
# The AGGREGATE honours that too, which is the part a consumer actually reads:
#
#   any check failed            -> status "fail",       exit 1
#   no check passed             -> status "unmeasured", exit 4
#   at least one passed, none failed -> status "pass",  exit 0
#
# `unmeasured` and 4 are the suite's existing words for this — path-resolve.sh's
# CQT_STATUS_UNMEASURED and CQT_EXIT_UNMEASURED — not a second vocabulary invented here.

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./report-dir.sh
. "${SCRIPT_DIR}/report-dir.sh"
cqt_report_dir_init
# Announced, like every other script in the suite. Section Q/R of false-clean-spec.sh
# drives every script that references REPORT_DIR and asserts it says where it resolved
# to; a script that resolves silently is one nobody can tell apart from a script that
# wrote into the audited repository.
cqt_announce_report_dir

# shellcheck source=./cqt-config.sh
. "${SCRIPT_DIR}/cqt-config.sh"

CONFIG_PATH=""
JSON_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --config)   CONFIG_PATH="${2-}"; shift 2 ;;
        --config=*) CONFIG_PATH="${1#--config=}"; shift ;;
        --json)     JSON_ONLY=1; shift ;;
        -h|--help)  sed -n '2,48p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf '%b[ERROR]%b unknown argument: %s\n' "$RED" "$NC" "$1" >&2; exit 2 ;;
    esac
done

[ -n "${CONFIG_PATH}" ] || {
    printf '%b[ERROR]%b --config is required\n' "$RED" "$NC" >&2
    exit 2
}

cqt_config_load "${CONFIG_PATH}" > /dev/null

# Every check records status, and a reason whenever the status is not `passed`. The
# reason is the part a person acts on; the status is the part full-audit.sh acts on.
CHECKS_JSON="{}"
FAILURES=0

record() {   # <key> <status: passed|failed|skipped> <reason>
    local key="$1" status="$2" reason="$3"
    CHECKS_JSON="$(jq -c --arg k "${key}" --arg s "${status}" --arg r "${reason}" '
        .[$k] = { status: $s, reason: $r, counted_as_pass: ($s == "passed") }
    ' <<< "${CHECKS_JSON}")"
    case "${status}" in
        passed)  say "%b[PASS]%b %s\n" "$GREEN" "$NC" "${key}" ;;
        failed)  say "%b[FAIL]%b %s: %s\n" "$RED" "$NC" "${key}" "${reason}"
                 FAILURES=$((FAILURES + 1)) ;;
        skipped) say "%b[SKIP]%b %s: %s\n" "$YELLOW" "$NC" "${key}" "${reason}" ;;
    esac
}

say() {
    [ "${JSON_ONLY}" -eq 1 ] && return 0
    # shellcheck disable=SC2059
    printf "$@"
}

# Where phpcs actually is. The same order solid-check.sh's resolve_analyzer uses, for the
# same reason: probing one location and dispatching to another is how a host-only tool
# came to be invoked inside a container where it does not exist.
PHPCS_CMD=()
resolve_phpcs() {
    if ddev exec test -f "vendor/bin/phpcs" > /dev/null 2>&1; then
        PHPCS_CMD=(ddev exec vendor/bin/phpcs); return 0
    fi
    if [ -x "vendor/bin/phpcs" ]; then
        PHPCS_CMD=(./vendor/bin/phpcs); return 0
    fi
    if command -v phpcs > /dev/null 2>&1; then
        PHPCS_CMD=(phpcs); return 0
    fi
    return 1
}

# ── check 1 ───────────────────────────────────────────────────────────────────
# The reason this reads the exit status and parses a LINE rather than grepping the blob:
# it used to do `out="$(phpcs -i 2>&1)"` and then `grep -q 'Drupal'` over merged streams.
# That discards the status entirely, so a phpcs exiting 255 was still read for content,
# and the pattern matches anywhere — including in the fatal's own stack trace. A real one,
# `PHP Fatal error ... in /home/dev/Sites/Drupal10/vendor/.../Runner.php`, was recorded
# {"status":"passed"} because the project path contains the word. The tool had not run and
# no standard was listed.
#
# So: a non-zero status is a failure on its own, and the match is against the standards
# phpcs actually names on its `The installed coding standards are ...` line, compared as
# whole tokens. A path can no longer answer for a registration.
check_phpcs_lists_drupal() {
    local out rc=0 line standards std
    if ! resolve_phpcs; then
        record "phpcs_lists_drupal" "skipped" \
            "phpcs is not installed anywhere this script can reach, so the standard's registration cannot be observed"
        return 0
    fi
    out="$("${PHPCS_CMD[@]}" -i 2>&1)" || rc=$?
    if [ "${rc}" -ne 0 ]; then
        record "phpcs_lists_drupal" "failed" \
            "phpcs -i exited ${rc}, so it did not run and no standard was listed. Whatever it printed is a diagnostic, not a standards list, and reading it for content is how a fatal whose stack trace names a path containing 'Drupal' came to be recorded as a pass. Output was: ${out}"
        return 0
    fi

    # phpcs prints one line: "The installed coding standards are A, B, C and D". Anchored
    # to that prefix, so no other line of output can supply the answer.
    line="$(printf '%s\n' "${out}" | sed -n 's/^The installed coding standards are //p' | head -1)"
    if [ -z "${line}" ]; then
        record "phpcs_lists_drupal" "failed" \
            "phpcs -i exited 0 but printed no 'The installed coding standards are' line, so there is no standards list to read and the registration cannot be confirmed. Output was: ${out}"
        return 0
    fi

    # Whole tokens, never a substring: "DrupalPractice" alone does not answer for
    # "Drupal", and neither does a path.
    standards="$(printf '%s' "${line}" | sed -e 's/[.[:space:]]*$//' -e 's/ and /,/g' -e 's/,/\n/g')"
    while IFS= read -r std; do
        std="$(printf '%s' "${std}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [ "${std}" = "Drupal" ]; then
            record "phpcs_lists_drupal" "passed" ""
            return 0
        fi
    done <<< "${standards}"

    record "phpcs_lists_drupal" "failed" \
        "phpcs -i does not list Drupal among its installed standards, so --standard=Drupal,DrupalPractice has nothing to load. drupal/coder is a rule set registered by dealerdirect/phpcodesniffer-composer-installer; without that plugin in config.allow-plugins it never activates, and nothing about that is reported as an error. It listed: ${line}"
}

# ── check 2 ───────────────────────────────────────────────────────────────────
check_extension_installer_registered() {
    local gen="vendor/phpstan/extension-installer/src/GeneratedConfig.php"
    local wanted="mglaman/phpstan-drupal"

    if ! cqt_config_doc | jq -e --arg n "${wanted}" '
            [.tools[]?.packages[]?.name] | index($n) != null' > /dev/null 2>&1; then
        record "phpstan_drupal_registered" "skipped" \
            "this config does not install ${wanted}, so there is nothing for extension-installer to have registered"
        return 0
    fi
    if [ ! -d vendor ]; then
        record "phpstan_drupal_registered" "skipped" \
            "there is no vendor/ tree, so no install has run here yet and the registration cannot be observed"
        return 0
    fi
    if [ ! -f "${gen}" ]; then
        record "phpstan_drupal_registered" "failed" \
            "${gen} does not exist, so ${wanted} is not registered with PHPStan. extension-installer never ran, and nothing about that is an error: PHPStan starts, loads zero Drupal rules, analyses Drupal as plain PHP and exits 0 — which reads as a clean tree. The usual cause is a missing config.allow-plugins entry for phpstan/extension-installer."
        return 0
    fi
    if grep -qF "${wanted}" "${gen}"; then
        record "phpstan_drupal_registered" "passed" ""
    else
        record "phpstan_drupal_registered" "failed" \
            "${gen} exists but does not name ${wanted}. The extension is installed and NOT registered, which is indistinguishable from a clean run: the shipped phpstan.neon carries no includes: block, so nothing errors."
    fi
}

# ── check 3 ───────────────────────────────────────────────────────────────────
#
# The violation is a FIXED LITERAL shipped in this script, never generated from config,
# because it is about to be written into somebody's repository and staged.
#
# The index is restored on every exit path, trap included. Leaving a staged file behind
# after a failed audit is a real harm, not a tidiness issue.
#
# The index is resolved through git rather than assumed at .git/index for the same reason
# the working-tree test is: in a linked worktree the index lives beside the worktree's own
# gitdir, and a literal path would restore the wrong file, or none.
CQT_VIOLATION_FILE=""
CQT_INDEX_BACKUP=""
CQT_INDEX_PATH=""
restore_index() {
    [ -n "${CQT_VIOLATION_FILE}" ] && rm -f "${CQT_VIOLATION_FILE}"
    if [ -n "${CQT_INDEX_BACKUP}" ] && [ -f "${CQT_INDEX_BACKUP}" ] && [ -n "${CQT_INDEX_PATH}" ]; then
        cp -f "${CQT_INDEX_BACKUP}" "${CQT_INDEX_PATH}" 2> /dev/null || true
        rm -f "${CQT_INDEX_BACKUP}"
    fi
    CQT_VIOLATION_FILE=""
    CQT_INDEX_BACKUP=""
    CQT_INDEX_PATH=""
}
trap restore_index EXIT INT TERM

check_hook_can_fail() {
    local enabled hook status
    enabled="$(cqt_config_get .git_hooks.enabled)"

    if [ "${enabled}" != "true" ]; then
        record "hook_can_fail" "skipped" \
            "git_hooks.enabled is false, so no hook was installed and there is nothing here that could fail"
        return 0
    fi
    # `git rev-parse`, not `[ -d .git ]`. In a linked worktree or a submodule, .git is a
    # FILE holding a `gitdir:` pointer, and hooks run there normally — so the directory
    # test recorded "this is not a git working tree" about a tree that plainly is one, and
    # silently disabled the one check that replaces setup.md's `git commit --allow-empty`.
    # This repository develops in worktrees, so the wrong branch was the reachable one.
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        record "hook_can_fail" "skipped" "this is not a git working tree, so no pre-commit hook can run"
        return 0
    fi
    # The hooks directory follows the same pointer. core.hooksPath moves it too, and
    # `--git-path hooks` is the one query that answers for every layout.
    hook="$(git rev-parse --git-path hooks 2> /dev/null)/pre-commit"
    if [ ! -x "${hook}" ]; then
        record "hook_can_fail" "failed" \
            "git_hooks.enabled is true but ${hook} is not present and executable, so the hook the config asked for is not installed"
        return 0
    fi

    CQT_INDEX_PATH="$(git rev-parse --git-path index 2> /dev/null)"
    CQT_INDEX_BACKUP="${CQT_INDEX_PATH}.cqt-verify-backup"
    cp -f "${CQT_INDEX_PATH}" "${CQT_INDEX_BACKUP}" 2> /dev/null || CQT_INDEX_BACKUP=""

    CQT_VIOLATION_FILE="./cqt-known-violation.php"
    cat > "${CQT_VIOLATION_FILE}" <<'VIOLATION'
<?php
// cqt-known-violation: written by install-verify.sh, staged, and removed again.
// Deliberately breaks the Drupal standard several ways at once: no file doc comment,
// a non lower_snake_case function name, spacing inside the parameter list, and a
// control structure with no braces on its own lines.
function Bad_NAME( $x ) { if($x){return 1;} return 0; }
VIOLATION

    git add -- "${CQT_VIOLATION_FILE}" > /dev/null 2>&1
    status=0
    "${hook}" > /dev/null 2>&1 || status=$?

    if [ "${status}" -ne 0 ]; then
        record "hook_can_fail" "passed" ""
    else
        record "hook_can_fail" "failed" \
            "the pre-commit hook exited 0 with a known Drupal-standard violation staged. A hook that passes this passes everything, which is the state setup.md's 'git commit --allow-empty' verification left behind: that command stages no files, and GrumPHP's git-staged-files context then inspects an empty set."
    fi

    restore_index
}

# ── run ───────────────────────────────────────────────────────────────────────
say '=== code-quality-tools: install verification ===\n\n'
check_phpcs_lists_drupal
check_extension_installer_registered
check_hook_can_fail

# ── the aggregate, which is the only part any consumer acts on ────────────────
#
# The per-check three-state discipline above is real, and the aggregate used to throw it
# away: `status` was `if failures == 0 then "pass" else "fail"`, so three skips became a
# pass. Executed on a project with nothing installed at all, this file wrote
# {"status":"pass","passed":0,"failed":0,"skipped":3}, printed "[OK] the installed
# toolchain can fail", and exited 0 — a claim about a toolchain it had not looked at, and
# the header two screens up says a consumer has to be able to tell those apart.
#
# The word and the exit code are NOT invented here. The gate_path_resolution sibling
# already settled both for exactly this state: status "unmeasured" (path-resolve.sh's
# CQT_STATUS_UNMEASURED) and exit 4 (CQT_EXIT_UNMEASURED), which full-audit.sh's
# gate_status_from_exit maps to "unmeasured" and which resolve_overall_status refuses to
# call a pass. Reusing them keeps one vocabulary; a second one here would mean two words
# for one condition and a reader who has to learn both.
PASSES="$(jq -r '[.[] | select(.status == "passed")] | length' <<< "${CHECKS_JSON}")"
SKIPS="$(jq -r '[.[] | select(.status == "skipped")] | length' <<< "${CHECKS_JSON}")"

# Precedence: a real failure outranks everything, then "nothing was measured", then pass.
# Zero passes with at least one skip is the unmeasured case — the run covered no ground.
AGG_STATUS="pass"
AGG_REASON=""
if [ "${FAILURES}" -ne 0 ]; then
    AGG_STATUS="fail"
    AGG_REASON="${FAILURES} check(s) failed"
elif [ "${PASSES}" -eq 0 ]; then
    AGG_STATUS="unmeasured"
    AGG_REASON="no check could be applied here (${SKIPS} skipped, 0 passed), so nothing about this toolchain was established. A zero-failure run that measured nothing is not a working install."
fi

mkdir -p "${REPORT_DIR}"
jq -n \
    --argjson checks "${CHECKS_JSON}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "${AGG_STATUS}" \
    --arg reason "${AGG_REASON}" \
    --argjson failures "${FAILURES}" '
    {
      status: $status,
      reason: $reason,
      timestamp: $ts,
      checks: $checks,
      findings: [ $checks | to_entries[] | select(.value.status != "passed")
                  | { check: .key, status: .value.status, reason: .value.reason } ],
      passed: ([ $checks[] | select(.status == "passed") ] | length),
      failed: $failures,
      skipped: ([ $checks[] | select(.status == "skipped") ] | length)
    }' > "${REPORT_DIR}/install-verify.json"

say '\n%s\n' "----"
case "${AGG_STATUS}" in
    fail)
        say '%b[FAIL]%b %s check(s) failed. See %s\n' "$RED" "$NC" "${FAILURES}" "${REPORT_DIR}/install-verify.json"
        exit 1
        ;;
    unmeasured)
        say '%b[UNMEASURED]%b %s See %s\n' "$YELLOW" "$NC" "${AGG_REASON}" "${REPORT_DIR}/install-verify.json"
        exit 4
        ;;
esac
say '%b[OK]%b the installed toolchain can fail. See %s\n' "$GREEN" "$NC" "${REPORT_DIR}/install-verify.json"
exit 0
