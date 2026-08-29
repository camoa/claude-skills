#!/bin/bash
# cqt-install.sh - install the toolchain a validated .code-quality.json asked for.
# Part of code-quality-audit skill
#
# One input, one job. Deliberately not a command and not a skill: full-audit.sh and CI
# both reach it with no model in the loop, which is the whole boundary rule this task
# adopted. Detection is a script, selection is an interview, the config is the artifact
# and the handoff, execution is a script and it fails closed, and verification is a
# SEPARATE script — a thing asking itself whether it worked verifies nothing.
#
# Usage:
#   cqt-install.sh --config PATH [--dry-run | --no-composer]
#   cqt-install.sh --config -    reads the document from stdin, which is how a derived
#                                config reaches it without ever becoming a file
#
#   --dry-run      print the exact command sequence and write nothing at all.
#   --no-composer  do every filesystem step for real, print the package-manager
#                  invocations instead of running them. This is what the template
#                  placement and shadow-refusal assertions run against: real files, no
#                  Composer, no npm, no DDEV.
#
# The stage order is load-bearing, not stylistic. See stage 2.

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/../../templates"
PLUGIN_MANIFEST="${SCRIPT_DIR}/../../../../.claude-plugin/plugin.json"

# shellcheck source=./cqt-config.sh
. "${SCRIPT_DIR}/cqt-config.sh"

# The marker that tells a file this plugin wrote from a file somebody else wrote. It is
# what makes the difference between refusing to shadow (stage 6) and refreshing our own
# output on a second run.
CQT_PROVENANCE="code-quality-tools:generated"

EXEC_PKG=1      # run package-manager commands
EXEC_FS=1       # do filesystem work
CONFIG_PATH=""
FAILED=0
REFUSED=0

usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --config)     CONFIG_PATH="${2-}"; shift 2 ;;
        --config=*)   CONFIG_PATH="${1#--config=}"; shift ;;
        --dry-run)    EXEC_PKG=0; EXEC_FS=0; shift ;;
        --no-composer) EXEC_PKG=0; EXEC_FS=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) printf '%b[ERROR]%b unknown argument: %s\n' "$RED" "$NC" "$1" >&2; exit 2 ;;
    esac
done

[ -n "${CONFIG_PATH}" ] || {
    printf '%b[ERROR]%b --config is required. This installer has exactly one input.\n' "$RED" "$NC" >&2
    exit 2
}

# ── how a command is emitted ──────────────────────────────────────────────────
#
# Every package-manager invocation is PRINTED whether or not it is run, so --dry-run's
# output is the real sequence rather than a description of one, and a live run leaves the
# same record in the terminal.
pkg() {
    if [ "${EXEC_PKG}" -eq 1 ]; then
        printf '[run] %s\n' "$*"
        "$@" || { FAILED=1; printf '%b[FAIL]%b %s\n' "$RED" "$NC" "$*"; return 1; }
    else
        printf '[dry] %s\n' "$*"
    fi
    return 0
}

# ── which binary drives Composer and npm here ─────────────────────────────────
#
# Resolved once, and by probing rather than by assuming. install-tools.sh hardcoded
# `ddev composer` for every Drupal project, so a project not running DDEV got a command
# that does not exist and a [WARN] that read like a package conflict.
COMPOSER_CMD=()
NPM_CMD=()
EXEC_PREFIX=()
resolve_runners() {
    if command -v ddev > /dev/null 2>&1 && ddev describe > /dev/null 2>&1; then
        COMPOSER_CMD=(ddev composer)
        NPM_CMD=(ddev npm)
        EXEC_PREFIX=(ddev exec)
    else
        COMPOSER_CMD=(composer)
        NPM_CMD=(npm)
        EXEC_PREFIX=()
    fi
}

# ── stage 1: load and validate ────────────────────────────────────────────────
#
# Refuse before touching anything. cqt_config_load exits 2 with the field named on any
# failure, so nothing below this line runs against a config nobody validated.
printf '=== code-quality-tools: install ===\n\n'
cqt_config_load "${CONFIG_PATH}" > /dev/null
resolve_runners

