#!/bin/bash
# secret-scan.sh - phases 1 and 3 of secret scanning: WHAT GROUND IS COVERED.
# Part of code-quality-audit skill. Sourced by drupal/security-check.sh and
# nextjs/security-check.sh; never executed directly.
#
# Sibling of core/secret-history.sh, which is phase 2 (confirmation). Read that
# file's header first: it explains the three phases and why the matched secret
# value never reaches a file, a log line or any process's argv. This file keeps
# both of those properties - every gitleaks invocation it builds carries --redact,
# and nothing here ever holds a matched value, so there is no xtrace hazard to
# suppress the way secret-history.sh has to.
#
# ── what this file decides ────────────────────────────────────────────────────
#
# "Run gitleaks" is not one operation. It is a choice of GROUND, and the choice
# was previously made silently and wrongly:
#
#   tree     the working tree. Seconds. `gitleaks dir`. The default.
#   history  every commit reachable from every ref. The only pass that can find a
#            secret that was committed and later removed - the case gitleaks
#            exists for - and the only pass that is genuinely expensive.
#   diff     a bounded commit range, normally merge-base..HEAD. The CI answer.
#
# The old invocation was `gitleaks detect ... --no-git`, which is the 8.x spelling
# of `gitleaks dir`: the working tree only, with nothing in the output saying so.
# A credential committed in one release and gitignored in the next was invisible,
# and "Gitleaks: 0 findings" read as proof of a clean repository.
#
# ── why history is not simply the default ─────────────────────────────────────
#
# Measured on the repository this came from: 2,368 commits, 253,505 packed
# objects, 224.84 MiB of history, with Drupal core, vendor/ and contrib all
# committed before a Composer migration. A full-history scan ran for many minutes
# at several hundred percent CPU and was killed at ten. Nothing makes full-history
# discovery cheap on a repository that ever committed its vendor directory. So
# history is an explicit, budgeted, timed-out opt-in, never the default.
#
# ── the --log-opts trap, which is measured and not theoretical ────────────────
#
# gitleaks takes --log-opts as a SINGLE STRING and splits it on whitespace before
# handing it to `git log`. SHELL QUOTE CHARACTERS INSIDE THE VALUE ARE THE TRAP, and
# their failure mode is worse than the problem they were meant to solve. Measured on
# gitleaks 8.30.1 against a two-commit fixture holding two secrets:
#
#   --log-opts="--all"                            rc=1  removed.js,tracked.js
#   --log-opts="--all -- :(exclude)removed.js"    rc=1  tracked.js      scopes CORRECTLY
#   --log-opts="--all -- ':(exclude)removed.js'"  rc=0  (none)          silent no-op
#
# The quoted form scans zero bytes, finds nothing and exits 0 - because the quotes
# reach git as literal characters and the pathspec matches no path. At scale that is
# what produced a 1h07m run over 4.01 GB that reported no error and covered nothing
# anyone intended. Silent no-op is the important part: anyone putting that in CI
# would believe the scan was scoped and get no coverage, indefinitely.
#
# So cqt_gitleaks_plan REFUSES a --log-opts value containing a quote character and
# records a skip. It does NOT refuse pathspecs as such: the unquoted form is measured
# to scope correctly, and refusing what works while calling it a pathspec problem is
# a false explanation on top of a false refusal. What the refusal can and cannot see
# is stated at the guard.
#
# What actually works, and what each thing buys:
#   * templates/gitleaks-vendored-allowlist.toml filters vendored findings so the
#     report is readable. It does NOT reduce scan time on a history pass - every blob
#     is still read - and it SUPPRESSES findings, so it is opt-in and the run prints
#     a [FILTER] line naming the config whenever it is in force.
#   * a bounded commit range makes CI affordable.
#   * an unquoted pathspec through --log-opts scopes a history pass.
#   * `gitleaks dir` over the working tree is seconds.
#
# ── why every history pass carries --text --no-textconv ───────────────────────
#
# `gitleaks git` drives `git log -p`. A `-diff` or `binary` attribute in
# .gitattributes makes git print "Binary files a/x and b/x differ" and NO content
# lines, so gitleaks reads zero bytes, finds nothing, writes a well-formed `[]` and
# exits 0. Measured on a fixture carrying `* -diff` and two committed secrets:
#
#   default flags                     INF 0 commits scanned  ~0 bytes    no leaks found
#   --text --no-textconv in log-opts  INF 1 commits scanned  ~116 bytes  leaks found: 2
#
# `*.json -diff` and `*.cfg binary` are ordinary .gitattributes entries and config
# files are where tokens live, so this is not a corner. core/secret-history.sh has
# carried --text for the same reason since it was written; this file now carries it
# too, and cqt_gitleaks_extra_scan additionally refuses to call a pass that scanned
# ZERO BYTES a clean history.
#
# ── environment ───────────────────────────────────────────────────────────────
#
#   CQT_SECRET_SCAN=tree|history|diff   ground to cover (default tree).
#   CQT_SECRET_SCAN_BASE=<ref>          diff mode base. Unset: derived from the
#                                       first resolvable upstream ref, else refused.
#   CQT_SECRET_SCAN_LOG_OPTS=<string>   passed to gitleaks --log-opts for the
#                                       history/diff pass. No quote characters:
#                                       gitleaks word-splits the value, so quoting
#                                       is lost. Ranges and unquoted pathspecs work.
#   CQT_SECRET_SCAN_ALLOWLIST=vendored  apply the shipped vendored-path allowlist.
#   CQT_SECRET_SCAN_ALLOWLIST_FILE=<p>  use this config instead of the shipped one.
#   CQT_SECRET_SCAN_TIMEOUT=N           seconds any one pass may take (default 300).
#
# The budget is enforced with timeout(1), NOT with gitleaks' own --timeout. That is
# deliberate and measured: gitleaks 8.30.1 given its own --timeout writes a
# well-formed EMPTY report, logs "partial scan completed" to stderr and exits 1, so
# a caller that reasons "report present, parses, length 0" calls a truncated scan a
# clean tree. timeout(1) exits 124 and writes nothing, which cannot be mistaken for
# a result. The cost of that choice is that on a machine WITHOUT timeout(1) there is
# no budget at all: the pass runs unbounded, and the scope line the gate prints says
# so rather than naming a limit nothing is enforcing.

# Directory this library was sourced from, resolved once. Used only to find the
# shipped allowlist template.
CQT_SECRET_SCAN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -n "$CQT_SECRET_SCAN_LIB_DIR" ] || CQT_SECRET_SCAN_LIB_DIR="."

