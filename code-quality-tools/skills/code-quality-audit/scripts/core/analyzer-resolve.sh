#!/bin/bash
# analyzer-resolve.sh - Resolve an analyzer binary to a runnable command.
# Part of code-quality-audit skill. Sourced, never executed.
#
# ONE resolver, for every gate that has to find an analyzer. It lived inside
# solid-check.sh and was the only place that knew about the `isolated` scope's
# vendor-bin layout, so dry-check.sh — which runs the one analyzer the catalog scopes
# isolated — probed `vendor/bin/phpcpd` alone and reported a CORRECTLY installed phpcpd
# as `tools_absent`, skipping the DRY gate on a project that had the tool. Moving the
# function here rather than copying it is the point: a second copy is a second place for
# the four locations to disagree.
#
# Sets, on success:
#   ANALYZER_CMD     the argv prefix to invoke, as an array
#   ANALYZER_RUNNER  container | host
# Returns 1 when the tool is nowhere at all, which is an EXPECTED absence: a gate runs
# what IS available and records the rest.

# shellcheck disable=SC2034
# The absolute path composer installs global binaries into, resolved at most once.
# `composer global config` prints "Changed current directory to ..." on STDERR, so
# stdout alone is the path. Empty when composer is absent or the lookup fails.
COMPOSER_GLOBAL_BIN=""
COMPOSER_GLOBAL_BIN_RESOLVED=0
resolve_composer_global_bin() {
    if [ "$COMPOSER_GLOBAL_BIN_RESOLVED" -eq 1 ]; then
        return 0
    fi
    COMPOSER_GLOBAL_BIN_RESOLVED=1
    if command -v composer &> /dev/null; then
        COMPOSER_GLOBAL_BIN=$(composer global config bin-dir --absolute 2>/dev/null) \
            || COMPOSER_GLOBAL_BIN=""
    fi
    return 0
}

# Resolve an analyzer to a runnable command. A tool counts as available if it exists
# anywhere a developer plausibly installed it, not only in the repo's vendor/bin.
# Adding phpmd and friends to a client's composer.json as dev dependencies is often
# not acceptable when auditing third-party code, so `composer global require` is the
# polite install — and a globally installed analyzer that works must not be recorded
# as "tool absent" and skipped.
#
# The runner is chosen by where the binary ACTUALLY is, mirroring the semgrep dispatch
# in security-check.sh. Probing one location and then dispatching to another is how a
# host-only tool came to be invoked inside the container, where it does not exist.
# Order: the repo's vendor/bin in the container first (a project-pinned version wins
# over whatever the machine happens to have), then the host PATH, then composer's
# global bin dir, which is frequently not on PATH.
#
# Sets ANALYZER_CMD (the argv prefix to invoke) and ANALYZER_RUNNER (container|host).
# Returns 1 when the tool is nowhere at all, which is an EXPECTED absence: the gate
# runs what IS available and records absences in the report.
resolve_analyzer() {
    local tool="$1"
    ANALYZER_CMD=()
    ANALYZER_RUNNER=""

    if ddev exec test -f "vendor/bin/$tool" &> /dev/null; then
        ANALYZER_RUNNER="container"
        ANALYZER_CMD=(ddev exec "vendor/bin/$tool")
        return 0
    fi

    # A fourth location, for a tool installed at `isolated` scope. Four analysers with
    # their own dependency trees do not belong in an application's require-dev, so
    # cqt-install.sh puts phpmd, phpcpd, php-security-linter and psalm into their own
    # bamarni bin namespaces instead. This is where they land.
    #
    # SECOND and not first, so a project that deliberately pinned a tool in its own
    # vendor/bin still wins, which is the existing order's stated intent. Second and not
    # last, so an isolated install is preferred over whatever the machine happens to
    # have. One lookup added to the resolver that already exists; nothing new resolves
    # paths, so nothing new can resolve them differently.
    if ddev exec test -f "vendor-bin/$tool/vendor/bin/$tool" &> /dev/null; then
        ANALYZER_RUNNER="container"
        ANALYZER_CMD=(ddev exec "vendor-bin/$tool/vendor/bin/$tool")
        return 0
    fi

    if command -v "$tool" &> /dev/null; then
        ANALYZER_RUNNER="host"
        ANALYZER_CMD=("$tool")
        return 0
    fi

    resolve_composer_global_bin
    if [ -n "$COMPOSER_GLOBAL_BIN" ] && [ -x "${COMPOSER_GLOBAL_BIN}/${tool}" ]; then
        ANALYZER_RUNNER="host"
        ANALYZER_CMD=("${COMPOSER_GLOBAL_BIN}/${tool}")
        return 0
    fi

    return 1
}