PROJECT_TYPE_CFG="$(cqt_config_get .project.type)"
WEB_ROOT="$(cqt_config_get .project.layout.web_root)"
MODULES_PATH="$(cqt_config_get .project.layout.modules)"
THEMES_PATH="$(cqt_config_get .project.layout.themes)"
PHPSTAN_LEVEL_CFG="$(cqt_config_get .phpstan.level)"
HOOKS_ENABLED="$(cqt_config_get .git_hooks.enabled)"
HOOKS_TOOL="$(cqt_config_get .git_hooks.tool)"
ISOLATION_PKG="$(cqt_config_get .isolation.package)"
ISOLATION_CONSTRAINT="$(cqt_config_get .isolation.constraint)"
ISOLATION_ALLOW="$(cqt_config_get .isolation.allow_plugin)"
ISOLATION_FORWARD="$(cqt_config_get .isolation.forward_command_key)"

printf '%b[OK]%b config: %s (%s), type %s, layout %s\n\n' "$GREEN" "$NC" \
    "${CONFIG_PATH}" "$(cqt_config_source)" "${PROJECT_TYPE_CFG}" "${WEB_ROOT:-<root>}"

# Read the scope lists once, into arrays. NUL-separated out of cqt_config_tools and
# consumed into a bash array here, so no package spec ever survives being re-split on
# whitespace or reaches a command as part of a string.
PROJECT_SPECS=(); ISOLATED_SPECS=(); MACHINE_IDS=(); ALLOW_PLUGINS=()
while IFS= read -r -d '' s; do PROJECT_SPECS+=("$s"); done < <(cqt_config_tools project)
while IFS= read -r -d '' s; do ISOLATED_SPECS+=("$s"); done < <(cqt_config_tools isolated)
while IFS= read -r -d '' s; do MACHINE_IDS+=("$s"); done < <(cqt_config_tool_ids machine)
while IFS= read -r -d '' s; do ALLOW_PLUGINS+=("$s"); done < <(cqt_config_allow_plugins)

IS_PHP=0
[ "${PROJECT_TYPE_CFG}" = "drupal" ] && IS_PHP=1
[ "${PROJECT_TYPE_CFG}" = "monorepo" ] && IS_PHP=1

# ── stage 2: authorise Composer plugins, BEFORE any require ───────────────────
#
# This is an ORDERING requirement, not a content one. A plugin refused on first
# activation does not retroactively activate when the key appears later, so every write
# here precedes every require below.
#
# Writing it at all is not optional under --no-interaction: Composer prompts
# interactively, and non-interactively it FAILS rather than silently skipping an unlisted
# plugin — the behaviour composer PR #10314 shipped deliberately to stop exactly the
# silent skip this task exists to fix.
#
# COMPOSER WRITES composer.json, NOT THIS SCRIPT. Not with jq, not with a here-doc, not
# with a merge of our own. Handing `composer config` the job hands Composer four problems
# that would otherwise be ours: merging into a block a project already has, the
# precedence of the user's global config, whether the key belongs under `config` on the
# running version, and preserving the file's formatting so the write does not land in
# somebody's diff as a reformat. --no-plugins is on every call because these writes run
# before the plugins they authorise are allowed to load.
stage_allow_plugins() {
    local p
    [ "${IS_PHP}" -eq 1 ] || return 0
    printf -- '-- Composer plugin authorisation\n'
    for p in "${ALLOW_PLUGINS[@]}"; do
        [ -n "$p" ] || continue
        pkg "${COMPOSER_CMD[@]}" config --no-plugins "allow-plugins.${p}" true
    done
    if [ "${#ISOLATED_SPECS[@]}" -gt 0 ] && [ -n "${ISOLATION_ALLOW}" ]; then
        pkg "${COMPOSER_CMD[@]}" config --no-plugins "allow-plugins.${ISOLATION_ALLOW}" true
    fi
    printf '\n'
}