# Path to the gitleaks config that carries the vendored-path allowlist. Never
# applied unless CQT_SECRET_SCAN_ALLOWLIST=vendored asks for it: an allowlist
# suppresses findings, and a default that silently filters is the same false clean
# the rest of this suite refuses.
cqt_gitleaks_allowlist_path() {
    if [ -n "${CQT_SECRET_SCAN_ALLOWLIST_FILE:-}" ]; then
        printf '%s' "$CQT_SECRET_SCAN_ALLOWLIST_FILE"
        return 0
    fi
    printf '%s' "${CQT_SECRET_SCAN_LIB_DIR}/../../templates/gitleaks-vendored-allowlist.toml"
    return 0
}

# WHICH gitleaks config will actually filter this scan, and where it came from.
# Echoes "<source>|<config path>", where source is one of:
#
#   vendored  our own opt-in, put on the command line by cqt_gitleaks_argv.
#   env       GITLEAKS_CONFIG is set in the environment.
#   repo      the audited directory holds a .gitleaks.toml.
#   none      nothing is filtering; the path half is empty.
#
# ── why this cannot be inferred from cqt_gitleaks_argv ────────────────────────
#
# It used to be. The disclosure was tied to CQT_SECRET_SCAN_ALLOWLIST=vendored on
# the reasoning that "the allowlist only reaches the command line through
# cqt_gitleaks_argv, so the disclosure is tied to the same condition that puts it
# there". MEASURED ON 8.30.1, THAT IS FALSE: gitleaks loads a config from two
# places nobody here passes.
#
#   no config anywhere                          findings: 1
#   <source>/.gitleaks.toml allowlisting *.js   findings: 0
#   GITLEAKS_CONFIG=<file> allowlisting *.js    findings: 0
#
# In both zero cases our argv never mentioned a config. End to end the gate then
# printed "No secrets detected", counted Critical: 0, and recorded
# allowlist:"none" about a repository whose committed secret had been silently
# filtered - a report making a POSITIVE FALSE CLAIM, which is worse than the
# silence it replaced. So the disclosure is driven by what is actually in force.
#
# The order below is gitleaks' own precedence, measured rather than read off the
# documentation, by pointing two configs at one scan and seeing which one won:
#
#   --config <file>          beats GITLEAKS_CONFIG          (1 finding vs 0)
#   --config <file>          beats <source>/.gitleaks.toml  (1 finding vs 0)
#   GITLEAKS_CONFIG=<file>   beats <source>/.gitleaks.toml  (1 finding vs 0)
#
# It is the SOURCE directory's .gitleaks.toml, not the current directory's: a
# .gitleaks.toml beside the caller but outside the scanned path had no effect
# (1 finding). Every scan this suite builds passes the audited directory as the
# source, so the two coincide here, and the check reads <path> for that reason.
#
# What this does NOT claim: that a named config is necessarily suppressing
# anything. A .gitleaks.toml that only ADDS rules filters nothing, and this
# reports it anyway. Naming a config that turned out to be harmless costs a line
# of output; staying silent about one that suppressed a live credential is the
# defect. Parsing the TOML to decide which it is would be a second, weaker
# guess in place of a fact.
#
#   cqt_gitleaks_effective_config <path>
cqt_gitleaks_effective_config() {
    local path="${1:-.}"
    if [ "${CQT_SECRET_SCAN_ALLOWLIST:-}" = "vendored" ]; then
        printf 'vendored|%s' "$(cqt_gitleaks_allowlist_path)"
        return 0
    fi
    if [ -n "${GITLEAKS_CONFIG:-}" ]; then
        printf 'env|%s' "$GITLEAKS_CONFIG"
        return 0
    fi
    if [ -f "${path%/}/.gitleaks.toml" ]; then
        printf 'repo|%s/.gitleaks.toml' "${path%/}"
        return 0
    fi
    printf 'none|'
    return 0
}

# Does this --log-opts value carry SHELL QUOTING that gitleaks will destroy?
#
# Returns 0 (yes, refuse it) or 1 (no).
#
# What it sees, and it is the whole of what was measured to fail: a single or double
# quote character anywhere in the value. gitleaks splits --log-opts on whitespace and
# hands the pieces to `git log` without a shell, so a quote reaches git as a literal
# character. `--log-opts="--all -- ':(exclude)x'"` scans zero bytes and exits 0.
#
# What it deliberately does NOT refuse, and why the earlier version of this guard was
# wrong to: a bare `--` token and a token starting with `:` survive the whitespace
# split intact. `--all -- :(exclude)removed.js` is measured to scope the scan
# correctly - it is the spelling that works, not the spelling that fails. Refusing it
# and blaming pathspecs told the operator something untrue about what they typed.
#
# What it cannot see, stated plainly rather than implied away: a value whose quoting
# problem is not spelled with quote characters. A pathspec containing a `*` that the
# CALLER's shell already expanded, for example, arrives here as ordinary words and is
# passed through. The claim is "a value carrying quote characters is refused", not
# "every way of mis-scoping a scan is caught".
cqt_gitleaks_log_opts_is_unsafe() {
    local s="$1" hit=1
    case "$s" in
        *\'*|*\"*) hit=0 ;;
    esac
    return "$hit"
}

# The base a diff-scoped run falls back to when CQT_SECRET_SCAN_BASE is unset.
# Echoes a commit sha, or nothing when no upstream ref resolves. Nothing is a
# refusal, not a licence to scan everything: an unbounded history scan nobody asked
# for is an hour of CPU per CI run on the repository this came from.
cqt_gitleaks_default_base() {
    local path="${1:-.}" ref mb head
    head="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
    for ref in origin/HEAD origin/main origin/master upstream/main upstream/master main master; do
        if ! git -C "$path" rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1; then
            continue
        fi
        mb="$(git -C "$path" merge-base HEAD "$ref" 2>/dev/null || true)"
        if [ -z "$mb" ]; then
            continue
        fi
        # A base equal to HEAD is an empty range, which would scan nothing and
        # report a clean result for a scan that covered no commit at all.
        if [ "$mb" = "$head" ]; then
            continue
        fi
        printf '%s' "$mb"
        return 0
    done
    printf ''
    return 0
}

# How many commits does this `git log` argument string select? Echoes a count, or
# the word "error" when git refused the arguments.
#
# `--no-patch --format=%H` goes BEFORE the caller's string so a `--` pathspec
# separator in that string still ends the option list where the caller meant it to.
# Globbing is disabled around the word split: a `*` in the value would otherwise be
# expanded against the audited directory before git ever saw it.
cqt_gitleaks_range_commits() {
    local path="${1:-.}" logopts="${2-}" out rc=0
    local _noglob=0
    case "$-" in *f*) _noglob=1 ;; esac
    set -f
    # shellcheck disable=SC2086
    out="$(git -C "$path" log --no-patch --format=%H $logopts 2>/dev/null)" || rc=$?
    if [ "$_noglob" -eq 0 ]; then set +f; fi
    if [ "$rc" -ne 0 ]; then
        printf 'error'
        return 0
    fi
    if [ -z "$out" ]; then
        printf '0'
        return 0
    fi
    # wc, not `grep -c`: grep exits 1 when its count is zero, which aborts the caller
    # under set -e for a result that is not an error.
    printf '%s\n' "$out" | wc -l | tr -d ' \n'
    return 0
}

