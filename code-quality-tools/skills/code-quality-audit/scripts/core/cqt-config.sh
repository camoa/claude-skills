#!/bin/bash
# cqt-config.sh - read .code-quality.json, or refuse.
# Part of code-quality-audit skill
#
# SOURCEABLE, in the shape of report-dir.sh and path-resolve.sh. Both the installer and
# the verifier need this as a function set rather than a process, and neither may inherit
# a shell option or a printed banner from it. So, like path-resolve.sh:
#
#   * it sources nothing;
#   * it executes no code and runs no external command at load time;
#   * it sets no shell option and prints nothing until a function is called.
#
# ── why this is not install-tools.sh:25-27 ────────────────────────────────────
#
# That code read two scalars out of environment.json with a Perl-regex grep and then did
# PROJECT_TYPE="${PROJECT_TYPE:-drupal}", so a missing, truncated or renamed field
# produced a Drupal install on a project nobody had established was Drupal, behind a
# [WARN] nobody reads.
#
# The nuance matters, and it is NOT "grep is wrong". That scrape is a deliberate no-jq
# path: full-audit.sh:128 does the same with a comment, and detect-environment.sh treats
# a missing jq as first-class. It is correct there because environment.json is a
# DETECTION RECORD, and a detection that could not run should degrade.
#
# .code-quality.json is a CONTRACT FILE. A contract you could not read is not a contract
# you may assume. So this library requires jq and says so, matching
# check_version_drift()'s own reasoning at detect-environment.sh:241-249 for choosing jq
# over a pattern, and every failure path here ends in exit 2 with the field named. No
# step falls through to a default.
#
# ── what it exposes ───────────────────────────────────────────────────────────
#
#   cqt_config_load <path|->        parse + validate; exits 2 on any failure
#   cqt_config_derive <type> <web>  emit a complete config from the catalog, on stdout
#   cqt_config_get <jq-path>        scalar accessor over the loaded document
#   cqt_config_tools <scope>        NUL-separated specs for one scope
#   cqt_config_source               "file" | "derived"
#   cqt_config_doc                  the validated document itself
#
# Nothing here writes to disk on any path. That is what makes it safe to source from an
# audit: a run the user asked to be a read leaves the tree as it found it.

# shellcheck disable=SC2034
# CQT_CONFIG_DOC and friends are unused WITHIN this file, which is what a sourceable
# library is. Silenced here rather than in scripts/lint-baseline.txt so the reason stays
# beside the code, the same choice path-resolve.sh made.

CQT_CONFIG_DOC=""
CQT_CONFIG_SOURCE=""
CQT_CONFIG_PATH=""

# Where the plugin's own data lives. Overridable so a fixture can point at a doctored
# catalog and prove the derivation is not a path around the validator.
CQT_SCHEMA_DIR_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/schema"
CQT_CATALOG="${CQT_CATALOG:-${CQT_SCHEMA_DIR_DEFAULT}/tool-catalog.json}"
CQT_SCHEMA="${CQT_SCHEMA:-${CQT_SCHEMA_DIR_DEFAULT}/code-quality.schema.json}"

# The schema majors this installer knows how to act on. A document carrying anything
# else is refused BY NAME rather than guessed at: setup.md:158-190 already shipped a
# different shape under the key "version", and installing from a shape you have decided
# to interpret loosely is how the two paths came to disagree.
CQT_SCHEMA_MAJORS="3"

# Composer's own package-name grammar, and npm's. Every name in a config reaches a
# command line, so it is checked against these before it can be an argument — whether it
# came from a project's config file or from the catalog this plugin ships. The catalog
# being trusted is not a reason for the installer to trust its own input.
CQT_NAME_COMPOSER='^[a-z0-9]([_.-]?[a-z0-9]+)*/[a-z0-9]([_.-]?[a-z0-9]+)*$'
CQT_NAME_NPM='^(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$'
# A version constraint is a narrow alphabet on purpose: it is concatenated onto the name
# with a colon and handed to Composer as one argv element.
CQT_CONSTRAINT_GRAMMAR='^[A-Za-z0-9^~><=!.*|, +-]*$'

