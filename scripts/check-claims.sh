#!/usr/bin/env bash
# Fails when a claim recorded in code-quality-tools/ disagrees with the in-repo authority
# for that claim.
#
# `make manifests` compares plugin.json against marketplace.json — two internal files
# agreeing with each other. Nothing compared a documented claim against the thing it
# describes, and the tree carried the consequences: an unconstrained `drupal/coder` in
# five documented install blocks while the catalog pins ^9.0; a package called
# "deprecated", which is a state Composer does not have; one table stamped
# `(December 2025)` standing over rows that had since gone wrong; and five different
# phpstan levels across twenty sites.
#
# Five rules, each deriving its authority from a file that already exists. No rule reads a
# register of claims: a register only catches the claims somebody remembered to register,
# and this repo has already recorded that relocating a hardcoded list is not removing it.
#
#   R1  a documented install carries the constraint schema/tool-catalog.json pins
#   R2  no bare month-year stamp; dated claims carry a per-row `checked YYYY-MM-DD`
#   R3  no maintenance judgement about a package that Composer cannot express
#   R4  one phpstan level: docs name the config field, code agrees with the shipped value
#   R5  the generated version table matches the two schema files (scripts/gen-tool-versions.sh)
#
# Exit codes:
#   0  every rule compared something and found no disagreement
#   1  a disagreement
#   2  a usage error
#   4  UNMEASURED — a rule compared nothing, or an authority was missing. Its own code,
#      not folded into 1, so a caller can tell "I found a problem" from "I could not
#      look". pytest and golangci-lint both reserve a code for collected-nothing; the
#      gate_path_resolution sibling reserved 4 for the same meaning in this plugin's
#      gates, and this follows it rather than inventing a second vocabulary.
#
# Offline by default and deterministic: CI must not fail on a green tree because
# Packagist was slow. `--upstream` is the deliberate refresh a person runs, the same
# posture as `make lint-baseline`. Nothing in make calls it.
#
# Discovery mirrors check-outputs.sh: git ls-files inside a work tree, pruned find
# outside one. Consequence, same as its siblings: a new file is not checked until it is
# `git add`ed.
#
# Written for bash 3.2 so macOS and CI agree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
UPSTREAM_MODE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root)     ROOT="${2-}"; shift 2 ;;
        --root=*)   ROOT="${1#--root=}"; shift ;;
        --upstream) UPSTREAM_MODE=1; shift ;;
        -h|--help)  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'check-claims: unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

PLUGIN_DIR="code-quality-tools"
CQA="${PLUGIN_DIR}/skills/code-quality-audit"
CATALOG="${ROOT}/${CQA}/schema/tool-catalog.json"
UPSTREAM_JSON="${ROOT}/${CQA}/schema/upstream-versions.json"
TEMPLATE="${ROOT}/${CQA}/templates/drupal/phpstan.neon"
GEN="${SCRIPT_DIR}/gen-tool-versions.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

FAILURES=0
UNMEASURED=0
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL  %s\n' "$1"; }
unmeasured() { UNMEASURED=$((UNMEASURED + 1)); printf 'UNMEASURED  %s\n' "$1"; }

command -v jq > /dev/null 2>&1 || { printf 'check-claims: jq is required\n' >&2; exit 2; }

# ── authorities ───────────────────────────────────────────────────────────────
#
# Every authority is a file that already exists for another reason. When one is missing
# the answer is UNMEASURED, never a pass: a rule with no authority has not agreed with
# anything, it has merely failed to disagree.
if [ ! -f "${CATALOG}" ]; then
    unmeasured "the tool catalog is missing (${CATALOG}), so R1 and R5 have no authority. Nothing was compared."
fi
if [ ! -f "${UPSTREAM_JSON}" ]; then
    unmeasured "the upstream version record is missing (${UPSTREAM_JSON}), so R5 has no authority. Nothing was compared."
fi