# Did the commits this pass covered ADD or MODIFY any file? Echoes the first such
# path, or nothing. Always returns 0.
#
# This exists for one decision: a pass that scanned ZERO BYTES was either BLINDED or
# had nothing to read, and those need opposite verdicts. The obvious checks do not
# separate them, which is why this one is spelled the way it is. Measured, on a
# fixture carrying `* -diff` whose range ADDS a file, against an honest range of pure
# deletions:
#
#                                              blinded+add     pure deletion
#   git log --format= --numstat --text         -  -  s.js      0  1  s.js
#   git log --format= --shortstat --text       0 insertions    0 insertions
#   git log --format= --name-only              s.js            s.js
#   git log --format= --name-only --diff-filter=AM   s.js      (empty)
#
# Only the last row separates them. --numstat is the trap: a `-diff` attribute makes
# git report the file as BINARY, and binary files print "-" for both counts even
# under --text, so the blinded case is indistinguishable from a zero-insertion one.
# --diff-filter=AM asks a different question - did any file get added or modified -
# which the attribute does not affect, because it is answered from the tree diff
# rather than from rendered patch text.
#
# `awk NF{print;exit}` and not `head -1`: --format= prints an empty line per commit,
# so the first line of output can be blank even when files follow, and `grep -m1`
# would exit 1 on no match and abort a caller running under set -e.
#
#   cqt_gitleaks_range_added <path> <log-opts>
cqt_gitleaks_range_added() {
    local path="${1:-.}" logopts="${2-}" out
    local _noglob=0
    case "$-" in *f*) _noglob=1 ;; esac
    set -f
    # shellcheck disable=SC2086
    out="$(git -C "$path" log --format= --name-only --diff-filter=AM $logopts 2>/dev/null \
           | awk 'NF{print; exit}')"
    if [ "$_noglob" -eq 0 ]; then set +f; fi
    printf '%s' "$out"
    return 0
}

# Resolve what this run will cover. Sets, and only ever sets:
#
#   CQT_GL_STATUS  ok | bad_mode | no_allowlist | log_opts_without_history |
#                  quoted_log_opts | bad_log_opts | no_git_repo | no_commits |
#                  no_base | empty_range
#   CQT_GL_MODE    the requested mode
#   CQT_GL_RANGE   the value handed to --log-opts, empty for an unbounded pass
#   CQT_GL_RANGE_KIND  what that value IS: "base" for a base..HEAD range this
#                  function resolved, "selector" for an operator-supplied
#                  CQT_SECRET_SCAN_LOG_OPTS string, empty for an unbounded pass.
#                  The caller needs the distinction to describe the scan
#                  truthfully: CQT_SECRET_SCAN=diff with
#                  CQT_SECRET_SCAN_LOG_OPTS='--all' discards the resolved base and
#                  hands git a selector, so the diff wording ("the commit range X;
#                  git history before the base was not scanned") described a
#                  bounded scan while ALL of history had in fact been read.
#   CQT_GL_REASON  a sentence for the operator, empty when status is ok
#
# Any status other than ok means the scan the operator asked for CANNOT be run.
# The caller records a skip; it must not quietly fall back to a narrower scan and
# report the result as if the requested one had happened.
#
# Always returns 0, so a caller under `set -e` decides on the status rather than
# being aborted by it.
cqt_gitleaks_plan() {
    local path="${1:-.}"
    CQT_GL_STATUS="ok"
    CQT_GL_MODE="tree"
    CQT_GL_RANGE=""
    CQT_GL_RANGE_KIND=""
    CQT_GL_REASON=""

    local want="${CQT_SECRET_SCAN:-tree}"
    CQT_GL_MODE="$want"
    case "$want" in
        tree|history|diff) ;;
        *)
            # A typo'd mode that silently degraded to a working-tree scan is the
            # exact false clean this file exists to remove.
            CQT_GL_STATUS="bad_mode"
            CQT_GL_REASON="CQT_SECRET_SCAN='${want}' is not one of tree, history, diff"
            return 0
            ;;
    esac

    if [ "${CQT_SECRET_SCAN_ALLOWLIST:-}" = "vendored" ]; then
        local tpl
        tpl="$(cqt_gitleaks_allowlist_path)"
        if [ ! -f "$tpl" ]; then
            CQT_GL_STATUS="no_allowlist"
            CQT_GL_REASON="CQT_SECRET_SCAN_ALLOWLIST=vendored, but ${tpl} does not exist"
            return 0
        fi
    fi

    local logopts="${CQT_SECRET_SCAN_LOG_OPTS:-}"
    if [ -n "$logopts" ]; then
        if [ "$want" = "tree" ]; then
            # Honouring nothing while the operator believes they scoped something is
            # how the --log-opts trap works in the first place. Say so instead.
            CQT_GL_STATUS="log_opts_without_history"
            CQT_GL_REASON="CQT_SECRET_SCAN_LOG_OPTS is set but CQT_SECRET_SCAN is 'tree', which reads no history at all"
            return 0
        fi
        if cqt_gitleaks_log_opts_is_unsafe "$logopts"; then
            CQT_GL_STATUS="quoted_log_opts"
            CQT_GL_REASON="CQT_SECRET_SCAN_LOG_OPTS contains a quote character; gitleaks splits --log-opts on whitespace and passes the pieces to git without a shell, so the quotes arrive as literal characters, the value matches nothing, and the pass scans zero bytes while exiting 0. Remove the quotes (an unquoted pathspec such as '--all -- :(exclude)vendor' scopes correctly), or filter the report with CQT_SECRET_SCAN_ALLOWLIST=vendored"
            return 0
        fi
    fi

    if [ "$want" = "tree" ]; then
        return 0
    fi

    # history and diff both read git, so a directory that is not a working tree
    # cannot answer them. Read the ANSWER, not the exit status: rev-parse prints
    # "false" and exits 0 inside a .git directory and in a bare repository.
    if [ "$(git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
        CQT_GL_STATUS="no_git_repo"
        CQT_GL_REASON="CQT_SECRET_SCAN=${want} needs a git working tree, and '${path}' is not one"
        return 0
    fi
    if ! git -C "$path" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        CQT_GL_STATUS="no_commits"
        CQT_GL_REASON="CQT_SECRET_SCAN=${want} needs history, and this repository has no commits yet"
        return 0
    fi

    # An operator-supplied --log-opts that selects NO COMMIT is the same hazard as a
    # base equal to HEAD: the pass runs, covers nothing, and reports a clean result
    # for a scan that read no commit at all. Checked once here, against git itself,
    # for both history and diff.
    if [ -n "$logopts" ]; then
        local n_commits
        n_commits="$(cqt_gitleaks_range_commits "$path" "$logopts")"
        if [ "$n_commits" = "error" ]; then
            CQT_GL_STATUS="bad_log_opts"
            CQT_GL_REASON="git rejected CQT_SECRET_SCAN_LOG_OPTS='${logopts}', so the ${want} pass would scan nothing"
            return 0
        fi
        if [ "$n_commits" = "0" ]; then
            CQT_GL_STATUS="empty_range"
            CQT_GL_REASON="CQT_SECRET_SCAN_LOG_OPTS='${logopts}' selects no commit, so the ${want} pass would cover nothing and report it as clean"
            return 0
        fi
    fi

    if [ "$want" = "history" ]; then
        # Empty range means every commit reachable from every ref.
        CQT_GL_RANGE="$logopts"
        if [ -n "$logopts" ]; then CQT_GL_RANGE_KIND="selector"; fi
        return 0
    fi

    local base="${CQT_SECRET_SCAN_BASE:-}"
    local derived=0
    if [ -z "$base" ]; then
        base="$(cqt_gitleaks_default_base "$path")"
        derived=1
    fi
    if [ -z "$base" ]; then
        CQT_GL_STATUS="no_base"
        CQT_GL_REASON="CQT_SECRET_SCAN=diff needs a base commit; set CQT_SECRET_SCAN_BASE (no upstream ref resolved here)"
        return 0
    fi
    local resolved
    resolved="$(git -C "$path" rev-parse --verify --quiet "${base}^{commit}" 2>/dev/null || true)"
    if [ -z "$resolved" ]; then
        CQT_GL_STATUS="no_base"
        if [ "$derived" -eq 1 ]; then
            CQT_GL_REASON="CQT_SECRET_SCAN=diff derived the base '${base}', which does not resolve to a commit"
        else
            CQT_GL_REASON="CQT_SECRET_SCAN_BASE='${base}' does not resolve to a commit"
        fi
        return 0
    fi
    if [ -n "$logopts" ]; then
        # The resolved base is DISCARDED here: gitleaks takes one --log-opts string,
        # and the operator's is the one that reaches git. The range is therefore
        # whatever they selected, which may be wider than a base..HEAD range and may
        # not be a range at all, so it is tagged as a selector and the caller says
        # "selected by" rather than "the commit range ... before the base".
        CQT_GL_RANGE="$logopts"
        CQT_GL_RANGE_KIND="selector"
        return 0
    fi
    # The same refusal cqt_gitleaks_default_base applies to a DERIVED base, applied
    # here to an operator-supplied one. CQT_SECRET_SCAN_BASE=$CI_COMMIT_SHA is an
    # ordinary CI misconfiguration, and `<HEAD>..HEAD` is an empty range: the pass
    # runs, covers no commit, and its clean result says nothing at all.
    local head_sha
    head_sha="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
    if [ -n "$head_sha" ] && [ "$resolved" = "$head_sha" ]; then
        CQT_GL_STATUS="empty_range"
        CQT_GL_REASON="CQT_SECRET_SCAN_BASE='${base}' resolves to HEAD, so the range is empty and the diff pass would cover no commit at all"
        return 0
    fi
    CQT_GL_RANGE="${resolved}..HEAD"
    CQT_GL_RANGE_KIND="base"
    return 0
}

