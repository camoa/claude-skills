#!/bin/bash
# lint-check.sh - Run PHP coding standards checks (Drupal, DrupalPractice)
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Where reports go is decided in one place, and it is never inside the audited
# repository unless REPORT_DIR says so or REPORT_DIR_IN_REPO=1 asks for it.
# shellcheck source=../core/report-dir.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/report-dir.sh"
cqt_report_dir_init
cqt_announce_report_dir

# Where this project's custom code lives is answered in ONE place, for every gate.
# These two variables used to default to a web/ literal here, which pointed the gate at
# a directory detect-environment.sh had already ruled out on every docroot-layout
# (Acquia) project. Themes are custom code too and phpcs has a Drupal standard for them;
# leaving the themes path out did not make the gate narrower, it made it silently wrong —
# every standards finding in every custom theme was invisible on every run, and the gate
# reported a clean tree without them.
#
# The library sources nothing, runs nothing at load time and prints nothing, so it is
# safe above this script's own `set -e`. An explicit DRUPAL_MODULES_PATH /
# DRUPAL_THEMES_PATH still wins and is never second-guessed, which is what keeps /audit
# behaving exactly as it does today.
# shellcheck source=../core/path-resolve.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/path-resolve.sh"
cqt_resolve_drupal_paths

# Which file types phpcs is asked to read, and what it must not read at all.
#
# phpcs checks .php and .inc and nothing else unless told otherwise, so every
# invocation in this file omitting --extensions meant .module, .install, .profile,
# .theme and .engine were never scanned — the file types that only exist in Drupal, and
# where hook implementations and theme preprocess live.
#
# NO `ext/flavour` SPELLING, AND NO `js`. `module/php` was the phpcs 3 way to name a
# tokenizer; PHPCS 4.0 removed the JS and CSS tokenizers outright and with them the
# flavour syntax ("the --extensions command-line argument no longer takes a language
# 'flavour' ... remove any language part, i.e. php,inc/php becomes php,inc" — PHPCS 4.0
# User Upgrade Guide). A bare extension has always defaulted to the PHP tokenizer, so
# the bare form is the one spelling both majors accept. `js` is left out deliberately:
# phpcs 4 cannot tokenize JavaScript at all, and naming it bare would make BOTH majors
# read .js files as PHP. JavaScript standards belong to eslint, which the Next.js gates
# already run.
PHPCS_EXTENSIONS="php,module,inc,install,profile,theme,engine"

# Somebody else's code, vendored into this tree. The Next.js gates already exclude
# these; this one did not, so a node_modules tree under a custom theme produced findings
# attributed to the project. Applies to directory arguments only, which is all that the
# whole-tree scans pass.
PHPCS_IGNORE="*/node_modules/*,*/vendor/*,*/bower_components/*"

