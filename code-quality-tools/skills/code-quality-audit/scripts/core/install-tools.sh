#!/bin/bash
# install-tools.sh - the entry point the two live callers already reach.
# Part of code-quality-audit skill
#
# Keeps its name because full-audit.sh:248 and SKILL.md:124 both route here. What it does
# has changed completely: it used to BE the install, with a thirteen-step hardcoded
# package list that disagreed with the one in commands/setup.md. Now it resolves a config
# and hands off, so there is one install path and it lives in a file that runs.
#
#   install-tools.sh [--config PATH] [--dry-run]
#
# With .code-quality.json present it loads the file. With it absent it DERIVES a complete
# config from the tool catalog, announces it in full, and pipes it to the installer on
# stdin. It does not write the file: /code-quality-tools:setup is this plugin's init
# command and its only writer. An audit run therefore installs the right set and states
# what it resolved, without leaving a config file in a repository whose owner never asked
# for one.
#
# It exits honestly. full-audit.sh reads both this exit status and the tools-status.json
# written below; the `|| true` that used to discard the status was fixed by the
# gate_path_resolution sibling, and this script's job is to give that caller something
# true to read.

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Where reports go is decided in one place, and it is never inside the audited
# repository unless REPORT_DIR says so or REPORT_DIR_IN_REPO=1 asks for it.
# shellcheck source=./report-dir.sh
. "${SCRIPT_DIR}/report-dir.sh"
cqt_report_dir_init
cqt_announce_report_dir

# Where this project's custom code lives is answered in ONE place, for every gate and now
# for the installer too. Sourcing this is safe by construction: it sources nothing, runs
# nothing at load time, sets no shell option and prints nothing.
# shellcheck source=./path-resolve.sh
. "${SCRIPT_DIR}/path-resolve.sh"

# shellcheck source=./cqt-config.sh
. "${SCRIPT_DIR}/cqt-config.sh"

DRY_RUN=0
CONFIG_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --config)   CONFIG_ARG="${2-}"; shift 2 ;;
        --config=*) CONFIG_ARG="${1#--config=}"; shift ;;
        --dry-run)  DRY_RUN=1; shift ;;
        -h|--help)  sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf '%b[ERROR]%b unknown argument: %s\n' "$RED" "$NC" "$1" >&2; exit 2 ;;
    esac
done

echo "=== Code Quality Audit - Install Tools ==="
echo ""

# ── which stack, answered from evidence rather than defaulted ─────────────────
#
# This is the line the research names by file:line. The old code read two scalars out of
# environment.json with a Perl-regex grep and then did PROJECT_TYPE="${PROJECT_TYPE:-drupal}",
# so a missing, truncated or renamed field produced a Drupal install on a project nobody
# had established was Drupal, behind a [WARN] nobody reads.
#
# Detection is allowed to look in several places — that is what detection is. What it is
# not allowed to do is invent an answer when every source came up empty, so the last
# branch refuses instead of picking one.
detect_project_type() {
    local t=""

    if [ -n "${PROJECT_TYPE:-}" ]; then
        printf '%s' "${PROJECT_TYPE}"
        return 0
    fi
    if [ -f "${REPORT_DIR}/environment.json" ] && command -v jq > /dev/null 2>&1; then
        t="$(jq -r '.project_type // empty' "${REPORT_DIR}/environment.json" 2> /dev/null)"
        [ -n "$t" ] && { printf '%s' "$t"; return 0; }
    fi
    if [ -f composer.json ] && grep -q '"drupal/core' composer.json 2> /dev/null; then
        printf 'drupal'; return 0
    fi
    if [ -f package.json ] && grep -q '"next"' package.json 2> /dev/null; then
        printf 'nextjs'; return 0
    fi
    for d in modules/custom web/modules/custom docroot/modules/custom; do
        if [ -d "$d" ]; then printf 'drupal'; return 0; fi
    done
    return 1
}

# ── resolve the config ────────────────────────────────────────────────────────
CONFIG_SOURCE_KIND=""
CONFIG_TO_USE=""
DERIVED_DOC=""

if [ -n "${CONFIG_ARG}" ]; then
    CONFIG_TO_USE="${CONFIG_ARG}"
    CONFIG_SOURCE_KIND="file"
elif [ -f .code-quality.json ]; then
    CONFIG_TO_USE=".code-quality.json"
    CONFIG_SOURCE_KIND="file"