# The `git log` flags every history or diff pass carries, appended to whatever range
# or pathspec the plan resolved.
#
#   --text          render every blob as text. WITHOUT IT a `-diff` or `binary`
#                   attribute in .gitattributes makes git emit "Binary files ...
#                   differ" and no content, so the pass reads ZERO BYTES, finds
#                   nothing and exits 0 - a clean history that was never read.
#                   Measured: `* -diff` turns a two-secret fixture into 0 commits,
#                   ~0 bytes, "no leaks found".
#   --no-textconv   a textconv filter configured in .gitattributes would otherwise
#                   replace the blob with whatever that filter prints.
#   -p -U0          the patch form gitleaks parses, with no context lines. gitleaks
#                   supplies these itself when --log-opts is absent (measured: a
#                   --log-opts value without -p still produces findings), so stating
#                   them keeps the pass identical whether or not a range was given
#                   and matches core/secret-history.sh's own walk.
#   --full-history  turns OFF git's history simplification. It changes nothing when
#                   no pathspec is in play, and matters once one is: with a pathspec
#                   git normally prunes commits it considers uninteresting for that
#                   path, and a secret scan wants the commits, not a readable log.
#                   Widening what is walked is the safe direction here.
#
# `--all` is added only for an UNBOUNDED history pass: every commit reachable from
# every ref, which is the ground that pass says it covers.
CQT_GITLEAKS_LOG_FLAGS="--full-history --text --no-textconv -p -U0"

# The command line for ONE pass, one argument per line.
#
# This is the single place gitleaks' flags are decided, so the opt-in allowlist
# reaches the real scan rather than only the builder. Callers read it into an array
# and execute that array; the audit suite reads the same function, so the asserted
# command and the executed command cannot drift apart.
#
# One argument per line means an argument containing a newline is not
# representable. Nothing here can produce one: the only caller-supplied value that
# reaches argv is CQT_GL_RANGE, which cqt_gitleaks_plan has already validated.
#
#   cqt_gitleaks_argv <tree|history|diff> <path> <report-path>
cqt_gitleaks_argv() {
    local pass="$1" path="${2:-.}" report="$3"
    local -a a=()
    case "$pass" in
        tree)         a=(gitleaks dir "$path") ;;
        history|diff) a=(gitleaks git "$path") ;;
        *)            return 0 ;;
    esac
    # --redact is not optional anywhere in this suite: the report is written to a
    # path that can end up inside the audited repository, and an audit must not be
    # the thing that commits the credential it just found.
    a+=(--redact --report-format json --report-path "$report" --no-banner)
    case "$pass" in
        history|diff)
            # The flags go FIRST, ahead of whatever the plan resolved. A --log-opts
            # value may legitimately end in a `--` pathspec separator, and anything
            # appended after that separator reaches git as a PATHSPEC rather than as
            # an option: `--all -- :(exclude)x --text` asks git for a file named
            # --text and scans zero bytes. Measured both ways.
            if [ -n "${CQT_GL_RANGE:-}" ]; then
                a+=("--log-opts=${CQT_GITLEAKS_LOG_FLAGS} ${CQT_GL_RANGE}")
            else
                a+=("--log-opts=${CQT_GITLEAKS_LOG_FLAGS} --all")
            fi
            ;;
    esac
    if [ "${CQT_SECRET_SCAN_ALLOWLIST:-}" = "vendored" ]; then
        a+=(--config "$(cqt_gitleaks_allowlist_path)")
    fi
    printf '%s\n' "${a[@]}"
    return 0
}