# =====================
# --changed mode (ADDITIVE): if invoked with `--changed <file>`, scope phpcs to
# the listed files and exit BEFORE the standard path below. Everything from the
# `echo "=== PHP Coding Standards Check ==="` line onward is byte-identical to
# the pre-existing script — a non-`--changed` invocation never enters this block.
# =====================
if [ "$1" == "--changed" ]; then
    CHANGED_FILE="$2"
    echo "=== PHP Coding Standards Check (changed mode) ==="
    echo "[changed mode] Scoping phpcs to files listed in: ${CHANGED_FILE}"
    echo ""

    # Lintable extensions for Drupal
    LINTABLE_EXTS="\.php$|\.module$|\.inc$|\.install$|\.profile$|\.theme$|\.engine$|\.js$"

    # What is not this project's code, expressed against THIS project's layout. The
    # list used to name web/core/, web/themes/contrib/ and web/modules/contrib/, a
    # second hardcoded layout on top of the one at the head of the file: on an Acquia
    # project every changed path begins docroot/, so core was linted as custom code and
    # nothing was excluded. The core prefix now comes from the resolved Drupal root, and
    # everything else is matched wherever it appears in the path rather than at one
    # layout's spelling of it.
    CHANGED_ROOT_PREFIX="$(cqt_drupal_root_prefix)"
    [ -n "$CHANGED_ROOT_PREFIX" ] && CHANGED_ROOT_PREFIX="${CHANGED_ROOT_PREFIX}/"
    CHANGED_EXCLUDE_RE="^(vendor/|${CHANGED_ROOT_PREFIX}core/)|(^|/)(vendor|node_modules|bower_components|contrib)/"

    # Two different empties, and filing them under one word is how this mode reported a
    # pass having scanned nothing.
    #
    #   CANDIDATES   lintable paths the caller asked about, present or not
    #   RELEVANT_FILES  the ones that are actually on disk
    #
    # A changed set with no lintable path in it (a docs-only diff) is a question the
    # gate can answer honestly: nothing to check, clean skip. A changed set that names
    # PHP files none of which exist is a question it CANNOT answer, and answering it
    # with a pass is the defect. phpcs aborts the whole run on the first missing
    # argument, writes nothing, and the empty report parses as zero findings.
    CANDIDATES=0
    RELEVANT_FILES=()
    MISSING_FILES=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if ! echo "$f" | grep -qE "$LINTABLE_EXTS"; then
            continue
        fi
        if echo "$f" | grep -qE "$CHANGED_EXCLUDE_RE"; then
            continue
        fi
        CANDIDATES=$((CANDIDATES + 1))
        if [ -e "$f" ]; then
            RELEVANT_FILES+=("$f")
        else
            MISSING_FILES+=("$f")
        fi
    done < "$CHANGED_FILE"

    CHANGED_MISSING_JSON=$(printf '%s\n' "${MISSING_FILES[@]+"${MISSING_FILES[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')

    if [ "${#RELEVANT_FILES[@]}" -eq 0 ] && [ "$CANDIDATES" -eq 0 ]; then
        echo -e "${GREEN}[SKIP]${NC} No lintable PHP files in the changed set — clean skip."
        mkdir -p "${REPORT_DIR}/lint"
        cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "tool": "phpcs",
  "mode": "changed",
  "standards": ["Drupal", "DrupalPractice"],
  "changed_file": "${CHANGED_FILE}",
  "relevant_files": 0,
  "paths_missing": [],
  "phpcs_exit": null,
  "report_usable": true,
  "errors": 0,
  "warnings": 0,
  "status": "skipped",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        exit 0
    fi

    if [ "${#RELEVANT_FILES[@]}" -eq 0 ]; then
        mkdir -p "${REPORT_DIR}/lint"
        cqt_unmeasured "every lintable file in the changed set is missing from disk — coding standards were NOT checked" \
            "${MISSING_FILES[@]+"${MISSING_FILES[@]}"}"
        cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "tool": "phpcs",
  "mode": "changed",
  "standards": ["Drupal", "DrupalPractice"],
  "changed_file": "${CHANGED_FILE}",
  "relevant_files": 0,
  "paths_missing": ${CHANGED_MISSING_JSON},
  "phpcs_exit": null,
  "report_usable": false,
  "errors": 0,
  "warnings": 0,
  "status": "${CQT_STATUS_UNMEASURED}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        exit "$CQT_EXIT_UNMEASURED"
    fi

    # A PARTIALLY MEASURABLE SET. Some of what the caller named is on disk and some is
    # not, so this run measures part of the question it was asked.
    #
    # The verdict for that shape is "partial", and it exits 1. Not 0: the caller reading
    # only the exit code — CI, and AIDA's /validate-* wrappers — reads 0 as a clean pass
    # over the whole set, which is the defect this task exists to remove, one grain
    # finer. Not 4: "unmeasured" means the gate covered nothing, and something was
    # covered here. Not 2: the files that WERE read came back clean, and a diff that
    # deletes a PHP file is ordinary — a gate that failed every such diff would fire on
    # every run and carry no information.
    #
    # Findings still outrank the cap. It only ever turns a would-be "pass" into
    # "partial"; a real error is still "fail" and still exits 2.
    CHANGED_PARTIAL=false
    if [ "${#MISSING_FILES[@]}" -gt 0 ]; then
        CHANGED_PARTIAL=true
        cqt_unmeasured "some changed files are not on disk — they were not scanned" \
            "${MISSING_FILES[@]}"
    fi

    # Have files to scan — now check DDEV + phpcs availability
    if ! ddev describe &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} DDEV is not running"
        exit 2
    fi
    if ! ddev exec vendor/bin/phpcs --version &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} PHP_CodeSniffer is not installed"
        echo "  Run: ddev composer require --dev \"drupal/coder:^8.3.30||^9.0\""
        exit 1
    fi

    mkdir -p "${REPORT_DIR}/lint"

    echo "Relevant files (${#RELEVANT_FILES[@]}):"
    printf '  %s\n' "${RELEVANT_FILES[@]}"
    echo ""

    CHANGED_ERRORS=0
    CHANGED_WARNINGS=0

    # Single invocation with the scoped file args.
    # --extensions is carried here too. phpcs applies extension filtering to directory
    # arguments only, so it changes nothing for an explicitly named file today; it is
    # on every invocation so that no later edit has to rediscover which of the four
    # mattered.
    set +e
    # shellcheck disable=SC2046
    ddev exec vendor/bin/phpcs \
        --standard=Drupal,DrupalPractice \
        --report=json \
        --extensions="${PHPCS_EXTENSIONS}" \
        "${RELEVANT_FILES[@]}" \
        2>/dev/null > "${REPORT_DIR}/lint/phpcs.json"
    CHANGED_PHPCS_EXIT=$?
    set -e

    set +e
    # shellcheck disable=SC2046
    ddev exec vendor/bin/phpcs \
        --standard=Drupal,DrupalPractice \
        --report=summary \
        --extensions="${PHPCS_EXTENSIONS}" \
        "${RELEVANT_FILES[@]}" \
        2>&1 | tee "${REPORT_DIR}/lint/phpcs-summary.txt"
    set -e

    # The standard path validates its counts as integers; this mode had no equivalent,
    # which is the other half of the measured defect. `-s`, not `-f`: phpcs dying
    # mid-run leaves the redirection target in place and empty, jq prints nothing on
    # empty input, and the count becomes the EMPTY STRING rather than a zero — which
    # `[ "" -gt 0 ]` then errors on, `if` swallows, and the status falls through to
    # "pass" while the heredoc writes `"errors": ,`.
    #
    # jq's status decides, not a substituted zero. See the long note on the standard
    # path: `|| echo "0"` turns a TRUNCATED report — non-empty, so `[ -s ]` passes, and
    # unparseable, so jq fails silently — into a certified clean tree. This is the mode
    # CI and AIDA's /validate-* wrappers invoke, and the one where nobody reads stdout.
    CHANGED_USABLE=true
    if [ -s "${REPORT_DIR}/lint/phpcs.json" ] && command -v jq &> /dev/null; then
        if CHANGED_TOTALS=$(jq -r '"\(.totals.errors // 0) \(.totals.warnings // 0)"' \
                               "${REPORT_DIR}/lint/phpcs.json" 2>/dev/null); then
            CHANGED_ERRORS="${CHANGED_TOTALS%% *}"
            CHANGED_WARNINGS="${CHANGED_TOTALS##* }"
        else
            CHANGED_USABLE=false
        fi
    else
        CHANGED_USABLE=false
    fi
    if ! [[ "$CHANGED_ERRORS" =~ ^[0-9]+$ ]] || ! [[ "$CHANGED_WARNINGS" =~ ^[0-9]+$ ]]; then
        CHANGED_USABLE=false
        CHANGED_ERRORS=0
        CHANGED_WARNINGS=0
    fi

    # The version-free rule, the same one the standard path uses. A non-zero exit WITH a
    # usable report is findings — phpcs 4 exits 3 for "auto-fixable plus
    # non-auto-fixable issues", which is a measurement, not a failure. A non-zero exit
    # with NO usable report is a run that did not happen, whichever major produced it:
    # 3.x's 3 and 4.x's 16 both arrive here with an empty or truncated report. Nothing
    # in this file asks phpcs which major it is.
    CHANGED_STATUS="pass"
    if [ "$CHANGED_USABLE" == false ]; then
        CHANGED_STATUS="${CQT_STATUS_UNMEASURED}"
    elif [ "$CHANGED_ERRORS" -gt 0 ]; then
        CHANGED_STATUS="fail"
    elif [ "$CHANGED_WARNINGS" -gt 10 ]; then
        CHANGED_STATUS="warning"
    elif [ "$CHANGED_PARTIAL" == true ]; then
        # Last, so a finding is never softened into an incomplete-coverage note.
        CHANGED_STATUS="partial"
    fi

    cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "tool": "phpcs",
  "mode": "changed",
  "standards": ["Drupal", "DrupalPractice"],
  "changed_file": "${CHANGED_FILE}",
  "relevant_files": ${#RELEVANT_FILES[@]},
  "paths_missing": ${CHANGED_MISSING_JSON},
  "phpcs_exit": ${CHANGED_PHPCS_EXIT},
  "report_usable": ${CHANGED_USABLE},
  "errors": ${CHANGED_ERRORS},
  "warnings": ${CHANGED_WARNINGS},
  "status": "${CHANGED_STATUS}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    echo ""
    echo "=== Summary (changed mode) ==="
    echo "  Files scanned: ${#RELEVANT_FILES[@]}"
    echo "  Errors:        ${CHANGED_ERRORS}"
    echo "  Warnings:      ${CHANGED_WARNINGS}"
    echo ""

    if [ "$CHANGED_STATUS" == "${CQT_STATUS_UNMEASURED}" ]; then
        cqt_unmeasured "phpcs produced no usable report (exit ${CHANGED_PHPCS_EXIT}) — coding standards were NOT verified" \
            "${RELEVANT_FILES[@]}"
        exit "$CQT_EXIT_UNMEASURED"
    elif [ "$CHANGED_STATUS" == "partial" ]; then
        echo -e "${YELLOW}[PARTIAL]${NC} No violations in what was read, but ${#MISSING_FILES[@]} changed file(s) were not on disk — coverage is incomplete"
        exit "$CQT_EXIT_WARNING"
    elif [ "$CHANGED_STATUS" == "pass" ]; then
        echo -e "${GREEN}[PASS]${NC} Coding standards check passed"
        exit 0
    elif [ "$CHANGED_STATUS" == "warning" ]; then
        echo -e "${YELLOW}[WARN]${NC} Some warnings found"
        exit 1
    else
        echo -e "${RED}[FAIL]${NC} Coding standards violations found"
        exit 2
    fi
fi

echo "=== PHP Coding Standards Check ==="
echo ""

# Check DDEV
if ! ddev describe &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} DDEV is not running"
    exit 2
fi

# Check if phpcs is available
if ! ddev exec vendor/bin/phpcs --version &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} PHP_CodeSniffer is not installed"
    echo "  Run: ddev composer require --dev \"drupal/coder:^8.3.30||^9.0\""
    exit 1
