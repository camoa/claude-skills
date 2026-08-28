#!/usr/bin/env bash
# Generates the tool inventory in code-quality-tools/commands/setup.md from
# code-quality-tools/skills/code-quality-audit/schema/tool-catalog.json.
#
# Four lists used to disagree about what /code-quality-tools:setup installs:
# commands/setup.md, scripts/core/install-tools.sh,
# references/operations/drupal-setup.md and templates/ci/github-drupal.yml. Each was a
# hardcoded list living inside the file that consumed it. This target removes one of
# them by generating it.
#
# GENERATION RELOCATES THE COMPARISON, IT DOES NOT REMOVE IT. One generated list cannot
# disagree with itself, but the file it is written into can still be hand-edited, and
# both mature tools in this space ship a guard for that. All three of their mechanisms
# are here, because the guard is the part that is easy to leave out:
#
#   * MARKERS, so the generated region has a boundary. terraform-docs replaces
#     everything between <!-- BEGIN_TF_DOCS --> and <!-- END_TF_DOCS -->; cog uses
#     [[[cog / ]]] / [[[end]]].
#   * AN IN-REGION BANNER, so a reader already inside the region learns it is
#     generated. terraform-docs issue #309 exists because people edit generated READMEs
#     without realising, and the fix shipped was exactly this banner.
#   * A CHECKSUM ON THE END MARKER, so the write path refuses instead of overwriting.
#     `cog -c` writes one and stops when the region no longer matches, "to avoid
#     overwriting the edited output".
#
# Three modes:
#
#   gen-setup-doc.sh            rewrite the region in place. RECOMPUTES the digest of
#                               the committed region first and REFUSES on a mismatch,
#                               because a mismatch means somebody's hand edit is about
#                               to be destroyed. It does not repair and does not
#                               overwrite. `make setup-doc`.
#   gen-setup-doc.sh --force    the deliberate override, for the person who has read
#                               the refusal and moved their edit somewhere that
#                               survives. Nothing in make calls this.
#   gen-setup-doc.sh --check    regenerate into a temp file, diff, and fail with the
#                               diff printed when the committed file differs. Also
#                               verifies the recorded checksum. `make setup-doc-check`,
#                               which joins the ci target.
#
# The diff and the checksum catch different things and both are kept. The diff is the
# repo guard: it fails CI when the committed file no longer matches what the catalog
# generates, whoever changed which side. The checksum is the local guard: it makes the
# write path stop before destroying an edit, at the moment the person is standing there
# to read the message. A diff alone reports the loss after it happened.
#
# Failing honestly, per the repo's stated rule that a check cannot pass without doing
# work: zero catalog entries fails, a missing marker fails, a missing or malformed
# checksum fails, an unreadable setup.md fails, and an untracked setup.md fails. An
# absent checksum is a FAILURE and not "an unchecksummed region we will adopt", because
# that is exactly the state a hand edit produces when somebody deletes a marker line
# they did not understand.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# The markers / banner / checksum mechanism lives in ONE place: scripts/gen-tool-versions.sh
# needs the identical contract for tool-comparison.md's version table, and a second copy of
# a checksum protocol drifts the way the four hardcoded package lists did.
# shellcheck source=./lib/generated-region.sh
. "${SCRIPT_DIR}/lib/generated-region.sh"

ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SETUP_MD_DEFAULT="${ROOT}/code-quality-tools/commands/setup.md"
CATALOG_DEFAULT="${ROOT}/code-quality-tools/skills/code-quality-audit/schema/tool-catalog.json"

SETUP_MD="${SETUP_MD_DEFAULT}"
CATALOG="${CATALOG_DEFAULT}"
MODE="write"

BEGIN_MARKER='<!-- BEGIN GENERATED: tool-catalog -->'
END_PREFIX='<!-- END GENERATED: tool-catalog sha256:'
END_SUFFIX=' -->'

die() { printf 'gen-setup-doc: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check)     MODE="check"; shift ;;
        --force)     MODE="force"; shift ;;
        --setup-md)  SETUP_MD="${2-}"; shift 2 ;;
        --catalog)   CATALOG="${2-}"; shift 2 ;;
        -h|--help)   sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

command -v jq > /dev/null 2>&1 || die "jq is required"

[ -f "${CATALOG}" ]  || die "catalog not found: ${CATALOG}"
[ -f "${SETUP_MD}" ] || die "setup.md not found: ${SETUP_MD}"

# A brand-new command file is invisible to `make outputs` and `make test` until it is
# git-added, and the same is true here: generating into an untracked file produces a
# region CI will never compare. Only asserted for the real file, because the spec
# necessarily works on a copy in a temp directory.
if [ "${SETUP_MD}" = "${SETUP_MD_DEFAULT}" ] && git -C "${ROOT}" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    git -C "${ROOT}" ls-files --error-unmatch "${SETUP_MD}" > /dev/null 2>&1 \
        || die "setup.md is not tracked by git, so a generated region in it would never be compared by CI"
fi

TOOL_COUNT="$(jq -r '.tools | length' "${CATALOG}" 2> /dev/null)" || die "catalog is not valid JSON"
[ "${TOOL_COUNT:-0}" -gt 0 ] 2> /dev/null \
    || die "the catalog holds zero tools, so there is nothing to generate. A check that found nothing to check has not passed."

