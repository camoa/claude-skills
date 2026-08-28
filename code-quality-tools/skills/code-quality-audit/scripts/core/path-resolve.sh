#!/bin/bash
# path-resolve.sh - where this project's custom code is, and what a gate does when that
# path is not there.
# Part of code-quality-audit skill
#
# SOURCEABLE, and that is the whole point of the file existing.
#
# Nine call sites across seven gates defaulted the modules path to a web/ layout literal
# instead of asking detect-environment.sh's resolver, so every docroot-layout (Acquia)
# project had each gate pointed at a directory that script had already ruled out. The
# obvious fix — have the gates source detect-environment.sh — is not available: that
# script is `set -e`, prints an environment-detection banner, sources report-dir.sh with
# its side effects, and assigns fourteen globals at load time, two of them PROJECT_TYPE
# and DRUPAL_MODULES_PATH, the exact names full-audit.sh owns. A `[ "${BASH_SOURCE[0]}" =
# "$0" ]` guard suppresses only `main`; everything above it still runs on source.
#
# So the resolution moved DOWN here instead, and this file obeys three rules a gate can
# rely on:
#
#   * it sources nothing;
#   * it runs no external command and executes no code at load time — only function and
#     constant definitions, so `. path-resolve.sh` works with an empty PATH;
#   * it sets no shell option and prints nothing. `set -e` in particular would change
#     what several gates do: lint-check.sh uses bare `jq ... || echo "0"` forms whose
#     behaviour depends on not having it.
#
# The [OK]/[WARN] announcements stay in detect-environment.sh, which is a user-facing
# command. A gate sourcing this library must not print an environment-detection banner,
# so the resolver here returns its findings in variables and says nothing.

# ── the suite's exit vocabulary ───────────────────────────────────────────────
#
# shellcheck disable=SC2034
# Everything this file defines is unused WITHIN this file — that is what a sourceable
# library is. The disable covers the constants and the two CQT_PATH_* result variables;
# without it every gate that gets git-added alongside it fails `make lint` for names it
# was written to publish. `make lint` keys its baseline on file and code, so silencing
# it here rather than in the baseline keeps the reason next to the code.
#
# 4, and deliberately not 3. Code 3 already means "the installed tree does not match
# composer.lock" in two places (detect-environment.sh:373 and full-audit.sh:146), so a
# gate leaving with 3 would hand a caller two meanings for one number.
#
# The exit code is the FALLBACK channel. The primary one is the `status` field in the
# gate's own JSON report: full-audit.sh already prefers the report over the exit code
# for two gates on the stated ground that an exit code "cannot express the difference",
# and CQT_STATUS_UNMEASURED is the word that travels there. Two gates (rector-fix.sh,
# tdd-workflow.sh) write no report at all, and for those the exit code is the only
# channel there is.
CQT_EXIT_PASS=0
CQT_EXIT_WARNING=1
CQT_EXIT_FAIL=2
CQT_EXIT_UNMEASURED=4

# The status word every gate writes into its report when it was asked to check a path
# it could not measure. Deliberately NOT "skipped": in this suite "skipped" already
# means "the tool is absent", which is a legitimate state of the machine. A path that is
# not there is a configuration fact about the project, and filing it under the same word
# would make two different findings indistinguishable to full-audit.sh.
CQT_STATUS_UNMEASURED="unmeasured"

# The paths the current process could not measure. Appended to by cqt_unmeasured, read
# by a gate when it builds paths_missing[] / tools_unmeasured[] for its report.
CQT_UNMEASURED_PATHS=()

# ── layout resolution ─────────────────────────────────────────────────────────