# ── failure ───────────────────────────────────────────────────────────────────

# Refuse, naming the field and the condition, and leave with 2.
#
# Two arguments because a reader acts on both halves: WHICH key is wrong and WHAT is
# wrong with it. A single generic "invalid config" tells somebody nothing they can fix,
# and this whole library exists because the alternative to a loud refusal was a silent
# default.
cqt_config_fail() {
    local field="$1" reason="$2"
    printf '[ERROR] .code-quality.json (%s): %s\n' "${CQT_CONFIG_PATH:-<stdin>}" "${reason}" >&2
    printf '        field: %s\n' "${field}" >&2
    printf '        The config is refused, not repaired. Repairing a contract silently is\n' >&2
    printf '        how this plugin came to have two install paths that disagreed.\n' >&2
    exit 2
}

# ── the enums, read from the schema rather than restated here ─────────────────
#
# The validator and the schema cannot drift on a value list, because there is only one
# list. No JSON Schema validator is a dependency of this plugin (no ajv, no
# check-jsonschema, no python jsonschema), so validation is implemented in jq; reading
# the enums out of the schema file is what keeps the schema load-bearing rather than
# decorative.
cqt_schema_enum() {
    jq -r --arg p "$1" '
        getpath($p | split(".") | map(select(length > 0))) | .[]? // empty
    ' "${CQT_SCHEMA}" 2>/dev/null
}

# ── load ──────────────────────────────────────────────────────────────────────

# Parse and validate one document. `-` reads it from stdin, which is how a derived
# config is validated without ever becoming a file.
#
# Order matters: every check runs against something the previous check established. A
# validator that reads a field before it has established the document parses is a
# validator that reports the wrong failure.
cqt_config_load() {
    local src="${1-}"
    local doc

    CQT_CONFIG_PATH="${src}"

    command -v jq > /dev/null 2>&1 || cqt_config_fail "(none)" \
        "jq is required to read a contract file, and is not installed. The audit path treats jq as optional because environment.json is a detection record; this is not one."

    [ -n "${src}" ] || cqt_config_fail "(none)" "no config path given"

    if [ "${src}" = "-" ]; then
        doc="$(cat)"
        CQT_CONFIG_SOURCE="derived"
        CQT_CONFIG_PATH="<stdin>"
        [ -n "${doc}" ] || cqt_config_fail "(document)" "the document on stdin is empty"
    else
        CQT_CONFIG_SOURCE="file"
        [ -e "${src}" ] || cqt_config_fail "(file)" "no such file: ${src}"
        [ -r "${src}" ] || cqt_config_fail "(file)" "the file is not readable: ${src}"
        [ -s "${src}" ] || cqt_config_fail "(file)" "the file is empty: ${src}"
        doc="$(cat "${src}")"
    fi

    jq -e . > /dev/null 2>&1 <<< "${doc}" \
        || cqt_config_fail "(document)" "the file is not valid JSON"

    CQT_CONFIG_DOC="${doc}"

    cqt_config_validate_shape
    cqt_config_validate_invariants
    return 0
}