# ── stage 3: project scope ────────────────────────────────────────────────────
#
# One invocation with the resolved specs. Constraints come from the config, so
# roave/security-advisories arrives as :dev-master rather than unconstrained — the bare
# form at setup.md:77 has no stable version to resolve to and takes the whole batch down
# with it.
stage_project() {
    [ "${#PROJECT_SPECS[@]}" -gt 0 ] || return 0
    printf -- '-- project scope\n'
    if [ "${IS_PHP}" -eq 1 ]; then
        pkg "${COMPOSER_CMD[@]}" require --dev --no-interaction "${PROJECT_SPECS[@]}"
    else
        pkg "${NPM_CMD[@]}" install --save-dev "${PROJECT_SPECS[@]}"
    fi
    printf '\n'
}

# ── stage 4: isolated scope ───────────────────────────────────────────────────
#
# One namespace per tool, never one shared namespace: sharing one graph across four
# analysers reintroduces exactly the collision the scope exists to avoid.
#
# forward-command is set so a developer's plain `composer install` installs the bin
# namespaces too. That forwarding is the single reason this beats a hand-rolled
# tools/composer.json.
stage_isolated() {
    local spec id rest
    [ "${#ISOLATED_SPECS[@]}" -gt 0 ] || return 0
    [ "${IS_PHP}" -eq 1 ] || return 0
    printf -- '-- isolated scope\n'
    pkg "${COMPOSER_CMD[@]}" require --dev --no-interaction \
        "${ISOLATION_PKG}${ISOLATION_CONSTRAINT:+:${ISOLATION_CONSTRAINT}}"
    pkg "${COMPOSER_CMD[@]}" config "${ISOLATION_FORWARD}" true
    for spec in "${ISOLATED_SPECS[@]}"; do
        [ -n "${spec}" ] || continue
        id="${spec%%:*}"
        rest="${spec#*:}"
        pkg "${COMPOSER_CMD[@]}" bin "${id}" require --dev "${rest}"
    done
    printf '\n'
}

# ── stage 5: machine scope, reported and never installed ──────────────────────
#
# install-tools.sh:144,:157 piped a moving branch of somebody's install script into `sh`
# and wrote /usr/local/bin during what the user had asked to be an audit, with a
# privilege it never requested. This reports absence and prints the hint instead. That
# is a security change as much as a scope one.
stage_machine() {
    local id hint
    [ "${#MACHINE_IDS[@]}" -gt 0 ] || return 0
    printf -- '-- machine scope (reported, never installed)\n'
    for id in "${MACHINE_IDS[@]}"; do
        [ -n "${id}" ] || continue
        hint="$(cqt_config_get ".tools.${id}.install_hint")"
        if command -v "${id}" > /dev/null 2>&1; then
            printf '%b[OK]%b %s is on PATH\n' "$GREEN" "$NC" "${id}"
        else
            printf '%b[MISSING]%b %s — %s\n' "$YELLOW" "$NC" "${id}" "${hint:-no hint recorded}"
        fi
    done
    printf '\n'
}

# ── stage 6: templates ────────────────────────────────────────────────────────

# The comment syntax for one placed file, so provenance can be prepended without making
# the file unparseable as itself.
provenance_line() {
    local dest="$1" body
    body="${CQT_PROVENANCE} from ${CONFIG_PATH} by code-quality-tools ${PLUGIN_VERSION}"
    case "${dest}" in
        *.xml)
            # CONFIG_PATH is a path somebody chose, and XML forbids `--` inside a comment
            # at all — `--config my--cfg.json` produced a file DOMDocument rejected with
            # "Double hyphen within comment". A comment carrying provenance must not be
            # able to make the file it describes unparseable, so the run is broken up. A
            # trailing hyphen would close the comment as `--->`, so that is separated too.
            # Looped, because one pass over `----` leaves a `--` behind: the replacement
            # is non-overlapping, so `- -- -` comes back out of `----`.
            while [ "${body}" != "${body//--/- -}" ]; do
                body="${body//--/- -}"
            done
            body="${body%-}"
            printf '<!-- %s -->' "${body}"
            ;;
        *.js)   printf '// %s' "${body}" ;;
        *)      printf '# %s' "${body}" ;;
    esac
}