else
    PTYPE="$(detect_project_type)" || {
        printf '%b[ERROR]%b no .code-quality.json, and the project type could not be\n' "$RED" "$NC" >&2
        printf '        determined from the environment record, composer.json, package.json\n' >&2
        printf '        or the tree. Nothing is assumed here: run /code-quality-tools:setup,\n' >&2
        printf '        or pass PROJECT_TYPE explicitly.\n' >&2
        exit 2
    }
    cqt_detect_drupal_root
    WEBROOT="$(cqt_drupal_root_prefix)"
    # A Next.js project has no Drupal root, and cqt_drupal_root_prefix keeps the
    # historical "web" default when it has nothing to derive from. That default is right
    # for a Drupal project with no detected root and wrong here, so it is cleared rather
    # than carried into a layout the config would then record as fact.
    [ "${PTYPE}" = "nextjs" ] && WEBROOT=""
    DERIVED_DOC="$(cqt_config_derive "${PTYPE}" "${WEBROOT}")"
    CONFIG_TO_USE="-"
    CONFIG_SOURCE_KIND="derived"

    # Validated exactly as a file is, then announced in full. The announcement is the
    # half that stops the silent skip, and it does not depend on any other task landing.
    cqt_config_load - > /dev/null <<< "${DERIVED_DOC}"
    cqt_config_announce_derived
    echo ""
fi

# ── hand off ──────────────────────────────────────────────────────────────────
INSTALL_ARGS=(--config "${CONFIG_TO_USE}")
[ "${DRY_RUN}" -eq 1 ] && INSTALL_ARGS+=(--dry-run)

install_exit=0
if [ "${CONFIG_SOURCE_KIND}" = "derived" ]; then
    printf '%s' "${DERIVED_DOC}" | bash "${SCRIPT_DIR}/cqt-install.sh" "${INSTALL_ARGS[@]}" || install_exit=$?
else
    bash "${SCRIPT_DIR}/cqt-install.sh" "${INSTALL_ARGS[@]}" || install_exit=$?
fi

# ── the record full-audit.sh reads ────────────────────────────────────────────
#
# full-audit.sh:255-266 stops the audit when tools-status.json is absent or its all_ok is
# not true, on the stated ground that an exit status alone cannot say "phpmd missing,
# phpstan fine". That contract predates this rewrite and is kept: an installer that
# stopped writing the file would fire the sibling's stop-on-failed-install gate on every
# run.
#
# Nothing is written on a dry run, because a dry run installed nothing and a status file
# claiming otherwise is exactly the false record this epic exists to remove.
if [ "${DRY_RUN}" -eq 0 ]; then
    mkdir -p "${REPORT_DIR}"
    TOOLS_JSON="$(
        cqt_config_doc \
        | jq -c '
            [ .tools | to_entries[] | select(.value.bin != null) | { key: .key, bin: .value.bin, scope: .value.scope } ]
          '
    )"
    STATUS_ENTRIES=""
    ALL_OK=true
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        id="$(jq -r '.key' <<< "$row")"
        bin="$(jq -r '.bin' <<< "$row")"
        scope="$(jq -r '.scope' <<< "$row")"
        state="absent"
        if command -v "${bin}" > /dev/null 2>&1; then
            state="ok"
        elif [ -x "vendor/bin/${bin}" ]; then
            state="ok"
        elif [ -x "vendor-bin/${id}/vendor/bin/${bin}" ]; then
            state="ok"
        elif command -v ddev > /dev/null 2>&1 && cqt_tool_present "vendor/bin/${bin}"; then
            state="ok"
        fi
        # A machine-scope tool that is not installed is a state of the machine, not a
        # failed install. Only the tools this run was supposed to install can fail it.
        if [ "${state}" != "ok" ] && [ "${scope}" != "machine" ]; then
            ALL_OK=false
        fi
        STATUS_ENTRIES="${STATUS_ENTRIES}${STATUS_ENTRIES:+,}$(jq -nc --arg k "$id" --arg v "$state" '{($k): $v}')"
    done <<< "$(jq -c '.[]' <<< "${TOOLS_JSON}")"

    [ "${install_exit}" -eq 0 ] || ALL_OK=false

    jq -n \
        --argjson tools "$( [ -n "${STATUS_ENTRIES}" ] && printf '[%s]' "${STATUS_ENTRIES}" || printf '[]' )" \
        --arg pt "$(cqt_config_get .project.type)" \
        --arg src "$(cqt_config_source)" \
        --argjson all_ok "${ALL_OK}" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        {
          status: (if $all_ok then "pass" else "fail" end),
          timestamp: $ts,
          installed_at: $ts,
          project_type: $pt,
          config_source: $src,
          tools: ($tools | add // {}),
          findings: [ $tools | add // {} | to_entries[] | select(.value != "ok")
                      | { tool: .key, state: .value } ],
          all_ok: $all_ok
        }' > "${REPORT_DIR}/tools-status.json"

    if [ "${ALL_OK}" = "true" ]; then
        printf '%b[OK]%b tool status written to %s\n' "$GREEN" "$NC" "${REPORT_DIR}/tools-status.json"
    else
        printf '%b[WARN]%b some tools are not available; see %s\n' "$YELLOW" "$NC" "${REPORT_DIR}/tools-status.json"
    fi
fi

exit "${install_exit}"