# Shape: the required keys, the types, and the enums. What a JSON Schema validator would
# do, done in jq because this plugin ships no validator binary and will not add one as a
# hard dependency of an install path.
cqt_config_validate_shape() {
    local doc="${CQT_CONFIG_DOC}" v major key missing enum_vals bad

    v="$(jq -r '.schema_version // ""' <<< "${doc}")"
    [ -n "${v}" ] || cqt_config_fail "schema_version" "schema_version is absent"
    case "${v}" in
        [0-9]*.[0-9]*) ;;
        *) cqt_config_fail "schema_version" "schema_version is not major.minor: ${v}" ;;
    esac
    major="${v%%.*}"
    case " ${CQT_SCHEMA_MAJORS} " in
        *" ${major} "*) ;;
        *) cqt_config_fail "schema_version" \
             "schema_version major ${major} is not one this installer knows (knows: ${CQT_SCHEMA_MAJORS}). Refused rather than guessed at." ;;
    esac

    # Required top-level keys, taken from the schema's own required[] list.
    for key in $(jq -r '.required[]?' "${CQT_SCHEMA}" 2>/dev/null); do
        jq -e --arg k "${key}" 'has($k)' > /dev/null 2>&1 <<< "${doc}" \
            || cqt_config_fail "${key}" "required key '${key}' is absent"
    done

    jq -e '.project | has("type")' > /dev/null 2>&1 <<< "${doc}" \
        || cqt_config_fail "project.type" "project.type is absent"
    jq -e '.project | has("layout")' > /dev/null 2>&1 <<< "${doc}" \
        || cqt_config_fail "project.layout" "project.layout is absent"

    cqt_config_enum_check "project.type" ".properties.project.properties.type.enum" \
        "$(jq -r '.project.type' <<< "${doc}")"
    cqt_config_enum_check "project.layout.web_root" \
        ".properties.project.properties.layout.properties.web_root.enum" \
        "$(jq -r '.project.layout.web_root // "\u0000ABSENT"' <<< "${doc}")"

    jq -e '.tools | type == "object" and length > 0' > /dev/null 2>&1 <<< "${doc}" \
        || cqt_config_fail "tools" "tools is absent, not an object, or empty"

    bad="$(jq -r '[.tools | to_entries[] | select((.value.scope // "") as $s | ["project","isolated","machine"] | index($s) | not) | .key] | join(", ")' <<< "${doc}")"
    [ -z "${bad}" ] || cqt_config_fail "tools.<id>.scope" \
        "scope must be project|isolated|machine; wrong on: ${bad}"

    bad="$(jq -r '[.tools | to_entries[] | select(.value | has("packages") | not) | .key] | join(", ")' <<< "${doc}")"
    [ -z "${bad}" ] || cqt_config_fail "tools.<id>.packages" \
        "every tool carries a packages list, even an empty one; absent on: ${bad}"

    # allow_plugins is required and usually empty. Required, because the entry that
    # matters is not derivable from the package list: drupal/coder pulls
    # dealerdirect/phpcodesniffer-composer-installer transitively and never names it,
    # so "allow every plugin I am requiring" cannot produce it, and without it the
    # Drupal phpcs standard is never registered at all.
    bad="$(jq -r '[.tools | to_entries[] | select(.value | has("allow_plugins") | not) | .key] | join(", ")' <<< "${doc}")"
    [ -z "${bad}" ] || cqt_config_fail "tools.<id>.allow_plugins" \
        "every tool carries an allow_plugins list, even an empty one; absent on: ${bad}"

    jq -e '.phpstan.level | type == "number" and . >= 0 and . <= 10' > /dev/null 2>&1 <<< "${doc}" \
        || jq -e '.project.type != "drupal"' > /dev/null 2>&1 <<< "${doc}" \
        || cqt_config_fail "phpstan.level" "a Drupal config carries phpstan.level, an integer 0-10"

    jq -e '.git_hooks | has("enabled") and (.enabled | type == "boolean")' > /dev/null 2>&1 <<< "${doc}" \
        || cqt_config_fail "git_hooks.enabled" "git_hooks.enabled is absent or not a boolean"

    # The isolation mechanism, carried in the config so the installer has one input
    # and no package name of its own.
    for key in package constraint allow_plugin forward_command_key; do
        jq -e --arg k "${key}" '.isolation | has($k)' > /dev/null 2>&1 <<< "${doc}" \
            || cqt_config_fail "isolation.${key}" "isolation.${key} is absent"
    done

    for key in coverage complexity duplication security_severity; do
        jq -e --arg k "${key}" '.thresholds | has($k)' > /dev/null 2>&1 <<< "${doc}" \
            || cqt_config_fail "thresholds.${key}" "thresholds.${key} is absent"
    done
    cqt_config_enum_check "thresholds.security_severity" \
        ".properties.thresholds.properties.security_severity.enum" \
        "$(jq -r '.thresholds.security_severity' <<< "${doc}")"
    return 0
}