SHIPPED_LEVEL=""
if [ -f "${TEMPLATE}" ]; then
    SHIPPED_LEVEL="$(grep -hE '^[[:space:]]*level:[[:space:]]*[0-9]+' "${TEMPLATE}" 2>/dev/null \
        | head -1 | sed -E 's/^[[:space:]]*level:[[:space:]]*([0-9]+).*/\1/')"
fi
if [ -z "${SHIPPED_LEVEL}" ]; then
    unmeasured "the phpstan template (${TEMPLATE}) states no numeric level, so R4 has no authority to compare against."
fi

PKGMAP="${TMP}/packages.tsv"
if [ -f "${CATALOG}" ]; then
    jq -r '.tools | to_entries[] | .value.packages[]? | .name + "\t" + (.constraint // "")' \
        "${CATALOG}" 2>/dev/null | sort -u > "${PKGMAP}" || : > "${PKGMAP}"
else
    : > "${PKGMAP}"
fi
PKG_COUNT="$(wc -l < "${PKGMAP}" | tr -d ' ')"

# ── discovery ─────────────────────────────────────────────────────────────────
FILELIST="${TMP}/files.txt"
if git -C "${ROOT}" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    git -C "${ROOT}" ls-files -- "${PLUGIN_DIR}" > "${FILELIST}" 2>/dev/null || : > "${FILELIST}"
else
    ( cd "${ROOT}" && find "${PLUGIN_DIR}" \
        \( -name node_modules -o -name vendor -o -name .git \) -prune -o \
        -type f -print ) > "${FILELIST}" 2>/dev/null || : > "${FILELIST}"
fi

# The files a rule can read: prose, templates a user copies, and the scripts that print
# instructions. A remediation string echoed by a gate is an install instruction handed to
# a user, so a shell script is scanned exactly like a markdown file.
SCANLIST="${TMP}/scan.txt"
grep -E '\.(md|sh|yml|yaml|json|neon)$' "${FILELIST}" > "${SCANLIST}" || : > "${SCANLIST}"
SCAN_COUNT="$(wc -l < "${SCANLIST}" | tr -d ' ')"
if [ "${SCAN_COUNT}" -eq 0 ]; then
    unmeasured "no tracked file was found under ${PLUGIN_DIR}/. Nothing was compared."
fi

# Absolute paths, one per line, for the rules that grep whole files.
abs() { sed "s|^|${ROOT}/|" "$1"; }

# A path is exempt from the prose rules when it is a spec (a spec must be able to name the
# value it asserts), or a CHANGELOG (a changelog records what was believed then, and the
# epic put rewriting one out of scope).
is_exempt_path() {
    case "$1" in
        */tests/*|*-spec.sh|*-spec.mjs) return 0 ;;
        */CHANGELOG.md|CHANGELOG.md)    return 0 ;;
        *) return 1 ;;
    esac
}

echo "check-claims: ${SCAN_COUNT} tracked files under ${PLUGIN_DIR}/, ${PKG_COUNT} packages in the catalog"
echo ""

# ── R1: a documented install carries the catalog's constraint ─────────────────
#
# An install context is a line naming `composer require` or `npm install`, plus the lines
# it continues onto through a trailing backslash. That covers the fenced blocks in the
# docs, the multi-line block in the CI template, and a one-line remediation string echoed
# by a gate, without needing to know which kind of file it is reading.
#
# Lines inside a generated region are skipped: that region is checked by its generator
# (R5), and text-matching a generated table would be checking the same bytes twice under
# a weaker rule.
R1_COMPARISONS=0
R1_OUT="${TMP}/r1.txt"
R1LIST="${TMP}/r1-files.txt"
: > "${R1LIST}"
while IFS= read -r rel; do
    is_exempt_path "${rel}" || printf '%s\n' "${rel}" >> "${R1LIST}"
done < "${SCANLIST}"
if [ "${PKG_COUNT}" -gt 0 ] && [ -s "${R1LIST}" ]; then
    abs "${R1LIST}" > "${TMP}/scan.abs"
    # shellcheck disable=SC2046
    awk -f - "${PKGMAP}" $(cat "${TMP}/scan.abs") > "${R1_OUT}" <<'AWK'
