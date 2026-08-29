#!/usr/bin/env bash
# Generates the PHP-ecosystem version table in
# code-quality-tools/skills/code-quality-audit/references/tool-comparison.md from two
# schema files:
#
#   schema/tool-catalog.json       package name and the constraint the installer resolves
#   schema/upstream-versions.json  what upstream published, and the date that was read
#
# The table used to be six hand-written rows under one heading date, `## Tool Versions
# (December 2025)`. Two of the six were wrong on the PHP floor, one was a major behind,
# and the heading gave no way to tell which rows had been re-read. Generating it makes the
# constraint column the installer's own constraint rather than a second copy of it, which
# is what turns "the coder row agrees with what the installer requires" from something you
# read into something a check compares.
#
# The mechanism — markers, an in-region banner, a checksum on the end marker — is
# scripts/lib/generated-region.sh, shared with scripts/gen-setup-doc.sh rather than copied
# from it. What lives here is what the region contains.
#
# Three modes, the same three the sibling generator has:
#
#   gen-tool-versions.sh          rewrite the region in place, REFUSING when the committed
#                                 region no longer matches its own checksum, because a
#                                 mismatch means a hand edit is about to be destroyed.
#                                 `make tool-versions`.
#   gen-tool-versions.sh --force  the deliberate override. Nothing in make calls it.
#   gen-tool-versions.sh --check  regenerate into memory, diff, and fail with the diff
#                                 printed. Called by scripts/check-claims.sh as rule R5.
#
# Failing honestly: zero catalog entries fails, zero generated rows fails, a missing
# marker fails, a missing or malformed checksum fails. A generator that produced an empty
# table and reported success would be the false-clean shape this epic exists to remove.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/generated-region.sh
. "${SCRIPT_DIR}/lib/generated-region.sh"

ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="write"

BEGIN_MARKER='<!-- BEGIN GENERATED: tool-versions -->'
END_PREFIX='<!-- END GENERATED: tool-versions sha256:'
END_SUFFIX=' -->'

die() { printf 'gen-tool-versions: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check)   MODE="check"; shift ;;
        --force)   MODE="force"; shift ;;
        --root)    ROOT="${2-}"; shift 2 ;;
        --root=*)  ROOT="${1#--root=}"; shift ;;
        -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

CQA="${ROOT}/code-quality-tools/skills/code-quality-audit"
CATALOG="${CQA}/schema/tool-catalog.json"
UPSTREAM="${CQA}/schema/upstream-versions.json"
TARGET="${CQA}/references/tool-comparison.md"

command -v jq > /dev/null 2>&1 || die "jq is required"

[ -f "${CATALOG}" ]  || die "catalog not found: ${CATALOG}"
[ -f "${UPSTREAM}" ] || die "upstream versions not found: ${UPSTREAM}"
[ -f "${TARGET}" ]   || die "target not found: ${TARGET}"

