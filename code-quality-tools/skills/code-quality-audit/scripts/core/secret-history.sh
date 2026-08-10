#!/bin/bash
# secret-history.sh - phase 2 of secret scanning: CONFIRMATION.
# Part of code-quality-audit skill. Sourced by drupal/security-check.sh and
# nextjs/security-check.sh; never executed directly.
#
# ── why this file exists ──────────────────────────────────────────────────────
#
# "Scan for secrets" is three jobs with wildly different costs:
#
#   phase 1  WORKING TREE   what secrets are in the code right now. Seconds.
#                           `gitleaks detect --no-git` already does this.
#   phase 2  CONFIRMATION   for a secret we ALREADY know about, when did it enter
#                           history, in which commits, by whom. This file.
#   phase 3  DISCOVERY      what secrets are in history that are no longer in the
#                           tree. Expensive; the only phase that needs a
#                           full-history scanner. NOT implemented here, and the
#                           phase-1 invocation keeps its --no-git.
#
# A phase-1 finding on its own is not actionable. "There is an API key in
# PreferencesController.php" leaves the only question that decides the remediation
# open. Never committed -> the fix is an edit. In history for two years across 44
# commits -> the fix is rotation at the provider plus a conversation about
# rewriting history, and editing the file changes nothing. Same finding, opposite
# remediation, and without phase 2 the report cannot say which one you have.
#
# ── the secret VALUE never touches disk, argv, or output ──────────────────────
#
# Every gitleaks invocation in this suite carries --redact, so the report on disk
# holds "REDACTED" rather than the matched value. That is deliberate and stays: a
# security audit must not be the thing that writes the secret into a committable
# file. It also means this file cannot read the value out of the report.
#
# The value is recovered from the WORKING-TREE FILE instead, using the line and
# column span gitleaks records (which --redact does not remove), and it lives only
# in shell and awk memory for the duration of the pass. In particular:
#
#   * it is never written to any file, including the report;
#   * it is never printed, so it cannot reach a log or a terminal transcript. That
#     includes bash's own xtrace, which publishes every assignment to stderr and is
#     inherited rather than typed - an exported SHELLOPTS=xtrace reaches every bash
#     descendant, and CI logs are kept. The three functions that hold the value save
#     and restore xtrace around it, so a caller running under `set -x` keeps the
#     trace everywhere except across the value. This claim was false when it was
#     first written: the code published the value 13 times under xtrace while the
#     comment said it could not. A comment asserting a guarantee the code does not
#     provide is worse than no comment;
#   * it is never passed as a command-line argument. /proc/<pid>/cmdline is
#     world-readable, so `git log -S "<value>"` - the obvious implementation, and
#     the one the gaps document proposes - publishes the secret to every user on
#     the machine for the duration of the walk. It is not used here for that one
#     reason. The value reaches awk through the ENVIRONMENT of that single child
#     process (/proc/<pid>/environ is 0400 and readable only by the owner, who can
#     already read this process's memory).
#
# The cost of refusing argv is that git's own pickaxe index is unavailable, so the
# walk below streams `git log -p` instead of asking `git log -S`. The MATCHING RULE
# is identical to -S ("commits that change the number of occurrences of the
# string"), see cqt_secret_history_scan; the walk is slower on a repository that
# ever committed its vendor directory, which is what CQT_SECRET_HISTORY_TIMEOUT
# bounds. A timeout is reported as "could not check", never as zero commits.
#
# That equivalence is a re-derivation, not the real thing, so it is checked against
# the real thing: the spec runs `git log -S` as an independent oracle over the diff
# SHAPES where a rule reading rendered patch text can part company with a rule
# reading blobs - .gitattributes markers, content that looks like a patch header,
# renames, merges, binary blobs. Two of those shapes produced false cleans before
# the oracle was pointed at them.
#
# Patch volume scales with history, so the budget is what decides whether a large
# repository gets an answer at all: roughly 20MB of patch text per second through
# the walk, against a default of 300 seconds. A repository big enough to exceed that
# is exactly the kind where "when did this enter history" matters most, which is why
# the default is not tighter. Past the budget the answer is budget_exceeded, which
# every surface renders as "could not be checked" and never as "not in history".
#
# ── what is deliberately NOT claimed ──────────────────────────────────────────
#
# Every non-answer is reported as an explicit status. A secret that was not found
# in history says so ("not_in_history"); a scan that could not be run or could not
# be trusted says THAT instead ("unknown" + a reason). The two are never collapsed,
# because "0 commits" read off a shallow clone is exactly the false clean the rest
# of this suite exists to refuse.
#
# Environment:
#   CQT_SECRET_HISTORY=0          disable phase 2 entirely.
#   CQT_SECRET_HISTORY_TIMEOUT=N  seconds the history walk may take (default 300).