# The detected Drupal root, expressed relative to the project root.
#
# Moved verbatim from detect-environment.sh:142; its answers do not change. detect_drupal
# already works out where the web root is — docroot/ on an Acquia-layout project, web/ on
# a composer-template one — so the custom-code paths must be derived from THAT and not
# guessed independently, or every docroot-layout project is told to look in a web/ that
# does not exist.
#
# Relative on purpose: the gates treat these as project-root-relative paths
# (coverage-report.sh builds /var/www/html/${DRUPAL_MODULES_PATH} for the container, and
# the grep-based gates run from the project root), so the absolute DRUPAL_ROOT must never
# leak into them.
#
# PROJECT_ROOT defaults to $PWD rather than being required: detect-environment.sh always
# sets it, a gate sourcing this library generally does not, and both run from the project
# root. $PWD is a shell variable, so reading it is not running `pwd`.
cqt_drupal_root_prefix() {
    local rel="${DRUPAL_ROOT:-}"
    local project_root="${PROJECT_ROOT:-$PWD}"

    # Nothing detected to derive from — keep the historical default rather than
    # inventing a layout.
    if [ -z "${rel}" ]; then
        printf '%s' "web"
        return 0
    fi

    case "${rel}" in
        "${project_root}")   rel="" ;;
        "${project_root}"/*) rel="${rel#"${project_root}"/}" ;;
    esac

    # detect_drupal composes "${PROJECT_ROOT}/${path}" over a search list whose first
    # entry is ".", so a root-layout project arrives here as "." or "./web".
    while [ "${rel}" != "${rel#./}" ]; do
        rel="${rel#./}"
    done
    rel="${rel%/}"
    if [ "${rel}" = "." ]; then
        rel=""
    fi

    printf '%s' "${rel}"
}

# Find the Drupal root when nobody has told us where it is.
#
# The same search detect_drupal performs, minus the reporting: a gate needs the ANSWER,
# not the announcement. Only runs when DRUPAL_ROOT is empty, so under /audit — where
# full-audit.sh has already re-exported values detect-environment.sh resolved — it never
# runs at all and cannot disagree with what that script decided.
#
# `[ -f ... ]` is a shell builtin, so this probes the filesystem without spawning
# anything, which is what keeps the library usable inside every gate.
cqt_detect_drupal_root() {
    local path
    local project_root="${PROJECT_ROOT:-$PWD}"

    [ -z "${DRUPAL_ROOT:-}" ] || return 0

    for path in "." "drupal-app" "web" "docroot"; do
        if [ -f "${path}/web/core/lib/Drupal.php" ]; then
            DRUPAL_ROOT="${project_root}/${path}/web"
            return 0
        fi
        if [ -f "${path}/core/lib/Drupal.php" ]; then
            DRUPAL_ROOT="${project_root}/${path}"
            return 0
        fi
    done

    return 0
}

# Resolve one custom-code path (modules or themes) and export it.
#
# An explicit value always wins and is never second-guessed: the caller who exported it
# knows their layout better than this detection does, and silently substituting a
# different directory would scope every gate at something the caller did not ask for. It
# is still REPORTED as missing when it does not exist, because that is a typo worth
# seeing rather than a clean scan of nothing.
#
# The path is exported even when no directory was found, so environment.json always names
# what was actually looked for rather than going blank. An empty field is worse than a
# wrong one: it is what full-audit.sh re-exports to the gates, and a gate handed nothing
# used to fall back to its own layout default, silently undoing the resolution on exactly
# the layouts that needed it.
#
# Prints nothing. Sets, for the caller that wants to announce:
#   CQT_PATH_ORIGIN               explicit | derived | nonstandard, for THIS call
#   CQT_PATH_STATE                ok | missing, for THIS call
#   CQT_PATH_ORIGIN_<var_name>    the same origin, kept per variable
#
# The per-variable record is the one a gate reads, through cqt_path_origin. The two
# unsuffixed globals are overwritten by the next call, and cqt_resolve_drupal_paths
# makes two, so after it CQT_PATH_ORIGIN describes the themes path and nothing else.
#
# The existence test here is `-d`, matching what detect-environment.sh has always done
# when CHOOSING between candidates. Gates use cqt_scan_path_state instead, which tests
# -e, because a scope override is documented to be allowed to name a single file.
cqt_resolve_custom_path() {
    local var_name="$1" kind="$2"
    local explicit="${!var_name-}"
    local record="CQT_PATH_ORIGIN_${var_name}"
    local prefix derived

    # RESOLVING TWICE IN ONE PROCESS MUST GIVE THE SAME ANSWER. Every branch below
    # exports the variable, including the not-found one, so a second call reads its own
    # previous output back as a caller's override and reports `explicit` for everything —
    # and a project with no custom modules is then a typo in a config nobody wrote, which
    # is precisely what the origin record exists to prevent.
    #
    # The record is what distinguishes them. A value this library derived is cleared and
    # re-derived; a value the CALLER exported (origin `explicit`) is left alone, because
    # ignoring the variable on every call would discard the override the moment anything
    # resolved twice.
    if [ -n "${!record-}" ] && [ "${!record}" != "explicit" ]; then
        explicit=""
    fi

    CQT_PATH_ORIGIN="derived"
    CQT_PATH_STATE="missing"

    # Written as an `if` rather than `[ -n ... ] && ...`: a caller may be running under
    # `set -e`, and a trailing AND-list whose test fails would hand the enclosing
    # function a non-zero status.
    prefix="$(cqt_drupal_root_prefix)"
    if [ -n "${prefix}" ]; then
        prefix="${prefix}/"
    fi
    derived="${prefix}${kind}/custom"

    if [ -n "${explicit}" ]; then
        CQT_PATH_ORIGIN="explicit"
        if [ -d "${explicit}" ]; then
            CQT_PATH_STATE="ok"
        fi
        export "${var_name}=${explicit}"
        printf -v "CQT_PATH_ORIGIN_${var_name}" '%s' "${CQT_PATH_ORIGIN}"
        return 0
    fi

    if [ -d "${derived}" ]; then
        CQT_PATH_STATE="ok"
        export "${var_name}=${derived}"
    elif [ -d "${kind}/custom" ]; then
        CQT_PATH_ORIGIN="nonstandard"
        CQT_PATH_STATE="ok"
        export "${var_name}=${kind}/custom"
    else
        export "${var_name}=${derived}"
    fi
    # Recorded here, where it is still known. Every branch above exports the variable,
    # the not-found one included, so nothing downstream can tell an override from a
    # derivation by looking at the variable afterwards.
    printf -v "CQT_PATH_ORIGIN_${var_name}" '%s' "${CQT_PATH_ORIGIN}"
    return 0
}

# Both custom-code paths, the call a gate makes.
#
# One line replaces a per-gate web/ layout literal. Under /audit
# the exported values win and no detection runs; invoked directly, or through AIDA's
# /validate-* wrappers, the gate gets the same answer detect-environment.sh would have
# given it — which is the entire defect this library exists to close.
cqt_resolve_drupal_paths() {
    cqt_detect_drupal_root
    cqt_resolve_custom_path DRUPAL_MODULES_PATH modules
    cqt_resolve_custom_path DRUPAL_THEMES_PATH themes
    return 0
}

# How the named variable came by its value: "explicit" when the caller exported one,
# "derived" or "nonstandard" when this library worked it out. A gate reports a missing
# EXPLICIT path differently from a missing derived one — the first is a typo in an
# override, the second is a project with no custom code.
#
# Read from the record cqt_resolve_custom_path wrote, NOT from whether the variable is
# non-empty. Emptiness answers this question only before resolution: afterwards the
# variable is set on every branch, so the emptiness test replies "explicit" to
# everything, and a project with no custom modules is reported as a typo in a config
# nobody wrote. That is the whole reason the origin is captured at the point it is
# decided.
#
# With no record, the variable has not been through the resolver yet and the emptiness
# test is the correct answer to give.
cqt_path_origin() {
    local var_name="$1"
    local record="CQT_PATH_ORIGIN_${var_name}"

    if [ -n "${!record-}" ]; then
        printf '%s' "${!record}"
    elif [ -n "${!var_name-}" ]; then
        printf 'explicit'
    else
        printf 'derived'
    fi
}

# ── the absent-path contract ──────────────────────────────────────────────────

# Can this path be measured at all: "ok" or "missing".
#
# `-e`, not `-d`. references/scope-targeting.md documents pointing DRUPAL_MODULES_PATH at
# a single module directory, and phpcs accepts a plain file too, so a directory-only test
# would call a legitimately scoped run unmeasured.
#
# Returns a WORD rather than echoing the path into a command line, and quotes its
# argument, so a path containing shell metacharacters cannot become one.
cqt_scan_path_state() {
    if [ -e "$1" ]; then
        printf 'ok'
    else
        printf 'missing'
    fi
}

# Announce that a check could not be performed, and record what it could not reach.
#
# The word matters as much as the exit code. "[SKIP]" reads as "nothing to do here";
# "[UNMEASURED]" reads as "this was not checked", which is what actually happened and
# what the reader has to act on.
cqt_unmeasured() {
    local reason="$1"
    shift
    local p
    printf '[UNMEASURED] %s\n' "${reason}"
    for p in "$@"; do
        [ -n "$p" ] || continue
        CQT_UNMEASURED_PATHS+=("$p")
        printf '  not measured: %s\n' "$p"
    done
    return 0
}

# The directory names no gate should report findings from: somebody else's code, vendored
# into this tree. The Next.js gates already exclude these; the Drupal gates did not, so a
# node_modules tree under a custom theme produced findings attributed to the project.
cqt_vendor_excludes() {
    printf '%s\n' node_modules vendor bower_components .git
}

# Is a tool present in the DDEV container, named by its path relative to the project root.
#
# The same `ddev exec test -f` shape install-tools.sh:255-261 and security-check.sh:951
# already use. A probe, not an interpretation of a later exit status: tdd-workflow.sh's
# RED phase reads every non-zero as "the test failed as expected", so a container with no
# PHPUnit and a genuinely failing test were the same signal, and the false one was the
# reassuring one.
cqt_tool_present() {
    ddev exec test -f "$1" > /dev/null 2>&1
}