# Merge gitleaks reports into one array on stdout, deduplicated.
#
# The same secret in the same place is reported once by the working-tree pass and
# again by every commit that carried it, so overlapping passes must be merged or a
# two-pass run would multiply-count what a one-pass run counted once.
#
# ── the key, and exactly what it does and does not guarantee ──────────────────
#
# THE RULE THIS OBEYS: never collapse two records that could be DIFFERENT
# CREDENTIALS. Over-reporting is a nuisance; dropping a live credential from the
# report is the failure this whole file exists to prevent.
#
# The obvious key - gitleaks' Fingerprint with the commit sha stripped, i.e.
# file:rule:startline - IDENTIFIES A LOCATION, NOT A SECRET, and a rotated
# credential is the single most common history case: two distinct values at the same
# coordinates in two commits. Measured, that key collapsed both into one record,
# dropping the old value entirely and attributing the surviving one to the wrong
# commit. The old credential is still live at the provider unless separately revoked,
# and is in every clone.
#
# Keying on the VALUE is not available: every invocation carries --redact, so Secret
# and Match arrive as the literal string "REDACTED".
#
# ── why entropy is NOT what separates two values ──────────────────────────────
#
# The previous key was File:RuleID:StartLine:Entropy, and the limitation it recorded
# was "two different values built from the same multiset of characters - an anagram,
# a reordered token". That understates the hole by a wide margin. Shannon entropy is
# a function of character FREQUENCIES ONLY, not of which characters they are, so two
# tokens that share no characters at all collide exactly. Measured against gitleaks
# 8.30.1: ghp_ + 18 distinct lowercase letters each doubled, and ghp_ + 18 entirely
# different characters each doubled, both report Entropy 4.421928 while sharing only
# the four characters of the rule prefix. Sampling 20,000 random tokens at gitleaks'
# printed float32 precision puts the collision rate at 1.2% for 32-char hex and 3.5%
# for 40-char base62 - not a corner case, a few percent of every rotated credential.
# End to end on a rotation fixture built from that pair, gitleaks reported two
# history records plus a tree record and the merge produced ONE finding: the older
# credential gone from the report, the survivor carrying the new value's coordinates
# with the old value's commit.
#
# So entropy is not in the key at all, and the drop-safety property no longer rests
# on it.
#
#   coordinate key = File : RuleID : StartLine : StartColumn : EndColumn
#
# StartColumn and EndColumn are in the key because two different secrets can sit on
# ONE line under one rule, and their spans are what tells them apart. Measured, the
# `dir` pass and the `git` pass agree on those columns for the same secret (12-51 for
# a token at the same offset in both, and 10-49 for an indented one), so including
# them does not stop a tree record merging with its own history record.
#
# ── the rule the grouping enforces ────────────────────────────────────────────
#
# Within one set of coordinates: A TREE RECORD MAY COLLAPSE WITH AT MOST ONE HISTORY
# RECORD, THE MOST RECENT ONE. The value sitting in the working tree is the one the
# latest commit put there, so that pairing is the only one that can be justified.
# Every EARLIER history record at those coordinates stays a separate finding, because
# nothing available here can show it holds the same value - and a record that might
# be a different credential is reported, never merged away.
#
# WHAT THAT GUARANTEES: no history record is ever dropped because its value happened
# to resemble another one, by entropy or by anything else. Two identical duplicates
# of the SAME record - same commit, same coordinates - still collapse, which is all
# the deduplication that was ever needed between overlapping passes.
# WHAT IT DOES NOT: it does not tell one credential from two. A secret that was
# added, deleted and later re-added unchanged at the same line produces two history
# records and is now counted twice. That is the deliberate direction: over-report,
# never drop. The count is therefore an upper bound on the number of distinct
# credentials, and phase 2's own full walk is what supplies the accurate
# first_seen_commit for anything still present in the tree.
#
# The key also includes StartLine, so ONE secret whose line number moved between
# commits is counted TWICE, for the same reason and with the same trade.
#
# The record kept for a tree-seen finding is the WORKING-TREE one, because its line
# and column span are working-tree coordinates and phase 2 needs those to recover the
# value. Its commit attribution comes from the most recent history record at those
# coordinates. A history-only finding keeps its own record, coordinates and all.
#
# NO COUNT IS EMITTED HERE, and that is the honest answer rather than a missing
# feature. Each record out of this merge is ONE INTRODUCTION EVENT, not a count of
# the commits that carried the value: this pass sees the commits it was given, keys
# on coordinates rather than on the value (--redact leaves nothing else to key on),
# and deliberately over-reports rotations. The field that used to sit here,
# CqtCommitCount, was 1 on every record and cqt_gitleaks_history_backfill copied it
# straight into the user-visible commit_count, so a secret whose value is in two
# commits was reported as "1 commit(s)". It was removed rather than renamed, because
# nothing reads it and a stored 1 is one refactor away from being believed again.
# Counting is phase 2's job: it walks all of history for the recovered VALUE.
#
# Echoes nothing on failure, which the caller treats as an unusable scan.
cqt_gitleaks_merge() {
    local -a present=()
    local f
    for f in "$@"; do
        if [ -f "$f" ] && [ -s "$f" ]; then
            present+=("$f")
        fi
    done
    if [ "${#present[@]}" -eq 0 ]; then
        printf '[]'
        return 0
    fi
    jq -s '
        [ .[] | .[]? ]
        | map(. + {__cqtkey: (
              (.File // "") + ":" + (.RuleID // "") + ":"
              + ((.StartLine // 0) | tostring) + ":"
              + ((.StartColumn // 0) | tostring) + ":"
              + ((.EndColumn // 0) | tostring))})
        | group_by(.__cqtkey)
        | map(
            # Tree records carry no Commit; history records do. That is what the
            # two passes are told apart by, here and in CqtTreeSeen.
            ( [ .[] | select((.Commit // "") == "") ] ) as $t
            # One entry per introduction event. group_by collapses records that are
            # LITERALLY the same finding reported twice - same commit at the same
            # coordinates, which is what an --all walk over a repository whose
            # commit is reachable from several refs can produce - and collapses
            # nothing else. Ascending by Date, so the last element is the most
            # recent commit at these coordinates.
            | ( [ .[] | select((.Commit // "") != "") ]
                | group_by((.Commit // "") + ":" + ((.Entropy // 0) | tostring))
                | map(.[0])
                | sort_by(.Date // "") ) as $h
            | ( if ($h | length) > 0 then $h[-1] else null end ) as $newest
            | ( if ($t | length) > 0
                then
                  # The working-tree record, attributed to the commit that put the
                  # CURRENT value there. Every older record at these coordinates is
                  # emitted separately below rather than folded in here.
                  [ ( $t[0]
                      + { CqtTreeSeen: true }
                      + ( if $newest != null
                          then { Commit: $newest.Commit,
                                 Author: $newest.Author,
                                 Email: $newest.Email,
                                 Date: $newest.Date,
                                 Message: $newest.Message }
                          else {} end ) ) ]
                  + [ $h[0:-1][] | . + { CqtTreeSeen: false } ]
                else
                  # Nothing in the tree at these coordinates, so there is no record
                  # any history record is entitled to merge into. Each stands alone.
                  [ $h[] | . + { CqtTreeSeen: false } ]
                end ) )
        | add // []
        | map(del(.__cqtkey))
        | sort_by(.File // "", .StartLine // 0, .RuleID // "")
    ' "${present[@]}" 2>/dev/null || printf ''
    return 0
}

# Remove any per-mode report left beside a merged report by an earlier run.
#
# cqt_gitleaks_extra_scan merges gitleaks-<mode>.json into gitleaks.json and then
# deletes it, so nothing is left to go stale. This exists for the OTHER direction:
# a `history` run followed by a `tree` run would otherwise leave last week's
# gitleaks-history.json sitting beside a current, tree-only gitleaks.json, where the
# next reader has no way to tell it is not part of this run's result.
#
#   cqt_gitleaks_clear_extra <merged-report-path>
cqt_gitleaks_clear_extra() {
    local merged="$1" dir mode
    dir="$(dirname "$merged")"
    for mode in tree history diff; do
        rm -f "${dir}/gitleaks-${mode}.json" "${dir}/gitleaks-${mode}.log" 2>/dev/null
    done
    return 0
}

# Run the history or diff pass and merge it into the working-tree report.
#
# Sets CQT_GL_EXTRA_STATUS (ok|failed), CQT_GL_EXTRA_REASON, CQT_GL_MERGED_COUNT
# (the deduplicated total across both passes) and CQT_GL_EXTRA_BYTES (the bytes
# gitleaks reported scanning, or -1 when it did not say). Always returns 0.
#
#   cqt_gitleaks_extra_scan <path> <merged-report-path>
cqt_gitleaks_extra_scan() {
    local path="${1:-.}" merged="$2"
    CQT_GL_EXTRA_STATUS="ok"
    CQT_GL_EXTRA_REASON=""
    CQT_GL_MERGED_COUNT=0
    CQT_GL_EXTRA_BYTES=-1

    # A helper that cannot answer degrades to an explicit failure; it never takes
    # the security gate down with it.
    local _errexit=0
    case "$-" in *e*) _errexit=1 ;; esac
    set +e

    local budget="${CQT_SECRET_SCAN_TIMEOUT:-300}"
    local dir extra errlog rc n arg out
    dir="$(dirname "$merged")"
    extra="${dir}/gitleaks-${CQT_GL_MODE}.json"
    errlog="${dir}/gitleaks-${CQT_GL_MODE}.log"

    rm -f "$extra" "$errlog" 2>/dev/null
    if [ -e "$extra" ]; then
        # A report from an earlier run that cannot be removed cannot be told apart
        # from this run's. Unprovable provenance is not a result.
        CQT_GL_EXTRA_STATUS="failed"
        CQT_GL_EXTRA_REASON="a ${CQT_GL_MODE} report from an earlier run could not be removed"
        if [ "$_errexit" -eq 1 ]; then set -e; fi
        return 0
    fi

    local -a argv=() runner=()
    while IFS= read -r arg; do
        argv+=("$arg")
    done < <(cqt_gitleaks_argv "$CQT_GL_MODE" "$path" "$extra")
    if [ "${#argv[@]}" -lt 3 ]; then
        CQT_GL_EXTRA_STATUS="failed"
        CQT_GL_EXTRA_REASON="no command line could be built for the ${CQT_GL_MODE} pass"
        if [ "$_errexit" -eq 1 ]; then set -e; fi
        return 0
    fi
    if command -v timeout >/dev/null 2>&1; then
        runner=(timeout "$budget")
    fi

    # gitleaks' progress log goes to stderr and is kept only long enough to read the
    # byte count out of it. Nothing in it is a secret value: every invocation this
    # file builds carries --redact, so the report holds "REDACTED" and the log holds
    # counts, paths and timings. The file is removed a few lines below either way.
    "${runner[@]}" "${argv[@]}" >/dev/null 2>"$errlog"
    rc=$?

    # HOW MUCH GROUND THE PASS ACTUALLY COVERED, read from gitleaks itself.
    # "INF scanned ~116 bytes (116 bytes) in 27.4ms" on 8.30.1. -1 means it did not
    # say, which is treated below as "cannot be shown to have covered anything".
    CQT_GL_EXTRA_BYTES=-1
    if [ -f "$errlog" ]; then
        CQT_GL_EXTRA_BYTES="$(sed -n 's/.*scanned ~\([0-9][0-9]*\) bytes.*/\1/p' "$errlog" 2>/dev/null | tail -1)"
        case "$CQT_GL_EXTRA_BYTES" in ''|*[!0-9]*) CQT_GL_EXTRA_BYTES=-1 ;; esac
    fi
    rm -f "$errlog" 2>/dev/null

    n=-1
    if [ -f "$extra" ] && [ -s "$extra" ]; then
        n=$(jq 'if type == "array" then length else -1 end' "$extra" 2>/dev/null)
        case "$n" in ''|*[!0-9-]*) n=-1 ;; esac
    fi

    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
        CQT_GL_EXTRA_STATUS="failed"
        CQT_GL_EXTRA_REASON="the ${CQT_GL_MODE} pass ran past its budget (CQT_SECRET_SCAN_TIMEOUT=${budget}s) and was killed, so nothing about history is proven"
    elif [ "$rc" -ge 2 ]; then
        CQT_GL_EXTRA_STATUS="failed"
        CQT_GL_EXTRA_REASON="the ${CQT_GL_MODE} pass exited ${rc}"
    elif [ "$rc" -eq 1 ] && [ "$n" -le 0 ]; then
        # gitleaks fatals through os.Exit(1), and it also writes a well-formed EMPTY
        # report when its own budget expires. Exit 1 with nothing in the report is
        # therefore a failed or truncated scan, never a clean one.
        CQT_GL_EXTRA_STATUS="failed"
        CQT_GL_EXTRA_REASON="the ${CQT_GL_MODE} pass exited 1 with an empty or unreadable report - a failed or partial scan, not a clean history"
    elif [ "$rc" -eq 0 ] && [ "$n" -lt 0 ]; then
        CQT_GL_EXTRA_STATUS="failed"
        CQT_GL_EXTRA_REASON="the ${CQT_GL_MODE} pass exited 0 but wrote no readable report"
    elif [ "$n" -eq 0 ] && [ "$CQT_GL_EXTRA_BYTES" -le 0 ]; then
        # A WELL-FORMED EMPTY REPORT FROM A PASS THAT READ NOTHING. This is what a
        # `-diff` or `binary` attribute in .gitattributes used to produce: git emits
        # "Binary files ... differ" instead of content, gitleaks scans ~0 bytes,
        # writes `[]` and exits 0, and the run reported a clean history it had never
        # read. --text --no-textconv now prevents that, and this refuses to call the
        # result clean if it ever happens again for any other reason.
        #
        # ── the one honest case, now told apart instead of accepted ────────────
        #
        # A BOUNDED range whose commits are pure deletions adds no content, so
        # gitleaks scans zero bytes there too and an honest CI run got a [SKIP]. That
        # is no longer indistinguishable from the blinded case: git is asked whether
        # the range added or modified any file at all. Non-empty plus zero scanned
        # bytes means something stopped the pass reading content that exists, which
        # is a failure. Empty means the range genuinely had nothing to offer, which
        # is a clean result over a range that covered what it said it did. See
        # cqt_gitleaks_range_added for why --diff-filter=AM is the check that works
        # and --numstat is not.
        #
        # UNBOUNDED passes are excluded on purpose. `--all` over a repository with any
        # commit in it always has content somewhere, so zero bytes there is never the
        # honest case, and there is no range to ask git about.
        local _added=""
        if [ "$CQT_GL_EXTRA_BYTES" -eq 0 ] && [ -n "${CQT_GL_RANGE:-}" ]; then
            _added="$(cqt_gitleaks_range_added "$path" "$CQT_GL_RANGE")"
        fi
        if [ "$CQT_GL_EXTRA_BYTES" -eq 0 ] && [ -n "${CQT_GL_RANGE:-}" ] && [ -z "$_added" ]; then
            : # Nothing was added or modified in the range, so nothing was there to
              # scan. The pass covered the ground it claimed; the result stands.
        else
            CQT_GL_EXTRA_STATUS="failed"
            if [ "$CQT_GL_EXTRA_BYTES" -eq 0 ]; then
                CQT_GL_EXTRA_REASON="the ${CQT_GL_MODE} pass found nothing after scanning ZERO bytes, so it covered no history at all - check .gitattributes for a -diff or binary attribute, and check that the range selects commits that add content"
            else
                CQT_GL_EXTRA_REASON="the ${CQT_GL_MODE} pass found nothing and did not report how many bytes it scanned, so it cannot be shown to have covered any history"
            fi
        fi
    fi

    if [ "$CQT_GL_EXTRA_STATUS" != "ok" ]; then
        rm -f "$extra" 2>/dev/null
        if [ "$_errexit" -eq 1 ]; then set -e; fi
        return 0
    fi

    out="$(cqt_gitleaks_merge "$merged" "$extra")"
    if [ -z "$out" ]; then
        CQT_GL_EXTRA_STATUS="failed"
        CQT_GL_EXTRA_REASON="the working-tree and ${CQT_GL_MODE} reports could not be merged"
        if [ "$_errexit" -eq 1 ]; then set -e; fi
        return 0
    fi
    if ! printf '%s' "$out" > "$merged" 2>/dev/null; then
        CQT_GL_EXTRA_STATUS="failed"
        CQT_GL_EXTRA_REASON="the merged report could not be written to ${merged}"
        if [ "$_errexit" -eq 1 ]; then set -e; fi
        return 0
    fi
    CQT_GL_MERGED_COUNT=$(jq 'length' "$merged" 2>/dev/null)
    case "$CQT_GL_MERGED_COUNT" in
        ''|*[!0-9]*)
            CQT_GL_EXTRA_STATUS="failed"
            CQT_GL_EXTRA_REASON="the merged report does not parse"
            CQT_GL_MERGED_COUNT=0
            ;;
    esac
    # Everything in the per-mode report is now inside the merged one. Leaving it
    # behind would put a second, partial report next to the real one, which the next
    # run has no way to tell apart from its own output.
    rm -f "$extra" 2>/dev/null

    if [ "$_errexit" -eq 1 ]; then set -e; fi
    return 0
}

# Fill in the history fields phase 2 structurally cannot supply.
#
# core/secret-history.sh recovers the secret VALUE from working-tree coordinates
# and then walks history for it. A finding that is only in history has no file in
# the working tree, so there is no value to recover and phase 2 correctly answers
# "unknown (value_unavailable)". Reporting that as "history could not be checked"
# would be absurd: the finding came OUT of the history scan, which already knows
# the commit, the author and the date.
#
# So the scan's own attribution is used where phase 2 could not answer, and ALSO
# wherever the finding was never seen in the working tree at all (CqtTreeSeen false).
# That second case is not a refinement, it is a correctness fix for the rotated
# credential: two values at the same coordinates produce two findings, and phase 2
# recovers whatever value is at those coordinates NOW, so it answers "found" about
# the CURRENT value for both of them. Its answer is then about a different secret
# than the history-only record it would be attached to, and the report would date an
# old, still-live credential to the commit that replaced it.
#
# Everywhere else phase 2 wins, because its walk covers all of history while a
# bounded pass only knows the range it was given - under CQT_SECRET_SCAN_LOG_OPTS the
# commit recorded here is the earliest one the pass COVERED, not necessarily the
# earliest one that exists.
#
# ── what this backfill can and cannot supply ──────────────────────────────────
#
# It supplies WHERE and WHEN and WHO: the commit, its date and its author, all of
# which the scan observed directly. It supplies NO COUNT. commit_count is emitted as
# null on this path, and the report line says the count was not established rather
# than printing a number.
#
# That is not a rounding-down. Every merged record is one introduction event, so a
# count taken from here would be 1 for every finding regardless of how many commits
# carry the value - measured on a two-commit fixture where `git log -S` over that
# value returns 2, this reported "1 commit(s)". Understating blast radius is the
# failure mode the history fields exist to prevent, and a positive number nothing
# counted is worse than an admitted gap: the remediation reads "1 commit, so one
# rewrite cleans it up".
#
# The value is NOT recovered from the introducing blob to run a real walk. That would
# put a matched secret back into a variable, which is the exact hazard
# core/secret-history.sh is built to contain, for a number that changes no action:
# the verb is ROTATE either way.
#
#   cqt_gitleaks_history_backfill <history_json> <merged_report_path>
cqt_gitleaks_history_backfill() {
    local history="$1" report="$2"
    if [ -z "$history" ] || [ "$history" = "[]" ] || [ ! -f "$report" ]; then
        printf '%s' "$history"
        return 0
    fi
    jq -n --argjson h "$history" --slurpfile r "$report" '
        (($r[0]) // []) as $rep
        | [ range(0; ($h | length)) as $i
            | $h[$i] as $e
            | ($rep[$i] // {}) as $g
            | ( if (($g.Commit // "") != "") then
                  { history_status: "found",
                    history_reason: "history_scan",
                    # NULL, NOT A NUMBER. See the note above the function: this pass
                    # knows the commit that introduced the finding and does not know
                    # how many commits carry the value, so it says so. A 1 here was a
                    # positive claim nothing had counted.
                    commit_count: null,
                    first_seen_commit: $g.Commit,
                    first_seen_date: (if (($g.Date // "") == "") then null else $g.Date end),
                    author: (if (($g.Author // "") == "") then null else $g.Author end) }
                else null end ) as $scan
            # `== false` and not `// true`: jq treats the boolean false as an empty
            # value, so `false // true` evaluates to true and the whole branch would
            # never fire.
            | if ($scan != null) and ($g.CqtTreeSeen == false) then $scan
              elif ($e.history_status // "") == "found" then $e
              elif $scan != null then $scan
              else $e end ]
    ' 2>/dev/null || printf '%s' "$history"
    return 0
}

# ── item 17: the deploy artifact is a second history ──────────────────────────
#
# `acli push:artifact` commits the BUILT tree to a separate git repository with its
# own remote, its own clones and its own access list. A credential in exported
# config therefore lives in two histories, and every deploy writes it into the
# second one again until the value leaves config. Reporting "found in 44 commits"
# against the source repository alone understates the blast radius and prescribes
# the wrong remediation.
#
# Echoes the artifact kind ("acquia") or nothing.
#
# Two detection routes, both of which say something about THIS REPOSITORY:
#   * a git remote on an Acquia host;
#   * an acli configuration in the project.
#
# A ~/.acquia-cli.yml is deliberately NOT a route. It says the person running the
# audit has Acquia credentials, not that this repository deploys there, and using
# it would put the flag on every project on the machine. A flag that appears
# everywhere gets ignored everywhere.
cqt_deploy_artifact_detect() {
    local path="${1:-.}" remotes
    # The REDACTED remote list from cqt_deploy_artifact_remotes, never `git remote -v`
    # itself. Matching a hostname needs the host and nothing else, and `case` expands
    # its subject under xtrace - so casing on the raw output published any credential
    # embedded in a remote URL to stderr on every traced run. See the redaction note
    # on cqt_deploy_artifact_remotes.
    remotes="$(cqt_deploy_artifact_remotes "$path")"
    case "$remotes" in
        *acquia.com*|*acquia-sites.com*)
            printf 'acquia'
            return 0
            ;;
    esac
    if [ -f "${path}/.acquia-cli.yml" ] || [ -f "${path}/acquia-cli.yml" ]; then
        printf 'acquia'
        return 0
    fi
    printf ''
    return 0
}

# Every remote URL this repository has, space separated, WITH ANY EMBEDDED
# CREDENTIAL REMOVED. Named in the remediation because remediation that names one
# remote leaves the credential live in the other.
#
# ── why the redaction is not optional ─────────────────────────────────────────
#
# `git remote -v` prints the URL verbatim, and a URL carries a userinfo field:
# https://<user>:<password>@host/path. The GitLab-CI and Acquia-pipelines pattern
# puts a LIVE TOKEN there - https://gitlab-ci-token:glpat-...@svn-1234.prod.hosting.
# acquia.com/app.git is an ordinary CI remote, not a contrived one. This string is
# pasted into a printed sentence, into .issues[].remediation inside
# security-report.json, and into the meta block, which are the same three channels
# core/secret-history.sh exists to keep a matched secret out of. An audit must not
# be the thing that writes out the credential it was run to find, so the standing
# contract - no secret to a file, to argv or to stdout, and none under xtrace -
# covers credentials embedded in remote URLs too.
#
# The substitution removes everything between "://" and the LAST "@" of the
# AUTHORITY. `[^/]*` cannot cross a path separator, so, measured:
#   https://tok:pw@host/x    -> https://host/x      stripped
#   https://u:p@ss@host/x    -> https://host/x      stripped; the match runs to the
#                                                   last @, so a password containing
#                                                   an @ leaves no tail behind
#   https://host/path@v1     -> unchanged           no @ in the authority
#   git@github.com:acme/x    -> unchanged           scp-like syntax has no "://" and
#                                                   no password field to carry, and
#                                                   the login name is not a secret
#
# What this does NOT claim: that a remote URL cannot carry a secret anywhere else. A
# token pasted into a PATH segment is not userinfo and is not removed by this.
#
# The redaction runs INSIDE the pipeline, so the raw URL is never the value of a
# shell variable. That placement is the whole point: xtrace publishes every
# assignment bash makes, an exported SHELLOPTS=xtrace is inherited rather than
# typed, and CI logs are kept - so a two-step "read raw, then sanitize" would
# publish the credential on the first step.
cqt_deploy_artifact_remotes() {
    local path="${1:-.}" list
    list="$(git -C "$path" remote -v 2>/dev/null | awk '{print $2}' \
            | sed -E 's#(://)[^/]*@#\1#g' | sort -u | tr '\n' ' ' || true)"
    # Trailing separator trimmed: this string is pasted into a sentence.
    printf '%s' "${list% }"
    return 0
}

# Attach the deploy-artifact fields to the issues array and extend the remediation.
#
# The advice differs by where the finding is. Inside exported configuration the
# value is re-committed by the next deploy whatever else is done, so the config
# exclusion is the load-bearing step and both remotes have to be named. Outside it,
# config_split is not the remedy and saying so anyway is how a report stops being
# read.
#
# ── what the wording may and may not assert ───────────────────────────────────
#
# The detection knows this PROJECT deploys through an artifact. It does not know
# which files the artifact BUILD ships: `acli push:artifact` commits a built tree,
# and test/fixtures/mock.js is in this repository without ever reaching that tree.
# So the sentence is conditional ("a finding in a file that reaches the built
# tree"), not the flat "every finding above also lives in the deploy repository" it
# used to be. That flat form asserted a blast radius nothing here can establish -
# the same over-reach cqt_deploy_artifact_detect refuses one function up when it
# declines to treat a ~/.acquia-cli.yml as evidence about this repository.
#
#   cqt_deploy_artifact_annotate <issues_json> <kind> <remotes>
cqt_deploy_artifact_annotate() {
    local issues="$1" kind="$2" remotes="$3"
    printf '%s' "$issues" | jq --arg kind "$kind" --arg remotes "$remotes" '
        map(
          ((.file // "") | test("(^|/)config/") and test("\\.ya?ml$")) as $exported
          | . + { deploy_artifact: $kind }
              + { remediation: (
                    (.remediation // "")
                    + " This project also deploys through an Acquia build artifact (acli push:artifact), so a value in a file that reaches the built tree also reaches a SECOND git repository with its own clones and access list. Remotes involved: " + $remotes + "."
                    + (if $exported then
                         " The finding is in exported configuration, so every deploy re-commits it: exclude the value with config_split (or config_ignore) and rotate at the provider. Removing it from the source repository alone does not stop it."
                       else
                         " Rotate at the provider and treat the deploy repository as exposed as well."
                       end) ) }
        )' 2>/dev/null || printf '%s' "$issues"
    return 0
}