# Column convention, verified empirically against gitleaks 8.30.1 rather than read
# off the documentation or inferred from the field names. Measured on files whose
# matches sit at known byte offsets:
#
#   StartLine  true byte offset  StartColumn
#       1              1              1
#       1             12             12
#       2              1              2
#       2              2              3
#       2             12             13
#       3              3              4        (also: 3 after a 2-byte UTF-8 char,
#                                               so these are BYTES, not characters)
#
# So the reported start is one PAST the true byte offset on every line except the
# FIRST line of the file, where it is exact - gitleaks locates the line by scanning
# back to the preceding newline and counts that newline, and line 1 has none. The
# earlier reading of this table, that the exception was "the match starts at column
# 1", fits half the rows and silently shifts the extraction by one byte on a secret
# that sits partway along the first line. The span EndColumn-StartColumn+1 is exact
# in bytes in every row.
#
# The extraction below is byte-oriented (LC_ALL=C) and does not trust this table on
# its own: whatever --redact leaves in Match around the word REDACTED is used to
# verify the alignment, and an extraction that does not carry those anchors is
# refused rather than attributed to commits.
CQT_GITLEAKS_COLUMN_BIAS=1

# Recover the matched value for ONE finding from the working-tree file.
#
# Echoes "<mode><US><value>" on stdout and returns 0, or returns non-zero having
# echoed nothing. stdout is a pipe into the caller's command substitution, so the
# value stays in memory. Nothing here writes, prints or passes the value anywhere
# else.
#
#   mode "exact"           the value is the matched secret.
#   mode "multiline_line"  the match spanned several lines (a PEM block is the
#                          usual case). Reconstructing the whole value would give a
#                          needle with newlines in it, which the line-oriented walk
#                          below cannot match, so the longest line of the match is
#                          used instead. That is a real narrowing and the caller
#                          reports it rather than passing it off as an exact
#                          confirmation.
#
# Arguments carry the LOCATION only: file, lines, columns and the REDACTED match.
#   cqt_secret_extract_value <file> <start_line> <end_line> <start_col> <end_col> <redacted_match>
cqt_secret_extract_value() {
    local file="$1" sl="$2" el="$3" sc="$4" ec="$5" redacted="$6"
    local us=$'\037'

    # These three read the LOCATION arguments only, so they are safe to trace.
    [ -n "$file" ] && [ -f "$file" ] || return 1
    case "$sl$el$sc$ec" in *[!0-9]*|'') return 1 ;; esac
    [ "$sl" -ge 1 ] || return 1

    # Everything past this point holds the value, and xtrace publishes every
    # assignment bash makes to stderr. That is not a state someone has to opt into
    # here: an exported SHELLOPTS=xtrace is inherited by every bash descendant, and
    # a CI log is a persisted artifact. Saved and restored in the same shape as
    # LC_ALL and errexit below, so a caller that asked for tracing still gets it
    # everywhere except across the value.
    local _xt=0
    case "$-" in *x*) _xt=1 ;; esac
    set +x

    # Byte semantics for every string operation below. gitleaks columns are byte
    # offsets, and under a UTF-8 locale bash would count characters instead, which
    # silently shifts the extraction on any line holding a non-ASCII byte.
    local _lc_set=0 _lc_old=''
    if [ -n "${LC_ALL+x}" ]; then _lc_set=1; _lc_old="$LC_ALL"; fi
    LC_ALL=C

    local out='' rc=1

    if [ "$el" -gt "$sl" ]; then
        # Multi-line match: no column arithmetic is reliable across the range, so
        # take the longest line the match covers and say so.
        local longest='' line=''
        while IFS= read -r line; do
            if [ "${#line}" -gt "${#longest}" ]; then longest="$line"; fi
        done < <(sed -n "${sl},${el}p" "$file" 2>/dev/null)
        # Trim, then require enough length to be a needle at all. A short line is
        # not distinctive enough to attribute commits to, and a wrong attribution
        # is worse than an honest "could not check".
        longest="${longest#"${longest%%[![:space:]]*}"}"
        longest="${longest%"${longest##*[![:space:]]}"}"
        if [ "${#longest}" -ge 20 ]; then
            out="multiline_line${us}${longest}"
            rc=0
        fi
    else
        local line
        line=$(sed -n "${sl}p" "$file" 2>/dev/null)
        local span=$((ec - sc + 1))
        # The bias is the counted newline in front of the line, so it is absent only
        # on the first line of the file. See the table at the top of this file.
        # The two candidates are always {sc, sc - bias}; which one is tried first is
        # what the line number decides. The second is tried ONLY when the redacted
        # Match left anchors to verify it with, so a future gitleaks that fixes its
        # own off-by-one still produces a correct extraction here instead of a
        # silently shifted one. Without anchors there is nothing to prefer it on,
        # and the measured convention stands.
        local primary="$sc" alternate=$((sc - CQT_GITLEAKS_COLUMN_BIAS))
        if [ "$sl" -gt 1 ]; then
            primary=$((sc - CQT_GITLEAKS_COLUMN_BIAS))
            alternate="$sc"
        fi

        # --redact rewrites only the secret inside Match, leaving whatever else the
        # rule matched around it. Those leftovers are anchors: they say how much of
        # the span is not the secret, AND they verify the offset, because a
        # mis-aligned extraction does not carry them.
        local prefix='' suffix='' anchored=0
        case "$redacted" in
            *REDACTED*)
                prefix="${redacted%%REDACTED*}"
                suffix="${redacted##*REDACTED}"
                if [ -n "$prefix" ] || [ -n "$suffix" ]; then anchored=1; fi
                ;;
            *)  # Not a redacted match at all. Refuse rather than guess.
                span=0 ;;
        esac

        local start raw value ok
        for start in "$primary" "$alternate"; do
            [ "$span" -gt 0 ] && [ "$start" -ge 1 ] || continue
            raw="${line:start-1:span}"
            # The span must actually exist in the line. A short read means the
            # report and the file disagree - the file changed under the scan, or
            # the column convention moved - and a value guessed from a partial read
            # must not be attributed to commits.
            [ "${#raw}" -eq "$span" ] || continue
            ok=1
            value="$raw"
            if [ -n "$prefix" ]; then
                if [ "${raw:0:${#prefix}}" = "$prefix" ]; then
                    value="${value:${#prefix}}"
                else
                    ok=0
                fi
            fi
            if [ "$ok" -eq 1 ] && [ -n "$suffix" ]; then
                if [ "${raw: -${#suffix}}" = "$suffix" ]; then
                    value="${value:0:${#value}-${#suffix}}"
                else
                    ok=0
                fi
            fi
            # A needle shorter than this is not specific enough to attribute commits
            # to; it would match unrelated content and inflate the count. Reported
            # as unavailable instead.
            if [ "$ok" -eq 1 ] && [ "${#value}" -ge 8 ]; then
                out="exact${us}${value}"
                rc=0
                break
            fi
            # Only an anchored match earns a second attempt.
            [ "$anchored" -eq 1 ] || break
        done
    fi

    if [ "$_lc_set" -eq 1 ]; then LC_ALL="$_lc_old"; else unset LC_ALL; fi
    if [ "$rc" -ne 0 ]; then
        if [ "$_xt" -eq 1 ]; then set -x; fi
        return 1
    fi
    # printf is a bash BUILTIN, so this hands the value to the caller's command
    # substitution through a pipe. An external command here would put the value in
    # argv, where /proc/<pid>/cmdline publishes it to every user on the machine.
    # Tracing is restored AFTER it: the trace of this line would be the value.
    printf '%s' "$out"
    if [ "$_xt" -eq 1 ]; then set -x; fi
    return 0
}