# Would writing DEST take a configuration away from a project that already had one?
#
# Two cases, and both are the same rule: this installer never deletes, rewrites, or takes
# ownership of a file it did not write.
#
#   1. A version-resolved sibling exists. PHPUnit resolves phpunit.xml BEFORE
#      phpunit.xml.dist, and drupal/core-dev ships a .dist while drupal-ai-contrib
#      writes one, so writing ours would silently override a project's own test
#      configuration.
#   2. The destination itself exists and does not carry our provenance marker, i.e.
#      somebody wrote it by hand. Overwriting that is the same class of harm.
#
# A file that DOES carry the marker is our own output and is refreshed, which is what
# lets /setup be re-run.
would_shadow() {
    local dest="$1"
    if [ -f "${dest}.dist" ] && ! grep -qF "${CQT_PROVENANCE}" "${dest}.dist" 2> /dev/null; then
        printf 'a version-resolved sibling %s already exists, and this plugin did not generate it' "${dest}.dist"
        return 0
    fi
    if [ -f "${dest}" ] && ! grep -qF "${CQT_PROVENANCE}" "${dest}" 2> /dev/null; then
        printf '%s already exists, and this plugin did not generate it' "${dest}"
        return 0
    fi
    return 1
}

# Substitute the layout into one template body.
#
# A literal string replace over a fixed token set, never a regex built from config input.
# The values come from project.layout, which cqt-config.sh invariant 5 has already
# constrained to three web_root values and to plain relative paths with no traversal.
# Tokens are replaced in their QUOTED form first, then bare.
#
# Every template that is parsed by a linter carries its tokens quoted, because a bare
# {{TOKEN}} in a YAML value position is a flow mapping whose key is a flow mapping and
# every parser rejects it. Replacing the quotes along with the token is what turns
# `- "{{MODULES_PATH}}"` into `- web/modules/custom` rather than into a quoted string
# that happens to look right.
#
# The quoted-form pass is what YAML and NEON need and what XML must NOT get. In XML the
# quotes around an attribute value are syntax, not part of the value, so eating them turns
# `<directory name="{{MODULES_PATH}}" />` into `<directory name=web/modules/custom />`,
# which no parser accepts. The defect was invisible while the provenance comment sat above
# the XML declaration and every placed XML file was already unparseable; fixing that
# uncovered it. So the destination's format decides, and `eat_quotes` is 0 for XML.
sub_token() {   # <body> <token> <value> <eat_quotes: 0|1>
    local body="$1" tok="$2" val="$3" eat="${4:-1}"
    [ "${eat}" -eq 1 ] && body="${body//\"\{\{${tok}\}\}\"/${val}}"
    body="${body//\{\{${tok}\}\}/${val}}"
    printf '%s' "${body}"
}

substitute() {   # <body> <dest>
    local body="$1" dest="${2-}" tasks eat=1
    [ "${dest##*.}" = "xml" ] && eat=0
    tasks="$(cqt_config_doc | jq -r '[.git_hooks.tasks[]?] | join(", ")')"
    body="$(sub_token "${body}" WEB_ROOT "${WEB_ROOT}" "${eat}")"
    body="$(sub_token "${body}" WEB_ROOT_PREFIX "${WEB_ROOT:+${WEB_ROOT}/}" "${eat}")"
    body="$(sub_token "${body}" MODULES_PATH "${MODULES_PATH}" "${eat}")"
    body="$(sub_token "${body}" THEMES_PATH "${THEMES_PATH}" "${eat}")"
    body="$(sub_token "${body}" HOOK_TASKS "[${tasks}]" "${eat}")"

    # The PHPStan level is a rewritten LINE, not a token, and deliberately so. The
    # template is parsed as YAML by the spec (section O pins its level, its paths and
    # its empty ignoreErrors), and a token there makes the file unparseable — so the
    # template keeps a real integer and this replaces it. phpstan.level in the config is
    # still the single source of truth the epic settled on; the literal in the template
    # is the same default, so the two cannot silently disagree.
    if [ -n "${PHPSTAN_LEVEL_CFG}" ]; then
        body="$(printf '%s' "${body}" \
            | sed -E "s|^([[:space:]]*)level:[[:space:]]*[0-9]+[[:space:]]*\$|\\1level: ${PHPSTAN_LEVEL_CFG}|")"
    fi
    printf '%s' "${body}"
}