FNR == NR {
    split($0, a, "\t"); pkg[a[1]] = a[2]; next
}
FNR == 1 { active = 0; gen = 0 }
/<!-- BEGIN GENERATED:/ { gen = 1 }
/<!-- END GENERATED:/   { gen = 0; next }
gen { next }
{
    if ($0 ~ /composer require/ || $0 ~ /npm install/) active = 1
    if (active) {
        for (p in pkg) {
            start = 1
            while ((idx = index(substr($0, start), p)) > 0) {
                pos = start + idx - 1
                before = (pos > 1) ? substr($0, pos - 1, 1) : ""
                rest = substr($0, pos + length(p))
                after = substr(rest, 1, 1)
                # Not an occurrence when it is part of a longer token or a path segment:
                # vendor/drupal/coder/src is a path, phpstan/phpstan-deprecation-rules is
                # a different package.
                if (before ~ /[A-Za-z0-9_.\/-]/ || after ~ /[A-Za-z0-9_.-]/) { start = pos + 1; continue }

                con = ""
                if (after == ":") {
                    con = substr(rest, 2)
                    sub(/[[:space:]\\"'\047,`)<>].*$/, "", con)
                } else if (after == " " || after == "\t") {
                    tail = rest
                    sub(/^[[:space:]]+/, "", tail)
                    tok = tail
                    sub(/[[:space:]\\"'\047,`)<>].*$/, "", tok)
                    if (tok ~ /^[\^~><=*]/ || tok ~ /^[0-9]/ || tok ~ /^dev-/) con = tok
                }
                printf "%s\t%s\t%s\t%s\t%s\n", FILENAME, FNR, p, pkg[p], con
                start = pos + 1
            }
        }
    }
    if (active && $0 !~ /\\[[:space:]]*$/) active = 0
}
AWK
    while IFS="$(printf '\t')" read -r f n p want got; do
        R1_COMPARISONS=$((R1_COMPARISONS + 1))
        rel="${f#"${ROOT}"/}"
        if [ -z "${want}" ] || [ "${want}" = "*" ]; then
            # The catalog states no opinion: an npm package, or drupal/core-dev, which is
            # a metapackage locked to the site's own Drupal minor. A doc that omits a
            # constraint there agrees with the catalog. A doc that states a DIFFERENT one
            # still fails below.
            [ -z "${got}" ] && continue
            [ "${got}" = "${want}" ] && continue
            fail "R1 ${rel}:${n} installs ${p} at ${got}, while the catalog deliberately states '${want:-none}'."
        elif [ -z "${got}" ]; then
            fail "R1 ${rel}:${n} installs ${p} with no constraint, while the catalog pins ${want}. An unconstrained dependency is a decision deferred onto whoever installs next."
        elif [ "${got}" != "${want}" ]; then
            fail "R1 ${rel}:${n} installs ${p} at ${got}, while the catalog pins ${want}."
        fi
    done < "${R1_OUT}"
fi
if [ "${R1_COMPARISONS}" -eq 0 ]; then
    unmeasured "R1 found no documented install of any catalogued package. Nothing was compared, so nothing passed."
else
    printf 'R1  package constraints:    %s comparisons\n' "${R1_COMPARISONS}"
fi

# ── R2: no bare month-year stamp ──────────────────────────────────────────────
#
# A stamp like `(December 2025)` or `(Dec 2025)` is the form that ages badly: it stood
# over a six-row table in which two rows had gone wrong, and nothing said which rows had
# been re-read. The replacement form is `checked YYYY-MM-DD`, one per row, which is what
# the generated table carries.
#
# Age is REPORTED, never failed. An age threshold fails a green tree with no commit
# behind it, so what is enforced here is the form; the oldest date is printed so the
# drift is visible before somebody acts on it.
R2_COMPARISONS=0
MONTHS='January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec'
while IFS= read -r rel; do
    case "${rel}" in *.md) ;; *) continue ;; esac
    is_exempt_path "${rel}" && continue
    R2_COMPARISONS=$((R2_COMPARISONS + 1))
    hits="$(grep -nHE "\((${MONTHS})[[:space:]]+[0-9]{4}\)" "${ROOT}/${rel}" 2>/dev/null | grep -v '<!-- ' || true)"
    if [ -n "${hits}" ]; then
        while IFS= read -r hit; do
            [ -n "${hit}" ] || continue
            fail "R2 ${hit#"${ROOT}"/} carries a bare month-year stamp. Use a per-row 'checked YYYY-MM-DD' instead, so the next drift shows up one row at a time."
        done <<EOF
${hits}
EOF
    fi
done < "${SCANLIST}"
if [ "${R2_COMPARISONS}" -eq 0 ]; then
    unmeasured "R2 scanned no markdown file. Nothing was compared, so nothing passed."
else
    printf 'R2  dated claims:            %s files compared\n' "${R2_COMPARISONS}"
    OLDEST="$(grep -rhoE 'checked [0-9]{4}-[0-9]{2}-[0-9]{2}' "${ROOT}/${CQA}" 2>/dev/null \
        | sed 's/checked //' | sort | head -1)"
    [ -z "${OLDEST}" ] || printf '    oldest checked date on record: %s (reported, never failed)\n' "${OLDEST}"
fi

# ── R3: no maintenance judgement Composer cannot express ──────────────────────
#
# `abandoned` is the only formal Composer package state: a composer.json field, enforced
# by `composer audit`. Packagist has no deprecated flag, and in PHP `deprecated` marks a
# symbol, not a package. So `deprecated`, `unmaintained` and `no longer maintained` beside
# a package name are always refused; `abandoned` is allowed only on a line that also
# carries the date somebody read the flag, because that is a fact with a source.
#
# Matched on the word `deprecated`, never on `deprecation`, so
# phpstan/phpstan-deprecation-rules does not trip it.
#
# TWO subjects, because people write a tool's name two ways.
#
#   a `vendor/package` token  — the whole line is refused if it carries a judgement.
#   a BARE tool name          — refused when the judgement is attached to the name.
#
# The bare half exists because the rule could not otherwise catch its own motivating
# case. All four sites this criterion was written to correct called the tool plain
# `drupal-check`, with no vendor prefix, and a rule that only reads lines carrying a
# slash walked straight past every one of them: `mglaman/drupal-check is deprecated.`
# failed, `The drupal-check tool is deprecated.` passed. That is the defect class this
# whole epic exists to remove, so it is not one this check gets to carry.
#
# The recognised names are DERIVED, never registered — a register only catches the names
# somebody remembered to register, which is this repo's own recorded mistake. The source
# is the two schema files that already exist: the catalog's tool keys, the basename of
# every Composer package name in the catalog and in the upstream record, and every
# unscoped npm name as written.
#
# Two deliberate subtractions, both about false positives rather than about taste:
#   - a scoped npm name (`@scope/name`) contributes nothing. People write it whole, and
#     the vendor/package half already sees it. This is what keeps `react`, `node`, `cli`
#     and `globals` — the basenames of @types/react, @types/node, @socketsecurity/cli and
#     @jest/globals — out of a rule that reads English prose.
#   - a name under four characters is too generic to carry a judgement on its own.
#
# And the bare half only fires when the judgement is ATTACHED to the name: the two
# separated by at most four filler words, in either order. Whole-line matching on a bare
# name would fail `"run rector", "auto-fix deprecated code"`, which is prose about
# deprecated code and not a judgement about Rector.
R3_COMPARISONS=0
PKGTOKEN='[a-z0-9][a-z0-9_.-]*/[a-z0-9][a-z0-9_.-]*'

NAMES_RAW="${TMP}/names-raw.txt"
: > "${NAMES_RAW}"
if [ -f "${CATALOG}" ]; then
    jq -r '.tools | keys[]' "${CATALOG}" 2>/dev/null >> "${NAMES_RAW}"
    jq -r '.tools[].packages[]?.name' "${CATALOG}" 2>/dev/null >> "${NAMES_RAW}"
fi
if [ -f "${UPSTREAM_JSON}" ]; then
    jq -r '.packages | keys[]' "${UPSTREAM_JSON}" 2>/dev/null >> "${NAMES_RAW}"
fi
BARENAMES="${TMP}/barenames.txt"
awk '{
    if ($0 ~ /^@/) next
    n = $0; sub(/^[^\/]*\//, "", n)
    if (n ~ /\// || length(n) < 4) next
    print n
}' "${NAMES_RAW}" 2>/dev/null | sort -u > "${BARENAMES}"

# Each name becomes a case-insensitive literal: docs write PHPStan and Rector, and a
# name at the start of a sentence is capitalised. The JUDGEMENT stays case-sensitive, so
# `E_USER_DEPRECATED` in a phpstan.neon comment is not a claim about a package.
BARE_ALT="$(awk '{
    out = ""
    for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c ~ /[a-z]/)      out = out "[" c toupper(c) "]"
        else if (c == ".")    out = out "\\."
        else                  out = out c
    }
    print out
}' "${BARENAMES}" 2>/dev/null | paste -sd'|' -)"