# Decide whether this repository can answer the history question at all.
# Echoes an empty string when it can, or the reason it cannot:
#   no_git_repo   the audited directory is not a git working tree
#   no_commits    a repository with no history yet
#   shallow_clone answerable only in part - see the caller
cqt_secret_history_repo_state() {
    local repo="${1:-.}"
    # The ANSWER, not the exit status. `rev-parse --is-inside-work-tree` prints
    # "false" and exits 0 inside a .git directory and in a bare repository, so a
    # check written on the status calls both of them working trees. Neither has a
    # tree to recover a value from, and the finding would then degrade to
    # value_unavailable - an honest status reached for the wrong reason, with the
    # wrong reason shown to the reader.
    local inside
    inside=$(git -C "$repo" rev-parse --is-inside-work-tree 2>/dev/null)
    if [ "$inside" != "true" ]; then
        printf 'no_git_repo'
        return 0
    fi
    if ! git -C "$repo" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        # An unborn HEAD can still have commits on other refs, so check those too
        # before calling it empty.
        if [ -z "$(git -C "$repo" rev-list -n 1 --all 2>/dev/null)" ]; then
            printf 'no_commits'
            return 0
        fi
    fi
    local shallow
    shallow=$(git -C "$repo" rev-parse --is-shallow-repository 2>/dev/null)
    if [ "$shallow" = "true" ]; then
        printf 'shallow_clone'
        return 0
    fi
    # --is-shallow-repository landed in git 2.15; fall back to the marker file.
    local gitdir
    gitdir=$(git -C "$repo" rev-parse --git-dir 2>/dev/null)
    if [ -n "$gitdir" ] && [ -f "${gitdir}/shallow" ]; then
        printf 'shallow_clone'
        return 0
    fi
    printf ''
    return 0
}