fi

mkdir -p "${REPORT_DIR}/lint"

# =====================
# Resolve what to scan: modules AND themes, minus whatever is not there.
# =====================
# The existence filter is not tidiness. phpcs aborts the WHOLE run when any argument
# path does not exist — it prints `ERROR: The file "..." does not exist.` on stderr,
# writes nothing to stdout and exits 3. With `--report=json > phpcs.json` that leaves an
# empty file, `jq '.totals.errors // 0'` on an empty file fails, `|| echo "0"` turns the
# failure into a zero, and the gate prints [PASS]. So simply appending a themes path that
# some layouts do not have would not merely skip themes, it would report a CLEAN TREE
# while scanning neither themes nor modules. Adding coverage must not be able to remove
# the coverage that already worked.
#
# `-e`, not `-d`: the documented override (references/scope-targeting.md) points these
# variables at a single module or theme directory, and phpcs accepts a plain file too.
#
# Checked on the HOST while phpcs runs in the CONTAINER. Equivalent in practice — DDEV
# mounts the project root and these are project-relative paths — and the script already
# assumes cwd is the project root (REPORT_DIR is relative). Run from elsewhere, the
# paths resolve nowhere, and the result is the loud "skipped" below rather than a pass.
SCAN_PATHS=()
MISSING_PATHS=()
for candidate in "${DRUPAL_MODULES_PATH}" "${DRUPAL_THEMES_PATH}"; do
    [ -n "$candidate" ] || continue
    if [ -e "$candidate" ]; then
        SCAN_PATHS+=("$candidate")
    else
        MISSING_PATHS+=("$candidate")
        echo -e "${YELLOW}[UNMEASURED]${NC} ${candidate} does not exist — not scanned"
    fi