GAPW='(is|are|was|were|has|have|had|been|being|be|now|currently|still|itself|also|the|a|an|this|it|its|tool|package|project|library|module|extension|binary|command|considered|marked|reportedly|apparently|officially|seems|appears|long|since|and|or)'
JUDGE_BAD='(deprecated|unmaintained|no[^A-Za-z0-9]+longer[^A-Za-z0-9]+maintained)'
JUDGE_ABA='(abandoned)'
BARE_BAD=""
BARE_ABA=""
if [ -n "${BARE_ALT}" ]; then
    BARE_BAD="(^|[^A-Za-z0-9_])(${BARE_ALT})([^A-Za-z0-9]+${GAPW}){0,4}[^A-Za-z0-9]+${JUDGE_BAD}"
    BARE_BAD="${BARE_BAD}|(^|[^A-Za-z0-9])${JUDGE_BAD}([^A-Za-z0-9]+${GAPW}){0,4}[^A-Za-z0-9]+(${BARE_ALT})([^A-Za-z0-9_]|$)"
    BARE_ABA="(^|[^A-Za-z0-9_])(${BARE_ALT})([^A-Za-z0-9]+${GAPW}){0,4}[^A-Za-z0-9]+${JUDGE_ABA}"
    BARE_ABA="${BARE_ABA}|(^|[^A-Za-z0-9])${JUDGE_ABA}([^A-Za-z0-9]+${GAPW}){0,4}[^A-Za-z0-9]+(${BARE_ALT})([^A-Za-z0-9_]|$)"