# Walk history once and attribute every needle in one pass.
#
# The needles arrive as a FUNCTION ARGUMENT, newline-separated. A function call
# execs nothing, so $2 lives in shell memory and never appears in any process's
# argv; from there the values reach awk through its ENVIRONMENT, which
# /proc/<pid>/environ exposes only to the owner. The pass is O(history), not
# O(history x findings), so a report with fifty findings costs the same walk as a
# report with one.
#
# MATCHING RULE, identical to `git log -S<string>`: a commit counts when it changes
# the NUMBER OF OCCURRENCES of the needle. Occurrences are counted in the added
# lines and in the removed lines of the commit's diff and compared; with -U0 there
# are no context lines, and unchanged regions contribute equally to both sides, so
# the comparison is the same one -S makes. That equivalence is what lets the spec
# cross-check this walk against git's own pickaxe.
#
# Echoes one line per needle that was found, plus one status line:
#   RC<US><git exit status>
#   N<US><needle index><US><commits><US><sha><US><author date><US><author name>
# No needle and no matched text is ever echoed.
cqt_secret_history_scan() {
    local repo="${1:-.}" needles="${2-}"
    # $2 is the needle list, and the awk invocation below carries it in an
    # environment assignment; under xtrace bash would trace both. Suppressed here as
    # well as in the entry point, because this function is reachable on its own.
    local _xt=0
    case "$-" in *x*) _xt=1 ;; esac
    set +x
    local budget="${CQT_SECRET_HISTORY_TIMEOUT:-300}"
    local marker="CQTC$$X${RANDOM}${RANDOM}"

    # `timeout` is coreutils and normally present; without it the walk simply runs
    # unbounded rather than not running at all.
    local runner=''
    if command -v timeout >/dev/null 2>&1; then runner="timeout $budget"; fi

    {
        local rc=0
        # --text is load-bearing, not a convenience. Without it, a `-diff` or
        # `binary` attribute in .gitattributes makes git print "Binary files a/x and
        # b/x differ" and NO content lines, so the walk sees nothing for that path
        # and reports a REAL zero - "never committed" about a credential that is
        # committed, and the remediation then actively tells the reader not to
        # rotate. `*.json -diff` and `*.cfg binary` are ordinary entries and config
        # files are where tokens live, so this is not a corner. git's own pickaxe
        # reads blobs rather than rendered patches and is unaffected, which is why
        # the two disagreed until --text closed the gap. The cost is that genuinely
        # binary blobs are streamed through the walk; that is bounded by the same
        # timeout as everything else, and a binary blob cannot produce a phase-1
        # finding to confirm in the first place, so nothing is lost by reading it.
        # shellcheck disable=SC2086
        $runner git -C "$repo" log --all --no-color --no-textconv --text -p -U0 \
            --format="${marker}%H%x1f%aI%x1f%an%x1f%at" 2>/dev/null || rc=$?
        printf '%sEXIT%s\n' "$marker" "$rc"
    } | CQT_NEEDLES="$needles" awk -v marker="$marker" '
        function flush(  i) {
            if (commit == "") return
            for (i = 1; i <= nn; i++) {
                if (plus[i] == minus[i]) continue
                cnt[i] = cnt[i] + 1
                if (!(i in first_at) || cat + 0 < first_at[i] + 0) {
                    first_at[i] = cat
                    first_c[i] = commit
                    first_d[i] = cdate
                    first_a[i] = cauthor
                }
            }
            for (i = 1; i <= nn; i++) { plus[i] = 0; minus[i] = 0 }
        }
        function occurrences(line, needle,   n, p, rest) {
            n = 0
            rest = line
            while (1) {
                p = index(rest, needle)
                if (p == 0) return n
                n = n + 1
                rest = substr(rest, p + length(needle))
            }
        }
        BEGIN {
            nn = split(ENVIRON["CQT_NEEDLES"], needle, "\n")
            ml = length(marker)
            commit = ""
            gitrc = "unknown"
            inhdr = 0
            for (i = 1; i <= nn; i++) { plus[i] = 0; minus[i] = 0; cnt[i] = 0 }
        }
        substr($0, 1, ml) == marker {
            rest = substr($0, ml + 1)
            if (substr(rest, 1, 4) == "EXIT") { gitrc = substr(rest, 5); next }
            flush()
            split(rest, f, "\037")
            commit = f[1]; cdate = f[2]; cauthor = f[3]; cat = f[4]
            inhdr = 0
            next
        }
        # PATCH STATE, not the first three bytes of the line. The `--- a/path` and
        # `+++ b/path` file headers must be skipped, or a needle that merely appears
        # in a FILENAME would be attributed to a commit. But those two strings are
        # also what an added line whose content begins with "++" and a removed line
        # whose content begins with "--" render as, and "--" is the comment prefix in
        # SQL, Lua, Haskell and Ada. Skipping on the bytes alone therefore drops real
        # content: the "++" case hides the introducing commit outright, and the "--"
        # case undercounts the deletion.
        #
        # Headers can only appear inside a `diff --git` block BEFORE its first `@@`
        # hunk marker, and content can only appear AFTER one, so the two are
        # separable exactly. A content line can never open the block itself: under
        # -p every content line carries a leading + or -, so "diff --git " and "@@"
        # at the start of a line are unambiguous.
        #
        # The reset at the commit boundary above is defence with no reachable case
        # behind it today, and it is labelled that way rather than presented as a
        # tested guarantee: the patch of every commit opens with "diff --git", which
        # sets the flag anyway, so no fixture can tell the reset from its absence. It
        # is kept because the thing that would make it reachable - printing merge
        # diffs with -m, or any future format change - would otherwise fail silently.
        /^diff --git / { inhdr = 1; next }
        /^@@/ { inhdr = 0; next }
        inhdr == 1 && /^(\+\+\+|---)/ { next }
        /^[+-]/ {
            for (i = 1; i <= nn; i++) {
                if (needle[i] == "") continue
                c = occurrences($0, needle[i])
                if (c == 0) continue
                if (substr($0, 1, 1) == "+") plus[i] = plus[i] + c
                else minus[i] = minus[i] + c
            }
        }
        END {
            flush()
            printf "RC\037%s\n", gitrc
            for (i = 1; i <= nn; i++) {
                if (cnt[i] == 0) continue
                printf "N\037%d\037%d\037%s\037%s\037%s\n", \
                    i, cnt[i], first_c[i], first_d[i], first_a[i]
            }
        }
    '
    if [ "$_xt" -eq 1 ]; then set -x; fi
    return 0
}