done

# Nothing to hand phpcs. Reported as "unmeasured", never as a pass and never with a
# zero exit: a run that examined no files found zero violations by not looking, which is
# the exact false clean this gate is supposed to catch in the code it scans.
#
# Not "skipped", and not exit 0. In this suite "skipped" already means the TOOL is
# absent, which is a legitimate state of the machine; a path that is not there is a
# configuration fact about the project, and filing both under one word makes them
# indistinguishable to full-audit.sh. The exit is 4 rather than 3 because 3 already
# means "the installed tree does not match composer.lock" in two places.
if [ "${#SCAN_PATHS[@]}" -eq 0 ]; then
    echo ""
    cqt_unmeasured "no lintable paths exist — coding standards were NOT checked" \
        "${MISSING_PATHS[@]+"${MISSING_PATHS[@]}"}"
    echo "  Override with DRUPAL_MODULES_PATH / DRUPAL_THEMES_PATH."
    cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "tool": "phpcs",
  "standards": ["Drupal", "DrupalPractice"],
  "paths": [],
  "paths_missing": $(printf '%s\n' "${MISSING_PATHS[@]+"${MISSING_PATHS[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]'),
  "phpcs_exit": null,
  "report_usable": false,
  "errors": 0,
  "warnings": 0,
  "status": "${CQT_STATUS_UNMEASURED}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    exit "$CQT_EXIT_UNMEASURED"
fi

SCAN_PATHS_JSON=$(printf '%s\n' "${SCAN_PATHS[@]}" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
MISSING_PATHS_JSON=$(printf '%s\n' "${MISSING_PATHS[@]+"${MISSING_PATHS[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')

# Initialize counters
ERRORS=0
WARNINGS=0

# Parse command line arguments
FIX_MODE=false
if [ "$1" == "--fix" ]; then
    FIX_MODE=true
fi

if [ "$FIX_MODE" == true ]; then
    echo "Running phpcbf (auto-fix mode)..."
    echo ""

    set +e
    ddev exec vendor/bin/phpcbf \
        --standard=Drupal,DrupalPractice \
        --extensions="${PHPCS_EXTENSIONS}" \
        --ignore="${PHPCS_IGNORE}" \
        "${SCAN_PATHS[@]}" \
        2>&1 | tee "${REPORT_DIR}/lint/phpcbf.txt"
    # PIPESTATUS[0], not `$?`. After `cmd | tee file` the status is TEE's, and tee
    # succeeds whenever it can write the file — so a phpcbf that never ran read as exit 0
    # and printed "All fixable issues corrected", the most reassuring of the three
    # messages below. rector-fix.sh:127-131 states this rule; the same shape survived
    # three lines below the code this task edited.
    PHPCBF_EXIT=${PIPESTATUS[0]}
    set -e

    echo ""
    if [ "$PHPCBF_EXIT" -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} All fixable issues corrected"
    elif [ "$PHPCBF_EXIT" -eq 1 ]; then
        echo -e "${GREEN}[OK]${NC} Some issues were fixed, re-run to check remaining"
    else
        echo -e "${YELLOW}[WARN]${NC} Some issues could not be auto-fixed"
    fi
else
    echo "Running phpcs (check mode)..."
    echo "  Standards: Drupal, DrupalPractice"
    echo "  Paths: ${SCAN_PATHS[*]}"
    echo ""

    # Run phpcs with JSON output
    set +e
    ddev exec vendor/bin/phpcs \
        --standard=Drupal,DrupalPractice \
        --report=json \
        --extensions="${PHPCS_EXTENSIONS}" \
        --ignore="${PHPCS_IGNORE}" \
        "${SCAN_PATHS[@]}" \
        2>/dev/null > "${REPORT_DIR}/lint/phpcs.json"
    PHPCS_EXIT=$?
    set -e

    # Also generate human-readable output
    set +e
    ddev exec vendor/bin/phpcs \
        --standard=Drupal,DrupalPractice \
        --report=summary \
        --extensions="${PHPCS_EXTENSIONS}" \
        --ignore="${PHPCS_IGNORE}" \
        "${SCAN_PATHS[@]}" \
        2>&1 | tee "${REPORT_DIR}/lint/phpcs-summary.txt"
    set -e

    # Parse JSON for counts.
    #
    # `-s`, not `-f`: phpcs dying mid-run leaves the redirection target in place and
    # EMPTY, and an absent or empty report is not a count of zero. The else branch is
    # the difference — without it a report that never arrived left the counters at
    # their initialised 0, which validates as an integer and certifies a clean tree.
    #
    # `|| echo "0"` IS NOT A FALLBACK, IT IS A FABRICATION, and it was the hole this
    # guard was written to close. On a TRUNCATED report — valid JSON so far and nothing
    # more, which is what an OOM-killed or disk-full phpcs leaves — `[ -s ]` is
    # satisfied because the file is not empty, jq exits non-zero and prints nothing, and
    # `|| echo "0"` then supplies a literal zero that validates as an integer below. The
    # gate certified a clean tree from a scan that died mid-write. Measured on the
    # shipped script: [PASS], exit 0, report_usable true, errors 0.
    #
    # So jq's OWN status is what decides, in ONE invocation whose failure cannot be
    # confused with a count: it either parses the report and prints both totals, or it
    # fails and the report is unusable. Nothing substitutes a value for a parse that did
    # not happen.
    PHPCS_USABLE=true
    if [ -s "${REPORT_DIR}/lint/phpcs.json" ] && command -v jq &> /dev/null; then
        if PHPCS_TOTALS=$(jq -r '"\(.totals.errors // 0) \(.totals.warnings // 0)"' \
                             "${REPORT_DIR}/lint/phpcs.json" 2>/dev/null); then
            ERRORS="${PHPCS_TOTALS%% *}"
            WARNINGS="${PHPCS_TOTALS##* }"
        else
            PHPCS_USABLE=false
        fi
    else
        PHPCS_USABLE=false
    fi

    # A count that is not a number is not a count of zero. A SECOND guard, kept even
    # though the parse above now reports its own failure.
    #
    # It catches the shape jq itself calls success: a report whose .totals.errors is
    # present but is a string, a null-that-is-not-absent, or an object — jq exits 0 and
    # prints it, and only this test can tell that it is not a count. jq exiting 0 on
    # EMPTY input is the same family: it emits nothing, ERRORS becomes the empty string,
    # `[ "" -gt 0 ]` aborts with "integer expression expected", `if` swallows that as
    # false and the status falls through to "pass".
    #
    # The two guards divide the ways a report can be unreadable and neither covers the
    # other: this one cannot see a truncated file (jq fails, prints nothing, and a
    # substituted 0 passes the regex), and the parse above cannot see a well-formed
    # report carrying a nonsense total.
    if ! [[ "$ERRORS" =~ ^[0-9]+$ ]] || ! [[ "$WARNINGS" =~ ^[0-9]+$ ]]; then
        PHPCS_USABLE=false
        ERRORS=0
        WARNINGS=0
    fi

    # THE VERSION-FREE EXIT RULE. PHPCS_EXIT was captured above and read nowhere in this
    # file; the fix is not "read 3 correctly", it is "read it at all" — and then not
    # decode it. `3` is a processing error under phpcs 3 and `1 auto-fixable + 2
    # non-auto-fixable issues` under phpcs 4, so a gate that decides by the number needs
    # a version table that has to be re-checked against every phpcs release.
    #
    # The report answers it instead, in a shape that did not change between majors:
    #
    #   non-zero exit WITH a usable JSON report -> findings, by the counts below
    #   non-zero exit with NO usable report     -> unmeasured
    #
    # A usable report already decides the verdict on its own, so the exit code adds
    # nothing when there is one; it is recorded in the report for a reader, and it is
    # what makes the unusable case legible rather than mysterious.
    LINT_STATUS="pass"
    if [ "$PHPCS_USABLE" == false ]; then
        LINT_STATUS="${CQT_STATUS_UNMEASURED}"
    elif [ "$ERRORS" -gt 0 ]; then
        LINT_STATUS="fail"
    elif [ "$WARNINGS" -gt 10 ]; then
        LINT_STATUS="warning"
    fi

    # Generate report
    cat > "${REPORT_DIR}/lint-report.json" << EOF
{
  "tool": "phpcs",
  "standards": ["Drupal", "DrupalPractice"],
  "paths": ${SCAN_PATHS_JSON},
  "paths_missing": ${MISSING_PATHS_JSON},
  "phpcs_exit": ${PHPCS_EXIT},
  "report_usable": ${PHPCS_USABLE},
  "errors": ${ERRORS},
  "warnings": ${WARNINGS},
  "status": "${LINT_STATUS}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    echo ""
    echo "=== Summary ==="
    echo "  Errors:   ${ERRORS}"
    echo "  Warnings: ${WARNINGS}"
    echo ""

    if [ "$LINT_STATUS" == "${CQT_STATUS_UNMEASURED}" ]; then
        # NOT exit 0. The status is the primary channel and full-audit.sh reads it, but
        # a gate run standalone or through AIDA's /validate-* wrappers has only the exit
        # code, and a zero there is read as a pass by every caller that has one.
        cqt_unmeasured "phpcs produced no usable report (exit ${PHPCS_EXIT}) — coding standards were NOT verified" \
            "${SCAN_PATHS[@]}"
        exit "$CQT_EXIT_UNMEASURED"
    elif [ "$LINT_STATUS" == "pass" ]; then
        echo -e "${GREEN}[PASS]${NC} Coding standards check passed"
        exit 0
    elif [ "$LINT_STATUS" == "warning" ]; then
        echo -e "${YELLOW}[WARN]${NC} Some warnings found"
        echo ""
        echo "To auto-fix, run:"
        echo "  scripts/drupal/lint-check.sh --fix"
        exit 1
    else
        echo -e "${RED}[FAIL]${NC} Coding standards violations found"
        echo ""
        echo "To auto-fix, run:"
        echo "  scripts/drupal/lint-check.sh --fix"
        exit 2
    fi
fi