PLUGIN_VERSION="unknown"
[ -f "${PLUGIN_MANIFEST}" ] && PLUGIN_VERSION="$(jq -r '.version // "unknown"' "${PLUGIN_MANIFEST}" 2> /dev/null)"

stage_templates() {
    local id src dest body prov reason
    printf -- '-- templates\n'
    while IFS= read -r id; do
        [ -n "${id}" ] || continue
        # The id came out of the schema's fixed allowlist (invariant 3), so it is a
        # known string rather than a path assembled from config input.
        src="${TEMPLATE_DIR}/${id}"
        dest="./$(basename "${id}")"
        if [ ! -f "${src}" ]; then
            printf '%b[FAIL]%b template %s is not in this plugin at %s\n' "$RED" "$NC" "${id}" "${src}"
            FAILED=1
            continue
        fi
        if reason="$(would_shadow "${dest}")"; then
            REFUSED=$((REFUSED + 1))
            printf '%b[DECLINED]%b %s not written: %s.\n' "$YELLOW" "$NC" "${dest}" "${reason}"
            printf '            Nothing was deleted or rewritten. This installer does not take\n'
            printf '            ownership of a file it did not write.\n'
            continue
        fi
        if [ "${EXEC_FS}" -eq 0 ]; then
            printf '[dry] place %s -> %s\n' "${id}" "${dest}"
            continue
        fi
        body="$(cat "${src}")"
        body="$(substitute "${body}" "${dest}")"
        prov="$(provenance_line "${dest}")"
        # An XML declaration has to stay the first line of the document, so the
        # provenance comment goes after it rather than before.
        #
        # `##*.`, not `#*.`: dest is built above as "./$(basename ...)", so it ALWAYS
        # begins with "./" and the shortest-match form strips through that first period.
        # For "./psalm.xml" it expanded to "/psalm.xml", never "xml", so this branch never
        # ran once — every generated XML file got the comment above its declaration and
        # libxml refused all three with "XML declaration allowed only at the start of the
        # document". The comment right above described behaviour the code did not have.
        if [ "${dest##*.}" = "xml" ] && printf '%s' "${body}" | head -1 | grep -q '<?xml'; then
            { printf '%s\n' "$(printf '%s' "${body}" | head -1)"
              printf '%s\n' "${prov}"
              printf '%s' "${body}" | tail -n +2
            } > "${dest}"
        else
            { printf '%s\n' "${prov}"; printf '%s' "${body}"; } > "${dest}"
        fi
        printf '%b[OK]%b placed %s\n' "$GREEN" "$NC" "${dest}"
    done <<< "$(cqt_config_doc | jq -r '.templates[]? // empty')"
    printf '\n'
}

# ── stage 7: git hooks, only on the consent that installed the package ────────
#
# GrumPHP attaches hooks at package-install time per its own README, so consent for the
# package and consent for the hooks are the same answer. That is why there is no second
# prompt here and no second install list: cqt-config.sh invariant 4 has already refused a
# config where git_hooks.enabled is false and a consent-gated tool is present.
stage_hooks() {
    [ "${HOOKS_ENABLED}" = "true" ] || return 0
    printf -- '-- git hooks\n'
    case "${HOOKS_TOOL}" in
        grumphp) pkg "${EXEC_PREFIX[@]}" vendor/bin/grumphp git:init ;;
        husky)   pkg "${NPM_CMD[@]}" exec husky init ;;
        *)       printf '%b[WARN]%b git_hooks.enabled is true but no tool is named\n' "$YELLOW" "$NC" ;;
    esac
    printf '\n'
}