# ── the region body ───────────────────────────────────────────────────────────
#
# One row per Composer package the catalog installs on the Drupal stack. The npm half of
# the catalog is deliberately absent: this table is the PHP ecosystem, and an npm package
# has no Packagist record to compare against.
#
# `Installed as` is the catalog's constraint, so the row cannot disagree with the
# installer without the diff catching it. `Upstream latest`, `PHP requirement` and
# `Checked` come from upstream-versions.json, which is the only place in the repo allowed
# to hold a fact about somebody else's release.
#
# A package with no upstream record prints `not recorded` rather than being dropped. A
# dropped row is a table that quietly stops describing what the installer installs;
# check-claims.sh R5 fails on the marker.
build_region() {
    printf '<!-- Generated from skills/code-quality-audit/schema/tool-catalog.json (package and\n'
    printf '     constraint) and schema/upstream-versions.json (version, PHP floor, checked date).\n'
    printf '     Do not modify this region directly; edit those two files and run `make tool-versions`.\n'
    printf '     `make claims` fails when this region and the schemas disagree. -->\n'
    printf '\n'
    printf '| Tool | Package | Installed as | Upstream latest | PHP requirement | Checked |\n'
    printf '|---|---|---|---|---|---|\n'
    jq -r --slurpfile up "${UPSTREAM}" '
        ($up[0].packages // {}) as $u
        | .tools | to_entries[]
        | select(.value.stack == "drupal")
        | .key as $id
        | .value.packages[]?
        | .name as $name
        | ($u[$name] // null) as $rec
        | ( (.constraint // "") | if . == "" then "_(unconstrained)_" else "`" + . + "`" end ) as $con
        | ( if $rec == null then "not recorded"
            elif ($rec.version // null) == null then "no tagged release"
            else $rec.version + " (" + ($rec.released // "?") + ")" end ) as $ver
        | ( if $rec == null then "not recorded"
            elif ($rec.php // null) == null then "not declared"
            else "`" + ($rec.php | gsub("\\|"; "\\|")) + "`" end ) as $php
        | ( if $rec == null then "not recorded" else ($rec.checked // "not recorded") end ) as $chk
        | "| `" + $id + "` | " + $name + " | " + $con + " | " + $ver + " | " + $php + " | " + $chk + " |"
    ' "${CATALOG}"
}

TOOL_COUNT="$(jq -r '.tools | length' "${CATALOG}" 2> /dev/null)" || die "catalog is not valid JSON"
[ "${TOOL_COUNT:-0}" -gt 0 ] 2> /dev/null \
    || die "the catalog holds zero tools, so there is nothing to generate. A generator that found nothing to generate has not succeeded."

NEW_BODY="$(build_region)"
ROW_COUNT="$(printf '%s\n' "${NEW_BODY}" | grep -c '^| `' || true)"
[ "${ROW_COUNT:-0}" -gt 0 ] \
    || die "the catalog holds no Drupal-stack Composer package, so the table would be empty. That is a failure, not an empty table."

NEW_DIGEST="$(region_digest "${NEW_BODY}")"

region_load "${TARGET}" "${BEGIN_MARKER}" "${END_PREFIX}" "${END_SUFFIX}" || die "${REGION_ERROR}"

case "${MODE}" in
    check)
        FAILED=""
        if [ "${REGION_DIGEST}" != "${REGION_RECORDED}" ]; then
            FAILED="checksum"
            printf 'gen-tool-versions: the region no longer matches its own checksum.\n' >&2
            printf '  recorded: %s\n  computed: %s\n' "${REGION_RECORDED}" "${REGION_DIGEST}" >&2
            printf '  Somebody edited inside the generated region. Move the edit into the two\n' >&2
            printf '  schema files, or into the prose outside the markers, then run make tool-versions.\n' >&2
        fi
        if [ "${REGION_BODY}" != "${NEW_BODY}" ]; then
            FAILED="${FAILED:+${FAILED} and }content"
            printf 'gen-tool-versions: the committed table differs from what the schemas generate.\n' >&2
            diff <(printf '%s\n' "${REGION_BODY}") <(printf '%s\n' "${NEW_BODY}") >&2 || true
        fi
        [ -z "${FAILED}" ] || exit 1
        printf 'gen-tool-versions: the version table matches the schemas (%s rows), and its checksum holds.\n' "${ROW_COUNT}"
        exit 0
        ;;
    force)
        region_replace "${TARGET}" "${REGION_BEGIN_NO}" "${REGION_END_NO}" \
            "${NEW_BODY}" "${NEW_DIGEST}" "${END_PREFIX}" "${END_SUFFIX}" \
            || die "could not write ${TARGET}"
        printf 'gen-tool-versions: version table regenerated, %s rows (--force).\n' "${ROW_COUNT}"
        exit 0
        ;;
    write)
        if [ "${REGION_DIGEST}" != "${REGION_RECORDED}" ]; then
            printf 'gen-tool-versions: REFUSING to regenerate.\n' >&2
            printf '  The committed region does not match the checksum on its end marker, which\n' >&2
            printf '  means it was edited by hand. Regenerating would destroy that edit silently.\n' >&2
            printf '  recorded: %s\n  computed: %s\n\n' "${REGION_RECORDED}" "${REGION_DIGEST}" >&2
            printf '  Move the edit into schema/tool-catalog.json or schema/upstream-versions.json,\n' >&2
            printf '  or into the prose outside the markers. Then run gen-tool-versions.sh --force.\n' >&2
            exit 1
        fi
        region_replace "${TARGET}" "${REGION_BEGIN_NO}" "${REGION_END_NO}" \
            "${NEW_BODY}" "${NEW_DIGEST}" "${END_PREFIX}" "${END_SUFFIX}" \
            || die "could not write ${TARGET}"
        printf 'gen-tool-versions: version table regenerated, %s rows.\n' "${ROW_COUNT}"
        exit 0
        ;;
esac
