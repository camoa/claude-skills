#!/usr/bin/env bash
# shellcheck shell=bash
#
# The marked, banner-carrying, checksummed generated region — the mechanism, once.
#
# scripts/gen-setup-doc.sh introduced it for setup.md's tool inventory and recorded why
# each of its three parts exists (markers so the region has a boundary, an in-region
# banner so a reader inside it learns it is generated, a checksum on the end marker so
# the write path refuses instead of overwriting a hand edit). scripts/gen-tool-versions.sh
# needs the identical mechanism for tool-comparison.md's version table.
#
# Copying it would have been the repo's own recorded mistake wearing a new name: four
# hardcoded package lists disagreeing with each other is what the catalog exists to end,
# and two copies of a checksum protocol drift the same way. So the primitives live here
# and both generators source them. What stays in each generator is the part that is
# genuinely its own: what the region CONTAINS, and what it says when it refuses.
#
# Everything here is bash 3.2, because the scripts that source it are.

# sha256 of a string, without a trailing newline, whichever tool the machine has.
region_digest() {
    if command -v sha256sum > /dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    else
        printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    fi
}

# region_load FILE BEGIN_MARKER END_PREFIX END_SUFFIX
#
# On success sets REGION_BEGIN_NO, REGION_END_NO, REGION_RECORDED (the digest written on
# the end marker), REGION_BODY (what lies between the markers, marker lines excluded) and
# REGION_DIGEST (the digest of REGION_BODY as committed). On failure sets REGION_ERROR and
# returns 1.
#
# An ABSENT checksum is a failure and not "a region we will adopt". That is exactly the
# state a hand edit produces when somebody deletes the part of the marker they did not
# understand, and adopting it would silently bless the edit the checksum exists to catch.
# REGION_* are this function's return values, read by the caller after it returns. The
# linter cannot see that from inside the file that sets them.
# shellcheck disable=SC2034
region_load() {
    local file="$1" begin="$2" end_prefix="$3" end_suffix="$4"
    local end_line

    REGION_ERROR=""; REGION_BEGIN_NO=""; REGION_END_NO=""
    REGION_RECORDED=""; REGION_BODY=""; REGION_DIGEST=""

    if [ ! -r "${file}" ]; then
        REGION_ERROR="${file} is not readable"
        return 1
    fi

    if ! grep -qxF "${begin}" "${file}"; then
        REGION_ERROR="the begin marker is missing from ${file}. Nothing bounds the generated region, so nothing can be generated or compared."
        return 1
    fi

    end_line="$(grep -nE "^${end_prefix}[0-9a-f]{64}${end_suffix}\$" "${file}" | head -1)"
    if [ -z "${end_line}" ]; then
        if grep -qE "^${end_prefix}" "${file}"; then
            REGION_ERROR="the end marker in ${file} carries no 64-hex sha256 digest. That is the state a hand edit produces when somebody deletes the part they did not understand, so it is a failure rather than a region to adopt."
        else
            REGION_ERROR="the end marker is missing from ${file}"
        fi
        return 1
    fi

    REGION_BEGIN_NO="$(grep -nxF "${begin}" "${file}" | head -1 | cut -d: -f1)"
    REGION_END_NO="${end_line%%:*}"
    if [ "${REGION_BEGIN_NO}" -ge "${REGION_END_NO}" ]; then
        REGION_ERROR="the end marker precedes the begin marker in ${file}"
        return 1
    fi

    REGION_RECORDED="$(printf '%s' "${end_line#*:}" | sed -E "s|^${end_prefix}([0-9a-f]{64})${end_suffix}\$|\1|")"
    REGION_BODY="$(sed -n "$((REGION_BEGIN_NO + 1)),$((REGION_END_NO - 1))p" "${file}")"
    REGION_DIGEST="$(region_digest "${REGION_BODY}")"
    return 0
}

# region_replace FILE BEGIN_NO END_NO BODY DIGEST END_PREFIX END_SUFFIX
#
# The digest covers the body BETWEEN the marker lines, banner included and the markers
# themselves excluded, so writing the digest cannot change the digest.
region_replace() {
    local file="$1" begin_no="$2" end_no="$3" body="$4" digest="$5" end_prefix="$6" end_suffix="$7"
    local tmp
    tmp="$(mktemp)" || return 1
    {
        sed -n "1,${begin_no}p" "${file}"
        printf '%s\n' "${body}"
        printf '%s%s%s\n' "${end_prefix}" "${digest}" "${end_suffix}"
        sed -n "$((end_no + 1)),\$p" "${file}"
    } > "${tmp}" || { rm -f "${tmp}"; return 1; }
    mv "${tmp}" "${file}"
}