# ── the region body ───────────────────────────────────────────────────────────
#
# The banner is part of the generated output, so the generator writes it and the digest
# covers it. A region carrying no banner therefore fails the digest as surely as an
# edited table does.
#
# What is generated is the tool INVENTORY and nothing else. It names tools and holds no
# `composer require` and no command, which is how criterion 17 (generate the installable
# content) and criterion 7 (no package list in setup.md) stop fighting.
build_region() {
    printf '<!-- Generated from skills/code-quality-audit/schema/tool-catalog.json.\n'
    printf '     Do not modify this region directly; edit the catalog and run `make setup-doc`.\n'
    printf '     `make setup-doc-check` fails when this region and the catalog disagree. -->\n'
    printf '\n'
    printf '| Tool | Package | Scope | Category |\n'
    printf '|---|---|---|---|\n'
    jq -r '
        .tools | to_entries[]
        | .key as $id
        | .value as $t
        | ( if ($t.packages | length) == 0 then "_(no package; installed on the machine)_"
            else [ $t.packages[] | .name + (if (.constraint // "") == "" then "" else " " + .constraint end) ]
                 | join("<br>")
            end ) as $pkgs
        | "| `" + $id + "` | " + $pkgs + " | " + $t.scope + " | " + $t.category + " |"
    ' "${CATALOG}"
}

# ── read what is committed ────────────────────────────────────────────────────
#
# region_load enforces the marker-and-checksum contract and sets REGION_BODY,
# REGION_DIGEST and REGION_RECORDED. Its failure messages are the ones this script used to
# raise itself, including the refusal of an end marker that carries no digest.
region_load "${SETUP_MD}" "${BEGIN_MARKER}" "${END_PREFIX}" "${END_SUFFIX}" || die "${REGION_ERROR}"

BEGIN_NO="${REGION_BEGIN_NO}"
END_NO="${REGION_END_NO}"
RECORDED="${REGION_RECORDED}"
COMMITTED_BODY="${REGION_BODY}"
COMMITTED_DIGEST="${REGION_DIGEST}"

NEW_BODY="$(build_region)"
NEW_DIGEST="$(region_digest "${NEW_BODY}")"

write_region() {
    region_replace "${SETUP_MD}" "${BEGIN_NO}" "${END_NO}" \
        "${NEW_BODY}" "${NEW_DIGEST}" "${END_PREFIX}" "${END_SUFFIX}" \
        || die "could not write ${SETUP_MD}"
}

case "${MODE}" in
    check)
        FAILED=""
        if [ "${COMMITTED_DIGEST}" != "${RECORDED}" ]; then
            FAILED="checksum"
            printf 'gen-setup-doc: the region no longer matches its own checksum.\n' >&2
            printf '  recorded: %s\n  computed: %s\n' "${RECORDED}" "${COMMITTED_DIGEST}" >&2
            printf '  Somebody edited inside the generated region. Move the edit into the\n' >&2
            printf '  catalog, or into the prose outside the markers, then run make setup-doc.\n' >&2
        fi
        if [ "${COMMITTED_BODY}" != "${NEW_BODY}" ]; then
            FAILED="${FAILED:+${FAILED} and }content"
            printf 'gen-setup-doc: the committed region differs from what the catalog generates.\n' >&2
            diff <(printf '%s\n' "${COMMITTED_BODY}") <(printf '%s\n' "${NEW_BODY}") >&2 || true
        fi
        # The one fact no generator produces: whether the two live call sites that reach
        # install-tools.sh still exist. That is a call site, not content, so it follows
        # check_version_drift()'s match / drift / unchecked shape and reports
        # `unchecked` with a reason rather than passing when it cannot read them.
        for site in "${ROOT}/code-quality-tools/skills/code-quality-audit/scripts/core/full-audit.sh" \
                    "${ROOT}/code-quality-tools/skills/code-quality-audit/SKILL.md"; do
            if [ ! -r "${site}" ]; then
                printf 'gen-setup-doc: unchecked — %s is not readable, so it could not be confirmed that it still routes to install-tools.sh\n' "${site}" >&2
                FAILED="${FAILED:+${FAILED} and }unchecked-call-site"
            elif ! grep -q 'install-tools.sh' "${site}"; then
                printf 'gen-setup-doc: %s no longer routes to install-tools.sh. The generated inventory describes an install path that file no longer reaches.\n' "${site}" >&2
                FAILED="${FAILED:+${FAILED} and }call-site"
            fi
        done
        [ -z "${FAILED}" ] || exit 1
        printf 'gen-setup-doc: setup.md matches the catalog (%s tools), and its checksum holds.\n' "${TOOL_COUNT}"
        exit 0
        ;;
    force)
        write_region
        printf 'gen-setup-doc: region regenerated from %s tools (--force).\n' "${TOOL_COUNT}"
        exit 0
        ;;
    write)
        if [ "${COMMITTED_DIGEST}" != "${RECORDED}" ]; then
            printf 'gen-setup-doc: REFUSING to regenerate.\n' >&2
            printf '  The committed region does not match the checksum on its end marker, which\n' >&2
            printf '  means it was edited by hand. Regenerating would destroy that edit silently.\n' >&2
            printf '  recorded: %s\n  computed: %s\n\n' "${RECORDED}" "${COMMITTED_DIGEST}" >&2
            printf '  The region as committed:\n' >&2
            printf '%s\n' "${COMMITTED_BODY}" | sed 's/^/  | /' >&2
            printf '\n  Move the edit into schema/tool-catalog.json, or into the prose outside the\n' >&2
            printf '  markers. Then run gen-setup-doc.sh --force to regenerate deliberately.\n' >&2
            exit 1
        fi
        write_region
        printf 'gen-setup-doc: region regenerated from %s tools.\n' "${TOOL_COUNT}"
        exit 0
        ;;
esac