# ── stage 8: hand off to a separate process ───────────────────────────────────
#
# Separate file, separate process. The boundary rule this task adopted says verification
# is a script and it is separate from execution, because the thing that did the work is
# the worst possible judge of whether the work landed.
stage_verify() {
    local verifier="${SCRIPT_DIR}/install-verify.sh"
    printf -- '-- verification (separate process)\n'
    if [ "${EXEC_PKG}" -eq 0 ]; then
        printf '[dry] %s --config %s\n\n' "${verifier}" "${CONFIG_PATH}"
        return 0
    fi
    if [ ! -x "${verifier}" ] && [ ! -f "${verifier}" ]; then
        printf '%b[FAIL]%b install-verify.sh is missing; an install nobody verified is not an install that worked\n' "$RED" "$NC"
        FAILED=1
        return 0
    fi
    # The verifier reads the same document the installer acted on. When the config was
    # derived, that document never became a file, so it is piped in on stdin.
    #
    # Its exit status is read as four states rather than two.
    #
    # 4 is `unmeasured`: no check could be applied, so nothing about this toolchain was
    # established. That is not a passing install — an install nobody could verify is the
    # state this whole stage exists to surface — so it still fails the run, but it is
    # REPORTED as its own thing, because "we could not look" and "we looked and it is
    # broken" call for different fixes. Reading only zero-or-not is what let a run with
    # three skipped checks print "[OK] the installed toolchain can fail".
    #
    # 5 is `partial`: every check that could be applied passed, and at least one could
    # not. It does NOT fail the install, and that is a deliberate line rather than a
    # softening. git_hooks.enabled false is a legitimate config — it is what every derived
    # config carries — so the hook check skips on a large share of correct installs, and
    # failing them would make the state fire so often it stopped carrying information.
    # What it must not do is disappear: the verifier's own [PARTIAL] block names which
    # checks were applied and which were not, and this repeats the consequence, so the
    # difference between a verified install and a partly verified one is on screen either
    # way.
    local vexit=0
    if [ "$(cqt_config_source)" = "derived" ]; then
        cqt_config_doc | bash "${verifier}" --config -
        vexit="${PIPESTATUS[1]}"
    else
        bash "${verifier}" --config "${CONFIG_PATH}" || vexit=$?
    fi
    case "${vexit}" in
        0) ;;
        4) FAILED=1
           printf '%b[UNMEASURED]%b verification could apply none of its checks here, so this\n' "$YELLOW" "$NC"
           printf '              install is not verified. That is recorded as a failure: an\n'
           printf '              install nobody could verify is not an install that worked.\n'
           ;;
        5) printf '%b[PARTIAL]%b verification applied some of its checks and none of them\n' "$YELLOW" "$NC"
           printf '          failed. The ones it could not apply are named above, and nothing\n'
           printf '          is established about what those cover. The install is not failed\n'
           printf '          for that; it is also not fully verified.\n'
           ;;
        *) FAILED=1 ;;
    esac
    printf '\n'
}

stage_allow_plugins
stage_project
stage_isolated
stage_machine
stage_templates
stage_hooks
stage_verify

printf -- '----\n'
if [ "${REFUSED}" -gt 0 ]; then
    printf '%b[INFO]%b %s config file(s) were not written, each with the reason above.\n' \
        "$YELLOW" "$NC" "${REFUSED}"
fi
if [ "${FAILED}" -ne 0 ]; then
    printf '%b[FAIL]%b the install did not complete.\n' "$RED" "$NC"
    exit 1
fi
printf '%b[OK]%b install complete.\n' "$GREEN" "$NC"
exit 0