else
    unmeasured "R3 derived no recognised tool name from the schema files, so its bare-name half compared nothing. A rule that only reads vendor/package tokens cannot see the wording that motivated it."
fi

R3_BARE_COMPARISONS=0
while IFS= read -r rel; do
    is_exempt_path "${rel}" && continue
    lines="$(grep -nHE "${PKGTOKEN}" "${ROOT}/${rel}" 2>/dev/null || true)"
    if [ -n "${lines}" ]; then
        while IFS= read -r line; do
            [ -n "${line}" ] || continue
            R3_COMPARISONS=$((R3_COMPARISONS + 1))
            body="${line#*:*:}"
            if printf '%s' "${body}" | grep -qE '\bdeprecated\b|\bunmaintained\b|no longer maintained'; then
                fail "R3 ${line#"${ROOT}"/} calls a package deprecated or unmaintained. Neither is a state Composer has. State the checkable fact instead — the constraint it pins, or its last release with the date you read it."
            elif printf '%s' "${body}" | grep -qE '\babandoned\b'; then
                if ! printf '%s' "${body}" | grep -qE 'checked [0-9]{4}-[0-9]{2}-[0-9]{2}'; then
                    fail "R3 ${line#"${ROOT}"/} calls a package abandoned with no checked date. Abandoned IS a Composer field, so the claim is allowed — with the date somebody read it."
                fi
            fi
        done <<EOF