# Public entry point. Reads a gitleaks report and echoes a JSON array with one
# object per finding, in report order:
#
#   { history_status: "found"|"not_in_history"|"unknown",
#     history_reason: "" | no_git_repo | no_commits | shallow_clone |
#                     budget_exceeded | git_walk_failed | value_unavailable |
#                     disabled | multiline_line,
#     commit_count: N|null, first_seen_commit: sha|null,
#     first_seen_date: iso|null, author: name|null }
#
# commit_count is null - not 0 - whenever the answer is unknown. A zero means "we
# looked and it is not in history"; anything else is a different claim.
#
# Call it in a command substitution. It never fails and never emits a secret.
#   cqt_secret_history_json <gitleaks_report_json> [repo_dir]
cqt_secret_history_json() {
    local report="$1" repo="${2:-.}"
    local us=$'\037'

    # Restore the caller's errexit on the way out: a helper that cannot answer must
    # degrade to "unknown", never take the security gate down with it.
    local _errexit=0
    case "$-" in *e*) _errexit=1 ;; esac
    set +e

    # Same save/restore for xtrace, and for the same kind of reason: the recovered
    # value is assigned, compared and concatenated all through this function, and a
    # trace of any of those lines is the secret in cleartext on stderr. Restored at
    # every one of the returns below, so a caller running under `set -x` loses the
    # trace of this function and nothing else.
    local _xt=0
    case "$-" in *x*) _xt=1 ;; esac
    set +x

    local n=0
    if [ -f "$report" ] && [ -s "$report" ]; then
        n=$(jq 'if type == "array" then length else 0 end' "$report" 2>/dev/null)
    fi
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$n" -eq 0 ]; then
        printf '[]'
        [ "$_xt" -eq 1 ] && set -x
        [ "$_errexit" -eq 1 ] && set -e
        return 0
    fi

    local -a hstat reason count sha adate aname
    local i=0
    while [ "$i" -lt "$n" ]; do
        hstat[i]="unknown"; reason[i]=""; count[i]=""
        sha[i]=""; adate[i]=""; aname[i]=""
        i=$((i + 1))
    done

    if [ "${CQT_SECRET_HISTORY:-1}" = "0" ]; then
        i=0
        while [ "$i" -lt "$n" ]; do reason[i]="disabled"; i=$((i + 1)); done
        cqt_secret_history_emit "$n" || true
        [ "$_xt" -eq 1 ] && set -x
        [ "$_errexit" -eq 1 ] && set -e
        return 0
    fi

    local repo_state
    repo_state=$(cqt_secret_history_repo_state "$repo")
    if [ "$repo_state" = "no_git_repo" ] || [ "$repo_state" = "no_commits" ]; then
        i=0
        while [ "$i" -lt "$n" ]; do reason[i]="$repo_state"; i=$((i + 1)); done
        cqt_secret_history_emit "$n" || true
        [ "$_xt" -eq 1 ] && set -x
        [ "$_errexit" -eq 1 ] && set -e
        return 0
    fi

    # Extract the matched values, deduplicate them, and remember which findings each
    # needle belongs to. Deduplication is why one secret repeated across ten files
    # costs one needle rather than ten.
    local -a needle_of         # finding index -> needle index (1-based) or ""
    local -a needle_mode       # finding index -> exact|multiline_line
    local needles=''
    local nneedles=0
    local -a needle_value
    local file sl el sc ec match extracted mode value j found

    # IFS is set on the `read` itself. The heredoc form of this - `read ... <<EOF` -
    # would be simpler to look at and would also make bash spill each record to a
    # temporary FILE, which is the one thing this file must never do.
    i=0
    while IFS="$us" read -r file sl el sc ec match; do
        [ "$i" -lt "$n" ] || break
        needle_of[i]=""
        needle_mode[i]=""
        extracted=$(cqt_secret_extract_value "$file" "$sl" "$el" "$sc" "$ec" "$match")
        if [ -n "$extracted" ]; then
            mode="${extracted%%"$us"*}"
            value="${extracted#*"$us"}"
            found=""
            j=1
            while [ "$j" -le "$nneedles" ]; do
                if [ "${needle_value[j]}" = "$value" ]; then found="$j"; break; fi
                j=$((j + 1))
            done
            if [ -z "$found" ]; then
                nneedles=$((nneedles + 1))
                needle_value[nneedles]="$value"
                if [ "$nneedles" -eq 1 ]; then needles="$value"
                else needles="${needles}"$'\n'"${value}"; fi
                found="$nneedles"
            fi
            needle_of[i]="$found"
            needle_mode[i]="$mode"
        else
            reason[i]="value_unavailable"
        fi
        i=$((i + 1))
    done < <(jq -r --arg us "$us" '
        .[] | [ (.File // ""), (.StartLine // 0 | tostring),
                (.EndLine // 0 | tostring), (.StartColumn // 0 | tostring),
                (.EndColumn // 0 | tostring), (.Match // "") ] | join($us)
    ' "$report" 2>/dev/null)

    if [ "$nneedles" -eq 0 ]; then
        cqt_secret_history_emit "$n" || true
        [ "$_xt" -eq 1 ] && set -x
        [ "$_errexit" -eq 1 ] && set -e
        return 0
    fi

    local gitrc='' tag idx ncount nsha ndate nauthor
    local -a res_count res_sha res_date res_author
    while IFS="$us" read -r tag idx ncount nsha ndate nauthor; do
        if [ "$tag" = "RC" ]; then gitrc="$idx"; continue; fi
        [ "$tag" = "N" ] || continue
        case "$idx" in ''|*[!0-9]*) continue ;; esac
        res_count[idx]="$ncount"
        res_sha[idx]="$nsha"
        res_date[idx]="$ndate"
        res_author[idx]="$nauthor"
    done < <(cqt_secret_history_scan "$repo" "$needles")

    # A walk that was cut short saw only part of history, so every needle it did
    # not find is unproven rather than absent. 124 is timeout(1)'s "killed on the
    # budget"; any other non-zero is git itself failing.
    local walk_reason=''
    if [ "$gitrc" != "0" ]; then
        if [ "$gitrc" = "124" ] || [ "$gitrc" = "137" ]; then
            walk_reason="budget_exceeded"
        else
            walk_reason="git_walk_failed"
        fi
    fi

    i=0
    while [ "$i" -lt "$n" ]; do
        j="${needle_of[i]:-}"
        if [ -z "$j" ]; then
            # No needle for this finding: either the value could not be recovered,
            # or the location read produced fewer records than the report has
            # findings. Both are "we could not check", never "not in history".
            [ -n "${reason[i]}" ] || reason[i]="value_unavailable"
            i=$((i + 1)); continue
        fi
        if [ -n "${res_count[j]:-}" ]; then
            hstat[i]="found"
            count[i]="${res_count[j]}"
            sha[i]="${res_sha[j]}"
            adate[i]="${res_date[j]}"
            aname[i]="${res_author[j]}"
            # A hit is a hit even on a truncated walk, but the count is then a
            # lower bound and the report says which narrowing applied.
            if [ -n "$walk_reason" ]; then reason[i]="$walk_reason"
            elif [ "$repo_state" = "shallow_clone" ]; then reason[i]="shallow_clone"
            elif [ "${needle_mode[i]:-}" = "multiline_line" ]; then reason[i]="multiline_line"
            fi
        elif [ -n "$walk_reason" ]; then
            reason[i]="$walk_reason"
        elif [ "$repo_state" = "shallow_clone" ]; then
            # The commits that would prove it are not in this clone. Absence here
            # is not evidence, and reporting 0 would read as "safe to just edit".
            reason[i]="shallow_clone"
        else
            hstat[i]="not_in_history"
            count[i]="0"
            if [ "${needle_mode[i]:-}" = "multiline_line" ]; then reason[i]="multiline_line"; fi
        fi
        i=$((i + 1))
    done

    cqt_secret_history_emit "$n" || true
    [ "$_xt" -eq 1 ] && set -x
    [ "$_errexit" -eq 1 ] && set -e
    return 0
}

# Serialise the per-finding arrays built by cqt_secret_history_json. Split out only
# so the six early returns above do not each carry a copy of it; it reads the
# caller's locals by design and is not a public entry point.
cqt_secret_history_emit() {
    local total="$1" us=$'\037' i=0 rows=''
    while [ "$i" -lt "$total" ]; do
        rows="${rows}${hstat[i]}${us}${reason[i]}${us}${count[i]}${us}${sha[i]}${us}${adate[i]}${us}${aname[i]}"$'\n'
        i=$((i + 1))
    done
    printf '%s' "$rows" | jq -R -s --arg us "$us" '
        split("\n") | map(select(length > 0)) | map(split($us)) | map({
            history_status: .[0],
            history_reason: .[1],
            commit_count: (if (.[2] // "") == "" then null else (.[2] | tonumber) end),
            first_seen_commit: (if (.[3] // "") == "" then null else .[3] end),
            first_seen_date: (if (.[4] // "") == "" then null else .[4] end),
            author: (if (.[5] // "") == "" then null else .[5] end)
        })' 2>/dev/null || printf '[]'
    return 0
}

# Attach the phase-2 fields to a gitleaks issues array and rewrite the remediation
# to match what the history says, because that is the whole point: the same finding
# needs a different response depending on the answer.
#
# Echoes the augmented issues array. Never emits a secret value.
#   cqt_secret_history_attach <issues_json> <history_json>
cqt_secret_history_attach() {
    local issues="$1" history="$2"
    jq -n --argjson issues "$issues" --argjson history "$history" '
        [ range(0; ($issues | length)) as $i
          | ($history[$i] // {}) as $h
          | $issues[$i] + $h + {
              remediation: (
                if $h.history_status == "found" then
                  "Rotate this credential at the provider: it is already in git history"
                  + (if $h.first_seen_date then " (since " + ($h.first_seen_date | .[0:10]) + ")" else "" end)
                  + (if $h.commit_count then ", " + ($h.commit_count | tostring) + " commit(s)" else "" end)
                  + ". Editing the file does not remove it from history."
                elif $h.history_status == "not_in_history" then
                  "Remove the secret from the file and use secret management. It has not reached git history, so no rotation is forced by this finding."
                else
                  ($issues[$i].remediation // "Remove secret from code, rotate credentials, and use secret management")
                  + " History could not be confirmed"
                  + (if ($h.history_reason // "") != "" then " (" + $h.history_reason + ")" else "" end)
                  + ", so assume it may already be committed."
                end
              )
            } ]' 2>/dev/null || printf '%s' "$issues"
    return 0
}

# Print a one-line human summary per finding. Location and history only - the value
# is not printed here or anywhere else.
#   cqt_secret_history_report <issues_json>
cqt_secret_history_report() {
    printf '%s' "$1" | jq -r '.[] |
        (.file // "?") + ":" + ((.line // 0) | tostring) + " - " +
        (if .history_status == "found" then
            "in git history since " + ((.first_seen_date // "?") | .[0:10]) +
            " (" + ((.commit_count // 0) | tostring) + " commit(s), first by " +
            (.author // "unknown") + ") - ROTATE, editing the file is not enough"
         elif .history_status == "not_in_history" then
            "not in git history (working tree only) - remove before committing"
         else
            "history could not be checked" +
            (if (.history_reason // "") != "" then " (" + .history_reason + ")" else "" end)
         end)' 2>/dev/null || true
    return 0
}