# One value against one enum in the schema. Named separately because the message has to
# carry the field, the offending value AND the permitted set: "invalid" alone leaves the
# reader guessing at what the file was allowed to say.
cqt_config_enum_check() {
    local field="$1" enum_path="$2" value="$3"
    local allowed

    # The membership test is done IN jq, not by splitting the enum into lines and
    # comparing in bash. The empty string is a legitimate member of the web_root enum —
    # it is what a root-layout project records — and a line-based comparison loses it:
    # command substitution strips the trailing newline the empty element produced, so
    # the value is silently absent from the list and every root-layout project is
    # refused for a value the schema explicitly permits.
    jq -e --arg p "${enum_path}" --arg v "${value}" '
        (getpath($p | split(".") | map(select(length > 0))) // []) | index($v) != null
    ' "${CQT_SCHEMA}" > /dev/null 2>&1 && return 0

    allowed="$(jq -r --arg p "${enum_path}" '
        (getpath($p | split(".") | map(select(length > 0))) // [])
        | map(if . == "" then "(empty)" else . end) | join("|")
    ' "${CQT_SCHEMA}" 2>/dev/null)"
    [ -n "${allowed}" ] || cqt_config_fail "${field}" \
        "the shipped schema has no enum at ${enum_path}; the plugin's own schema is unreadable, so nothing is validated"
    cqt_config_fail "${field}" "'${value}' is not one of: ${allowed}"
}

# Meaning, not shape. These are the reason criterion 8 holds for BOTH entry points
# rather than only for the wizard's: a derived config goes through exactly these.
cqt_config_validate_invariants() {
    local doc="${CQT_CONFIG_DOC}" ptype missing name constraint bad tmpl allowed

    ptype="$(jq -r '.project.type' <<< "${doc}")"

    # 1. The Drupal PHPStan set. Its absence is the defect the whole task starts from:
    #    the shipped phpstan.neon carries no `includes:` block by design, so when the
    #    extension never registered there is nothing to fail. PHPStan starts, loads zero
    #    Drupal rules, analyses Drupal as plain PHP, and exits 0.
    if [ "${ptype}" = "drupal" ] || [ "${ptype}" = "monorepo" ]; then
        for name in phpstan/extension-installer mglaman/phpstan-drupal phpstan/phpstan-deprecation-rules; do
            jq -e --arg n "${name}" '
                [.tools[] | select(.scope == "project") | .packages[]?.name] | index($n) != null
            ' > /dev/null 2>&1 <<< "${doc}" \
                || cqt_config_fail "tools" \
                     "a Drupal config must install ${name} at scope project; it is absent. Without it PHPStan analyses Drupal as plain PHP and exits 0, which reads as a clean tree."
        done
    fi

    # 2. Names and constraints, against the grammars. This is the trust boundary:
    #    .code-quality.json is attacker-reachable on any repository the auditor did not
    #    write, and these values become `composer require` arguments.
    while IFS= read -r name; do
        [ -n "${name}" ] || continue
        if ! printf '%s' "${name}" | grep -qE "${CQT_NAME_COMPOSER}" \
           && ! printf '%s' "${name}" | grep -qE "${CQT_NAME_NPM}"; then
            cqt_config_fail "tools.<id>.packages[].name" \
                "package name '${name}' matches neither the Composer nor the npm name grammar. Nothing else may reach a command line."
        fi
    done <<< "$(jq -r '.tools[]?.packages[]?.name // empty' <<< "${doc}")"

    while IFS= read -r constraint; do
        [ -n "${constraint}" ] || continue
        printf '%s' "${constraint}" | grep -qE "${CQT_CONSTRAINT_GRAMMAR}" \
            || cqt_config_fail "tools.<id>.packages[].constraint" \
                 "version constraint '${constraint}' is outside the permitted alphabet"
    done <<< "$(jq -r '.tools[]?.packages[]?.constraint // empty' <<< "${doc}")"

    while IFS= read -r name; do
        [ -n "${name}" ] || continue
        printf '%s' "${name}" | grep -qE "${CQT_NAME_COMPOSER}" \
            || cqt_config_fail "tools.<id>.allow_plugins[]" \
                 "allow-plugins entry '${name}' is not a Composer package name. It becomes an argument to 'composer config'."
    done <<< "$(jq -r '.tools[]?.allow_plugins[]? // empty' <<< "${doc}")"

    for name in "$(jq -r '.isolation.package // empty' <<< "${doc}")" \
                "$(jq -r '.isolation.allow_plugin // empty' <<< "${doc}")"; do
        [ -n "${name}" ] || continue
        printf '%s' "${name}" | grep -qE "${CQT_NAME_COMPOSER}" \
            || cqt_config_fail "isolation" "isolation names '${name}', which is not a Composer package name"
    done

    # 3. Template ids, against the schema's fixed allowlist. Never joined into a path,
    #    so a config cannot make the installer read or write an arbitrary file.
    allowed="$(cqt_schema_enum ".properties.templates.items.enum")"
    [ -n "${allowed}" ] || cqt_config_fail "templates" \
        "the shipped schema carries no template allowlist, so nothing constrains what would be placed"
    while IFS= read -r tmpl; do
        [ -n "${tmpl}" ] || continue
        printf '%s\n' "${allowed}" | grep -qxF -- "${tmpl}" \
            || cqt_config_fail "templates" \
                 "template id '${tmpl}' is not in the allowlist: $(printf '%s' "${allowed}" | tr '\n' '|')"
    done <<< "$(jq -r '.templates[]? // empty' <<< "${doc}")"

    # 4. Consent. GrumPHP attaches git hooks at package-install time, so consent for the
    #    package and consent for the hooks are the same answer. setup.md:76 installed the
    #    package in the unconditional block, BEFORE the prompt at :196, and :206
    #    installed it again — so a user who declined hooks still got it.
    if [ "$(jq -r '.git_hooks.enabled' <<< "${doc}")" != "true" ]; then
        bad="$(jq -r '[.tools[]?.packages[]?.name | select(. == "phpro/grumphp" or . == "husky")] | join(", ")' <<< "${doc}")"
        [ -z "${bad}" ] || cqt_config_fail "git_hooks.enabled" \
            "git_hooks.enabled is false, so no consent-gated tool may be installed; found: ${bad}"
    fi

    # 5. Layout containment. These strings are substituted into every placed template and
    #    are the only config values that become path components.
    while IFS= read -r bad; do
        [ -n "${bad}" ] || continue
        case "${bad}" in
            *..*|/*) cqt_config_fail "project.layout" \
                        "layout value '${bad}' escapes the project root" ;;
        esac
        printf '%s' "${bad}" | grep -qE '^[A-Za-z0-9._/-]+$' \
            || cqt_config_fail "project.layout" \
                 "layout value '${bad}' is not a plain relative path"
    done <<< "$(jq -r '.project.layout | to_entries[] | select(.key != "web_root") | .value // empty' <<< "${doc}")"

    return 0
}

# ── accessors ─────────────────────────────────────────────────────────────────

cqt_config_doc() { printf '%s' "${CQT_CONFIG_DOC}"; }
cqt_config_source() { printf '%s' "${CQT_CONFIG_SOURCE}"; }

# One scalar, by jq path. Returns empty for a path that is not there rather than the
# string "null", because a caller testing -n on "null" would be testing a true string.
cqt_config_get() {
    jq -r --arg p "$1" 'getpath($p | split(".") | map(select(length > 0))) // empty' \
        <<< "${CQT_CONFIG_DOC}" 2>/dev/null
}

# The package specs for one scope, NUL-separated so a name never has to survive being
# re-split on whitespace, and consumed into a bash array by the installer rather than
# interpolated into a command string.
#
#   project | machine : "<name>[:<constraint>]" per package
#   isolated          : "<tool-id>:<name>[:<constraint>]", because each isolated tool
#                       gets its OWN vendor-bin namespace and the id is the namespace
#
# An empty constraint emits the bare name. That is deliberate and not an omission: npm
# packages and drupal/core-dev are unconstrained on purpose, the latter because it is a
# metapackage locked to the site's Drupal minor.
cqt_config_tools() {
    local scope="$1"
    if [ "${scope}" = "isolated" ]; then
        jq -j --arg s "${scope}" '
            .tools | to_entries[] | select(.value.scope == $s) as $t
            | $t.value.packages[]?
            | ($t.key + ":" + .name + (if (.constraint // "") == "" then "" else ":" + .constraint end))
            + "\u0000"
        ' <<< "${CQT_CONFIG_DOC}" 2>/dev/null
    else
        jq -j --arg s "${scope}" '
            .tools[] | select(.scope == $s) | .packages[]?
            | (.name + (if (.constraint // "") == "" then "" else ":" + .constraint end))
            + "\u0000"
        ' <<< "${CQT_CONFIG_DOC}" 2>/dev/null
    fi
}

# Every Composer plugin the loaded config says must be allowed, de-duplicated and
# NUL-separated, in catalog order. Stage 2 of the installer writes one `composer config`
# invocation per entry, before any require.
cqt_config_allow_plugins() {
    jq -j '[.tools[]?.allow_plugins[]?] | unique | .[] | . + "\u0000"' \
        <<< "${CQT_CONFIG_DOC}" 2>/dev/null
}

# The tool ids at one scope, NUL-separated. The installer needs the id as well as the
# packages: it is the vendor-bin namespace, and it is what a machine-scope report names.
cqt_config_tool_ids() {
    jq -j --arg s "$1" '.tools | to_entries[] | select(.value.scope == $s) | .key + "\u0000"' \
        <<< "${CQT_CONFIG_DOC}" 2>/dev/null
}

# ── derive ────────────────────────────────────────────────────────────────────

# Build a COMPLETE config from the catalog, for a detected project type and layout, and
# write it to stdout. The only function that reads tool-catalog.json, and it writes
# nothing at all.
#
# Why complete rather than partial, and why not simply refusing: refusing silently skips,
# and deriving does not. A run that cannot find a config still installs the full, correct
# package set and still prints exactly what it resolved.
#
# Why nothing is persisted: no tool in this space writes a config file during a normal
# run. PHPStan and Prettier hold zero-config defaults in memory; ESLint 9 fails fast and
# points at `npm init @eslint/config`. Writing is reserved for an explicit init command,
# and this plugin has one — /code-quality-tools:setup is the sole writer. An audit that
# invents a file in somebody's repository leaves something indistinguishable from a file
# a person authored.
#
# Both arguments are required. A derivation that guessed its own project type would be
# the fail-open default this library exists to remove, wearing a different name.
cqt_config_derive() {
    local ptype="${1-}" webroot="${2-}" mods themes

    command -v jq > /dev/null 2>&1 || cqt_config_fail "(none)" \
        "jq is required to derive a config from the catalog, and is not installed"
    [ -n "${ptype}" ] || cqt_config_fail "project.type" \
        "cannot derive a config without a detected project type. Nothing is assumed here."
    [ -f "${CQT_CATALOG}" ] || cqt_config_fail "(catalog)" \
        "the tool catalog is missing at ${CQT_CATALOG}"

    if [ -n "${webroot}" ]; then
        mods="${webroot}/modules/custom"
        themes="${webroot}/themes/custom"
    else
        mods="modules/custom"
        themes="themes/custom"
    fi

    # git_hooks.enabled is false because no consent was given: a derived config is what
    # an AUDIT resolves, and an audit has asked nobody anything. Invariant 4 then keeps
    # every consent-gated tool out, which is the same gate the wizard's config passes.
    jq --arg t "${ptype}" --arg w "${webroot}" --arg m "${mods}" --arg th "${themes}" '
        . as $catalog
        | (if $t == "nextjs" then ["nextjs","any"] else ["drupal","any"] end) as $stacks
        | [.tools | to_entries[]
           | select(.value.stack as $st | ($stacks | index($st)) != null)
           | select(.value.consent_gated != true)] as $picked
        | {
            schema_version: "3.0",
            project: { type: $t, layout: { web_root: $w, modules: $m, themes: $th } },
            tools: ($picked | map({
                key: .key,
                value: ({ scope: .value.scope, packages: .value.packages,
                          allow_plugins: (.value.allow_plugins // []), bin: .value.bin }
                        + (if (.value.install_hint // "") == "" then {} else { install_hint: .value.install_hint } end))
              }) | from_entries),
            phpstan: { level: 5 },
            isolation: ( $catalog.isolation
                         | { package, constraint, allow_plugin, forward_command_key } ),
            templates: (if $t == "nextjs"
                        then ["nextjs/eslint.config.js","nextjs/jest.config.js","nextjs/jest.setup.js"]
                        else ["drupal/phpstan.neon","drupal/phpmd.xml","drupal/phpunit.xml","drupal/psalm.xml"]
                        end),
            git_hooks: { enabled: false, tool: null, tasks: [] },
            thresholds: { coverage: 80, complexity: 10, duplication: 5, security_severity: "medium" }
          }
    ' "${CQT_CATALOG}"
}

# Print the derived config in full, by scope, so a run that found no file still states
# exactly what it resolved. This is the half that stops the silent skip, and it does not
# depend on the full-audit.sh `|| true` fix landing in the sibling task.
#
# This used to end the first paragraph with "Nothing was written." That sentence was
# false at the moment it was printed. The narrow claim behind it holds — no
# .code-quality.json is created, and the report directory resolves outside the repository
# — but the install that follows places the template config files and lets Composer edit
# composer.json, and a full find(1) snapshot before and after a derived audit shows
# phpstan.neon, phpmd.xml, phpunit.xml and psalm.xml added and composer.json modified.
# "Nothing was written" is the reassurance a reader acts on, so it now says what it
# actually means and the run names the files it is about to place.
#
# The templates are still placed, deliberately. Removing them from this path would leave
# PHPStan reading no config on exactly the projects that never ran /setup, which is
# PHPStan analysing Drupal as plain PHP and exiting 0 — the false clean this epic exists
# to remove, reintroduced in the name of tidiness. The honest fix is the sentence.
cqt_config_announce_derived() {
    local scope spec tmpl
    printf '[INFO] No .code-quality.json found. Derived a complete config from the tool\n'
    printf '       catalog for project type %s, layout %s. No .code-quality.json was\n' \
        "'$(cqt_config_get .project.type)'" "'$(cqt_config_get .project.layout.web_root)'"
    printf '       written: this config exists only in memory for the duration of this run.\n'
    for scope in project isolated machine; do
        printf '[INFO] Resolved (%s):\n' "${scope}"
        while IFS= read -r -d '' spec; do
            printf '         %s\n' "${spec}"
        done < <(cqt_config_tools "${scope}")
    done
    printf '[INFO] The install this feeds DOES write to the project: Composer edits\n'
    printf '       composer.json for the packages above, and these config files are placed\n'
    printf '       at the project root unless a file of that name is already there:\n'
    while IFS= read -r tmpl; do
        [ -n "${tmpl}" ] || continue
        printf '         ./%s\n' "${tmpl##*/}"
    done <<< "$(jq -r '.templates[]? // empty' <<< "${CQT_CONFIG_DOC}" 2> /dev/null)"
    printf '[INFO] To keep this configuration, run /code-quality-tools:setup. That command\n'
    printf '       is the only writer of .code-quality.json in this plugin.\n'
}