${lines}
EOF
    fi

    # The bare-name half. A line already carrying a vendor/package token was judged
    # above, so it is skipped here rather than failed twice for one sentence.
    #
    # The cheap word test runs first. The name alternation is a long regex and most
    # files carry no judgement word at all, so this is a filter, not a second rule: a
    # file it excludes could not have matched the expensive pattern either.
    [ -n "${BARE_BAD}" ] || continue
    grep -qE 'deprecated|unmaintained|maintained|abandoned' "${ROOT}/${rel}" 2>/dev/null || continue
    bare="$(grep -nHE "${BARE_BAD}|${BARE_ABA}" "${ROOT}/${rel}" 2>/dev/null || true)"
    [ -n "${bare}" ] || continue
    while IFS= read -r line; do
        [ -n "${line}" ] || continue
        body="${line#*:*:}"
        printf '%s' "${body}" | grep -qE "${PKGTOKEN}" && continue
        R3_BARE_COMPARISONS=$((R3_BARE_COMPARISONS + 1))
        if printf '%s' "${body}" | grep -qE "${BARE_BAD}"; then
            fail "R3 ${line#"${ROOT}"/} calls a tool deprecated or unmaintained by its bare name. Neither is a state Composer has, and dropping the vendor prefix does not make it one. State the checkable fact instead — the constraint it pins, or its last release with the date you read it."
        elif ! printf '%s' "${body}" | grep -qE 'checked [0-9]{4}-[0-9]{2}-[0-9]{2}'; then
            fail "R3 ${line#"${ROOT}"/} calls a tool abandoned by its bare name, with no checked date. Abandoned IS a Composer field, so the claim is allowed — with the date somebody read it."
        fi
    done <<EOF
${bare}
EOF
done < "${SCANLIST}"
if [ "${R3_COMPARISONS}" -eq 0 ]; then
    unmeasured "R3 found no line naming a package. Nothing was compared, so nothing passed."
else
    BARE_COUNT="$(wc -l < "${BARENAMES}" | tr -d ' ')"
    printf 'R3  maintenance judgements:  %s lines carrying a vendor/package token, plus %s bare-name judgement(s), against %s names derived from the schema files\n' \
        "${R3_COMPARISONS}" "${R3_BARE_COMPARISONS}" "${BARE_COUNT}"
fi

# ── R4: one phpstan level ─────────────────────────────────────────────────────
#
# Two sub-rules, because a command line and a config value fail differently.
#
# R4a — a `--level` on a command line the plugin ships to be RUN (its own commands, and
# the CI templates a user copies) is refused outright. Not because the number is wrong,
# but because a command-line level silently overrides a placed phpstan.neon: a user who
# copied the template got level 5 in the file and level 8 on the command line, and the
# command line won without saying so. Those sites read .code-quality.json's phpstan.level.
#
# R4b — every other numeric level literal, in prose, in a script, in a JSON example, must
# equal the value templates/drupal/phpstan.neon ships. Something has to carry the default,
# and a doc describing the gate's fallback is accurate rather than a second opinion. What
# this forbids is a SECOND value, which is what "the count of distinct hardcoded levels is
# 0" means once the authority is subtracted: five values were live across twenty sites.
R4_COMPARISONS=0
LEVEL_RE='(--level[= ]+[0-9]+|^[[:space:]]*level:[[:space:]]*[0-9]+|"level"[[:space:]]*:[[:space:]]*[0-9]+|LEVEL:-[0-9]+|\{[[:space:]]*level:[[:space:]]*[0-9]+)'
CLI_LEVEL_RE='--level[= ]+[0-9]+'
if [ -n "${SHIPPED_LEVEL}" ]; then
    while IFS= read -r rel; do
        is_exempt_path "${rel}" && continue
        [ "${ROOT}/${rel}" = "${TEMPLATE}" ] && continue
        hits="$(grep -nHE "${LEVEL_RE}" "${ROOT}/${rel}" 2>/dev/null || true)"
        [ -n "${hits}" ] || continue
        while IFS= read -r hit; do
            [ -n "${hit}" ] || continue
            R4_COMPARISONS=$((R4_COMPARISONS + 1))
            body="${hit#*:*:}"
            got="$(printf '%s' "${body}" | grep -oE "${LEVEL_RE}" | head -1 | grep -oE '[0-9]+$')"
            runnable=1
            case "${rel}" in
                */commands/*.md|*/templates/ci/*) ;;
                *) runnable=0 ;;
            esac
            if [ "${runnable}" -eq 1 ] && printf '%s' "${body}" | grep -qE "${CLI_LEVEL_RE}"; then
                fail "R4a ${hit#"${ROOT}"/} passes --level on a command line this plugin ships to be run. A command-line level overrides a placed phpstan.neon silently. Read .code-quality.json's phpstan.level instead."
            elif [ "${got}" != "${SHIPPED_LEVEL}" ]; then
                fail "R4b ${hit#"${ROOT}"/} states phpstan level ${got}, while templates/drupal/phpstan.neon ships ${SHIPPED_LEVEL}. One source of truth means one value; point at .code-quality.json's phpstan.level rather than choosing a second."
            fi
        done <<EOF
${hits}
EOF
    done < "${SCANLIST}"
    # A site that READS the field is a comparison too: it is the form the rule asks for,
    # and counting it is what keeps R4 measurable once every stray literal is gone.
    POINTERS="$(grep -rlE 'phpstan\.level' "${ROOT}/${PLUGIN_DIR}" 2>/dev/null | wc -l | tr -d ' ')"
    R4_COMPARISONS=$((R4_COMPARISONS + POINTERS))
fi
if [ "${R4_COMPARISONS}" -eq 0 ]; then
    unmeasured "R4 found no phpstan level site at all, and no site naming the config field. Nothing was compared, so nothing passed."
else
    printf 'R4  phpstan level:           %s sites compared against the shipped level %s\n' "${R4_COMPARISONS}" "${SHIPPED_LEVEL}"
fi

# ── R5: the generated version table ───────────────────────────────────────────
#
# Generate-then-diff, the shape terraform-docs --output-check and cog -c use. The table's
# constraint column IS the catalog's constraint, so criterion 9's "the coder row agrees
# with what the installer requires" is a comparison the generator performs rather than
# something a reader checks.
#
# The half a generator cannot state: a catalogued package with no upstream record. Its row
# prints `not recorded`, and that is a failure here rather than a row somebody skims past.
R5_COMPARISONS=0
if [ -f "${CATALOG}" ] && [ -f "${UPSTREAM_JSON}" ] && [ -x "${GEN}" ]; then
    GENOUT="$(bash "${GEN}" --root "${ROOT}" --check 2>&1)"; GENRC=$?
    R5_COMPARISONS="$(jq -r '[.tools[] | select(.stack == "drupal") | .packages[]?] | length' "${CATALOG}" 2>/dev/null || echo 0)"
    if [ "${GENRC}" -ne 0 ]; then
        fail "R5 the generated version table disagrees with the schema files it is generated from. Run 'make tool-versions' after editing the catalog or the upstream record."
        printf '%s\n' "${GENOUT}" | sed 's/^/      /'
    fi
    MISSING="$(jq -r --slurpfile up "${UPSTREAM_JSON}" '
        ($up[0].packages // {}) as $u
        | [.tools[] | select(.stack == "drupal") | .packages[]? | .name]
        | unique[] | select($u[.] == null)' "${CATALOG}" 2>/dev/null || true)"
    if [ -n "${MISSING}" ]; then
        while IFS= read -r m; do
            [ -n "${m}" ] || continue
            fail "R5 ${m} is installed by the catalog and has no record in schema/upstream-versions.json, so the version table cannot state anything about it. Add it, or run check-claims.sh --upstream."
        done <<EOF
${MISSING}
EOF
    fi
fi
if [ "${R5_COMPARISONS}" -eq 0 ]; then
    unmeasured "R5 generated no version-table row. Nothing was compared, so nothing passed."
else
    printf 'R5  generated version table: %s rows compared\n' "${R5_COMPARISONS}"
fi

# ── --upstream: the deliberate refresh ────────────────────────────────────────
#
# The one thing this check cannot settle offline is whether a recorded upstream value is
# still what upstream publishes. That is why every record carries the date it was read.
# This mode re-reads them. It is not wired into make and never runs in CI: a check that
# needs the network is a check that fails a green tree when the network is down.
#
# It compares the version, the PHP requirement AND the abandoned flag. The PHP floor is
# there deliberately: two stated upstream facts in this epic failed re-verification, and
# one of them was a PHP floor, not a version.
if [ "${UPSTREAM_MODE}" -eq 1 ]; then
    echo ""
    echo "── --upstream: re-reading Packagist ──"
    command -v curl > /dev/null 2>&1 || { printf 'check-claims: curl is required for --upstream\n' >&2; exit 2; }
    for name in $(jq -r '.packages | keys[]' "${UPSTREAM_JSON}"); do
        rec="$(jq -r --arg n "${name}" '.packages[$n] | [.version, .php, .abandoned, .checked] | @tsv' "${UPSTREAM_JSON}")"
        r_ver="$(printf '%s' "${rec}" | cut -f1)"
        r_php="$(printf '%s' "${rec}" | cut -f2)"
        body="$(curl -fsS --max-time 20 "https://repo.packagist.org/p2/${name}.json" 2>/dev/null || true)"
        if [ -z "${body}" ]; then
            fail "--upstream could not read ${name} from Packagist. That is unmeasured, not agreement."
            continue
        fi
        live="$(printf '%s' "${body}" | jq -r --arg n "${name}" '
            [ .packages[$n][] | select((.version | test("dev|alpha|beta|RC"; "i")) | not) ] | .[0]
            | [ (.version | sub("^v"; "")), (.require.php // "null"), ((.abandoned // false) | tostring) ] | @tsv')"
        l_ver="$(printf '%s' "${live}" | cut -f1)"
        l_php="$(printf '%s' "${live}" | cut -f2)"
        l_aba="$(printf '%s' "${live}" | cut -f3)"
        [ "${r_ver}" = "null" ] && r_ver=""
        [ "${r_php}" = "null" ] && r_php=""
        [ "${l_php}" = "null" ] && l_php=""
        if [ -n "${l_ver}" ] && [ "${r_ver}" != "${l_ver}" ]; then
            fail "--upstream ${name}: recorded ${r_ver:-none}, upstream publishes ${l_ver}."
        fi
        if [ "${r_php}" != "${l_php}" ]; then
            fail "--upstream ${name}: recorded PHP requirement '${r_php}', upstream declares '${l_php}'."
        fi
        if [ "${l_aba}" != "false" ]; then
            fail "--upstream ${name}: upstream now marks this package abandoned. That IS a Composer state, so it can be recorded — with today's date."
        fi
        printf '    %-40s recorded %-10s upstream %-10s\n' "${name}" "${r_ver:-none}" "${l_ver:-none}"
    done
fi

# ── verdict ───────────────────────────────────────────────────────────────────
echo ""
if [ "${UNMEASURED}" -gt 0 ]; then
    printf 'check-claims: UNMEASURED — nothing was compared by %s rule(s). A check that compared nothing has not passed.\n' "${UNMEASURED}" >&2
    exit 4
fi
if [ "${FAILURES}" -gt 0 ]; then
    printf 'check-claims: %s claim(s) disagree with the authority for them.\n' "${FAILURES}" >&2
    exit 1
fi
printf 'check-claims: every rule compared something, and every claim agrees with its authority.\n'
exit 0
