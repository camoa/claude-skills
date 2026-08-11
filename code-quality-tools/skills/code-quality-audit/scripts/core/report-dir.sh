#!/bin/bash
# report-dir.sh - where an audit run writes its reports.
# Part of code-quality-audit skill. Sourced by every script in the suite; also runnable
# directly (`report-dir.sh --print` / `--latest` / `--origin`) so that a consumer which
# cannot source a shell file - a hook, a slash command, a person - gets the same answer
# from the same rule instead of assuming one. See the entry point at the end of the file.
#
# Every script in this suite used to resolve its own output as
#
#     REPORT_DIR="${REPORT_DIR:-.reports}"
#
# copied independently into sixteen files. That default is RELATIVE, so it landed inside
# whatever repository was being audited. On client work that is somebody else's tree; the
# directory is not gitignored, so `git add .` sweeps it in; a report is a point-in-time
# finding about one commit and does not belong on a branch that travels; and auditing
# four repositories leaves four disconnected directories with no shared history.
#
# The plumbing was already right — every script honours an explicitly set REPORT_DIR — so
# only the DEFAULT needed to change. It changes here, once, and every script sources this
# file. Nothing routed through detect-environment.sh's setup_report_dir() before, so
# fixing it there alone would have changed nothing for any standalone gate.
#
# Resolution order:
#
#   1. $REPORT_DIR when explicitly set. Unchanged; the caller knows where they want it.
#   2. The ai-dev-assistant project folder registered for this working directory, under
#      <project>/audits/<date>/. This is the case that matters for our own work: the
#      report lands beside task.md, research.md and the architecture notes.
#   3. Otherwise outside the repository entirely, under
#      ${XDG_STATE_HOME:-$HOME/.local/state}/code-quality-tools/<project>/<timestamp>/.
#      Each of those variables has to be absolute and outside the audited tree to be
#      used; see cqt_report_dir_state_root for what happens when it is not, and why.
#   4. .reports/ only when REPORT_DIR_IN_REPO=1 asks for it, gitignored at creation.
#
# The default never lands inside the audited repository, and the line the run prints
# about that is measured rather than asserted — see cqt_announce_report_dir.
#
# REPORT_DIR, REPORT_DIR_ORIGIN and CQT_REPORT_DIR_INHERITED are all EXPORTED.
# full-audit.sh runs detect-environment.sh and every gate as separate processes, and each
# of those sources this file too; without the export each would re-resolve, the step-3
# timestamp would differ per process, and full-audit.sh would look for an environment.json
# that a child wrote somewhere else. Exporting makes the parent's answer the run's answer,
# carrying the origin as well keeps the child's "where the report went" line honest rather
# than reporting every inherited value as an explicit one, and the third says whether the
# value was handed down or typed — which is what separates "write here" from "read the
# previous run from here".

# The root of the tree being audited: the git working tree when there is one, otherwise
# the working directory. This is the thing the whole file exists to keep reports out of.
cqt_report_dir_audited_root() {
    local top=""
    top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -z "${top}" ]; then
        top="$(pwd -P 2>/dev/null || printf '%s' "${PWD}")"
    fi
    printf '%s' "${top%/}"
}

# An absolute, lexically normalised form of a path, so that two paths can be compared.
#
# Not realpath: the directory being asked about has usually not been created yet — it is
# resolved first and made second — and `realpath -m` is not portable. Symlinks are
# therefore NOT resolved. That is safe for the one comparison this exists for, because
# the root it is compared against comes from `git rev-parse --show-toplevel` or `pwd -P`,
# both of which are already physical, and a relative path is anchored to `pwd -P` here.
#
# The segment walk is parameter expansion rather than `IFS=/; for seg in ${p}`, because
# the unquoted form also GLOBS: a path holding * or ? would be replaced by whatever
# happens to be on disk, which is a wrong answer arrived at silently.
cqt_report_dir_abspath() {
    local p="${1:-}"
    [ -n "${p}" ] || return 1
    case "${p}" in
        /*) ;;
        *)  p="$(pwd -P 2>/dev/null || printf '%s' "${PWD}")/${p}" ;;
    esac

    local rest="${p}" seg="" out=""
    while [ -n "${rest}" ]; do
        seg="${rest%%/*}"
        if [ "${seg}" = "${rest}" ]; then rest=""; else rest="${rest#*/}"; fi
        case "${seg}" in
            ''|'.') ;;
            '..')   out="${out%/*}" ;;
            *)      out="${out}/${seg}" ;;
        esac
    done
    printf '%s' "${out:-/}"
    return 0
}

# Is this path inside the tree being audited? The one question the invariant is about,
# asked once here so that every place that needs the answer gets the same one, and so
# that the answer is MEASURED rather than inferred from which rule produced the path.
#
# A relative path is inside by construction unless it climbs out with ..: it resolves
# against the working directory, and the working directory is the audited tree or a
# subdirectory of it. That is exactly how a relative XDG_STATE_HOME used to put reports
# back in the repository while the run announced the opposite.
cqt_report_dir_is_inside() {
    local p="" top=""
    p="$(cqt_report_dir_abspath "${1:-}")" || return 1
    [ -n "${p}" ] || return 1
    top="$(cqt_report_dir_audited_root)"
    # audited_root strips a trailing slash, so the filesystem root arrives empty. Auditing
    # / is pathological, but "everything is inside" is the true answer for it and this
    # function must not report a comfortable falsehood.
    [ -n "${top}" ] || return 0
    [ "${p}" != "${top}" ] || return 0
    case "${p}/" in
        "${top}"/*) return 0 ;;
    esac
    return 1
}

# The root of the out-of-repo location. XDG_STATE_HOME is the right variable: these are
# state files that survive a run and are not caches.
#
# Each candidate has to EARN the job rather than merely being set, and a candidate that
# does not is skipped for the next one:
#
#   ABSOLUTE. XDG_STATE_HOME, HOME and TMPDIR are all environment values, and a relative
#   value in any of them resolves against the audited repository's working directory —
#   which is the single thing this file exists to prevent, arrived at through the code
#   path that believes it is preventing it. The freedesktop basedir spec says the same
#   about XDG_*: a relative value is invalid and must be ignored, not repaired.
#
#   OUTSIDE THE AUDITED TREE. An absolute path can point into the repository just as
#   easily — XDG_STATE_HOME set to the checkout itself is the obvious way — and "the
#   environment said so" is not a reason to write a report into somebody else's tree.
#   This also catches the case nobody configures on purpose: auditing a repository whose
#   root IS $HOME, where the default $HOME/.local/state is inside the tree. The reports
#   go to /tmp for that run, which is worse than durable and better than committable.
#
# /tmp is the last resort and is not itself subjected to the containment test, because
# there has to be a final answer. If even that is inside the audited tree, the run says
# so: cqt_announce_report_dir measures the resolved path instead of trusting the rule.
cqt_report_dir_state_root() {
    local candidate=""
    for candidate in "${XDG_STATE_HOME:-}" "${HOME:+${HOME}/.local/state}" "${TMPDIR:-}"; do
        [ -n "${candidate}" ] || continue
        case "${candidate}" in
            /*) ;;
            *)  continue ;;
        esac
        # An `if` rather than `... && continue`: the && form's status is the whole list's,
        # so a candidate that IS acceptable would return non-zero from the last command in
        # the loop body and kill a caller running under `set -e`.
        if cqt_report_dir_is_inside "${candidate}"; then
            continue
        fi
        printf '%s/code-quality-tools' "${candidate%/}"
        return 0
    done
    printf '%s/code-quality-tools' "/tmp"
    return 0
}

# A name for the thing being audited, used as the per-project directory under the state
# root. The repository root is the better answer than the working directory, so that
# running the audit from a subdirectory does not scatter reports across several names.
cqt_report_dir_project_name() {
    local name=""
    name="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -z "${name}" ]; then
        name="$(pwd -P 2>/dev/null || printf '%s' "${PWD}")"
    fi
    name="${name%/}"
    name="${name##*/}"
    # This becomes a path component. Anything outside this set is replaced rather than
    # escaped, because the name is for a human reading `ls`, not for round-tripping.
    name="${name//[!A-Za-z0-9._-]/_}"
    case "${name}" in
        ''|'.'|'..') name="project" ;;
    esac
    printf '%s' "${name}"
}

# The ai-dev-assistant project folder registered for the current working directory, or
# nothing. Prints nothing and returns 0 on every failure: a wrong project folder is worse
# than none, because it files one engagement's findings under another's.
#
# Matching is on codePath by containment, anchored at a path separator. A plain string
# prefix would make /srv/client-a match a codePath of /srv/client, which is exactly the
# mix-up that must not happen. Where several registrations match — a repository and a
# module inside it, both legitimately registered — the longest codePath wins, since it is
# the more specific statement about where this code belongs.
#
# THAT IS THE WHOLE RULE. It used to be followed by a tiebreak on lastAccessed, so that
# several projects registered against ONE codePath resolved to the most recently accessed
# one. That was wrong in a way this file cannot detect: lastAccessed is written by another
# tool at another time, is absent from many real records, and goes stale the moment a
# project is worked on without going through that tool. On the repository this was
# written in it selects a project that is not the engagement in progress. A tiebreak that
# is usually-but-not-always right is the worst kind here, because being wrong means one
# client's findings are filed in another client's folder and nothing says so. Two records
# naming two different folders for one codePath is the registry declining to say which,
# and the honest reading of that is to decline too and let step 3 take the report. Two
# records naming the SAME folder are not a tie and still resolve.
#
# Three things about a matched record are checked rather than trusted, because the
# registry is written by another tool and a bad record here defeats the invariant this
# whole file exists for:
#
#   codePath must be ABSOLUTE and not the root. A record with codePath "/" matches every
#   directory on the machine, so one stray record would capture every audit anywhere; a
#   relative codePath cannot be compared to an absolute cwd at all.
#
#   path must be ABSOLUTE. A relative project path resolves against the audited
#   repository's working directory, which puts the report straight back inside the tree.
#
#   path must be OUTSIDE the audited tree. An absolute path can point into the repository
#   just as easily, and "the registry said so" is not a reason to write a report into
#   somebody else's checkout.
#
# jq is required rather than optional. The registry is JSON written by another tool, and
# a grep-shaped reading of it matches the wrong record sooner or later; declining and
# falling through to step 3 is the safe failure.
cqt_report_dir_aida_project() {
    command -v jq >/dev/null 2>&1 || return 0
    [ -n "${HOME:-}" ] || return 0

    local cwd="" reg="" found="" found_real="" audited=""
    cwd="$(pwd -P 2>/dev/null || printf '%s' "${PWD}")"
    [ -n "${cwd}" ] || return 0
    audited="$(cqt_report_dir_audited_root)"

    # The legacy drupal-dev-framework location is still read: the plugin was renamed and
    # a machine that has not re-registered its projects still has its registry there.
    for reg in "${HOME}/.claude/ai-dev-assistant/active_projects.json" \
               "${HOME}/.claude/drupal-dev-framework/active_projects.json"; do
        [ -r "${reg}" ] || continue
        found="$(jq -r --arg cwd "${cwd}" '
            [ (.projects // [])[]
              | select(((.codePath // "") | length) > 0)
              | select(((.path // "") | length) > 0)
              | . as $rec
              | ($rec.codePath | sub("/+$"; "")) as $code
              | select($code | startswith("/"))
              | select($rec.path | startswith("/"))
              | select($cwd == $code or ($cwd | startswith($code + "/")))
              | { path: $rec.path, depth: ($code | length) }
            ] as $all
            | ($all | map(.depth) | max) as $deepest
            | ( [ $all[] | select(.depth == $deepest) | .path ] | unique ) as $winners
            | if ($winners | length) == 1 then $winners[0] else empty end
        ' "${reg}" 2>/dev/null || true)"
        [ -n "${found}" ] || continue
        # A registration whose folder has been moved or deleted is stale. Creating it
        # would invent a project record, so fall through instead.
        [ -d "${found}" ] && [ -w "${found}" ] || continue
        # Compared after resolution, so a symlink into the tree is caught too.
        found_real="$(cd "${found}" 2>/dev/null && pwd -P || true)"
        [ -n "${found_real}" ] || continue
        if [ -n "${audited}" ]; then
            case "${found_real}/" in
                "${audited}"/*) continue ;;
            esac
        fi
        printf '%s' "${found}"
        return 0
    done
    return 0
}

# Decide REPORT_DIR and REPORT_DIR_ORIGIN, and export both. Idempotent: a second call in
# the same process, or a call in a child process, returns the value already decided.
#
# CQT_REPORT_DIR_INHERITED is exported alongside them, and records whether the value was
# HANDED DOWN by a parent that had already resolved it, as opposed to typed by the person
# running the gate. Both arrive as "REPORT_DIR is already set", so the origin alone cannot
# tell them apart — a parent exports REPORT_DIR_ORIGIN too, and a caller typing
# `REPORT_DIR=/tmp/x ./gate.sh` does not. The difference matters to anything that READS a
# report rather than writing one; see cqt_report_dir_for_reading.
cqt_resolve_report_dir() {
    if [ -n "${REPORT_DIR:-}" ]; then
        if [ -n "${REPORT_DIR_ORIGIN:-}" ]; then
            CQT_REPORT_DIR_INHERITED=1
        else
            REPORT_DIR_ORIGIN="explicit"
            CQT_REPORT_DIR_INHERITED=0
        fi
        export REPORT_DIR REPORT_DIR_ORIGIN CQT_REPORT_DIR_INHERITED
        return 0
    fi

    CQT_REPORT_DIR_INHERITED=0

    if [ "${REPORT_DIR_IN_REPO:-0}" = "1" ]; then
        REPORT_DIR=".reports"
        REPORT_DIR_ORIGIN="in-repo-opt-in"
        export REPORT_DIR REPORT_DIR_ORIGIN CQT_REPORT_DIR_INHERITED
        return 0
    fi

    local project=""
    project="$(cqt_report_dir_aida_project)" || project=""
    if [ -n "${project}" ]; then
        REPORT_DIR="${project}/audits/$(date +%Y-%m-%d)"
        REPORT_DIR_ORIGIN="project"
        export REPORT_DIR REPORT_DIR_ORIGIN CQT_REPORT_DIR_INHERITED
        return 0
    fi

    REPORT_DIR="$(cqt_report_dir_state_root)/$(cqt_report_dir_project_name)/$(date +%Y%m%dT%H%M%S)"
    REPORT_DIR_ORIGIN="state"
    export REPORT_DIR REPORT_DIR_ORIGIN CQT_REPORT_DIR_INHERITED
    return 0
}

# Where to READ a report that already exists.
#
# The resolution above answers "where does THIS run write", and for a tool that converts
# or summarises an existing report that is the wrong question. The two answers differ in
# exactly one case, and it is the new default: a freshly resolved step-3 directory carries
# this second's timestamp, so it is empty by construction and can never hold the input.
# report-processor.sh defaulted its input to ${REPORT_DIR}/audit-report.json, which after
# the move to an out-of-repo default is a path that cannot contain its own input. The
# `latest` pointer exists precisely to name the previous run, so that is what is used.
#
# WHERE the previous run is, is cqt_report_dir_latest's job and is not repeated here.
# What this adds is the one thing that function cannot know: WHETHER to ask it. A gate
# that full-audit.sh handed REPORT_DIR to must read the run IN PROGRESS — `latest` still
# names the run before it until this one finishes having written something — and that
# gate and a person typing REPORT_DIR=... both arrive as "already set". Only
# CQT_REPORT_DIR_INHERITED separates them.
cqt_report_dir_for_reading() {
    local latest=""
    if [ "${CQT_REPORT_DIR_INHERITED:-0}" != "1" ]; then
        if latest="$(cqt_report_dir_latest 2>/dev/null)" && [ -n "${latest}" ]; then
            printf '%s' "${latest}"
            return 0
        fi
    fi
    printf '%s' "${REPORT_DIR}"
}

# Keep the report directory out of the audited repository's commits.
#
# Reports quote lines out of the audited source and name the files a secret scanner
# matched in, so the directory must not be committable by accident. With the resolution
# above this only has anything to do on the opt-in path, but it stays general: an
# explicitly set REPORT_DIR can also point inside the tree. Defence in depth in a
# repository we do not own — it never aborts the audit, never writes through a symlink,
# never invents a pattern it cannot write safely, and only ever appends.
cqt_gitignore_report_dir() {
    local report_dir="$1"
    local in_work_tree=""
    in_work_tree="$(git rev-parse --is-inside-work-tree 2>/dev/null || true)"
    [ "${in_work_tree}" = "true" ] || return 0

    local gitignore=".gitignore"
    local entry="${report_dir%/}"
    entry="${entry#./}"
    local skip_reason=""

    # Ask git, not this file: the path may already be covered by a parent .gitignore,
    # .git/info/exclude or a global excludesfile, in which case writing anything here
    # would just be a stray edit.
    if [ -z "${entry}" ]; then
        skip_reason="empty"
    elif git check-ignore -q "${report_dir}" 2>/dev/null; then
        skip_reason="already-ignored"
    fi

    # A gitignore entry is a repo-relative pattern, so an absolute REPORT_DIR is
    # deliberately never written: rewriting it into one is not safe to guess. Say so only
    # when it actually sits inside this work tree, where it would otherwise go
    # unprotected. Absolute and outside the tree needs no entry at all — which is now the
    # normal case — so that stays silent.
    if [ -z "${skip_reason}" ]; then
        case "${entry}" in
            /*)
                local top=""
                top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
                skip_reason="absolute-outside-work-tree"
                if [ -n "${top}" ]; then
                    case "${entry}/" in
                        "${top}"/*) skip_reason="absolute-inside-work-tree" ;;
                    esac
                fi
                ;;
        esac
    fi

    # REPORT_DIR is interpolated into gitignore's PATTERN language, where * ? [ ] \ are
    # wildcards, a leading # is a comment, a leading ! negates (which would UN-ignore
    # paths), and a trailing space is stripped. Refuse rather than guess an escaping for
    # a value holding any of them.
    if [ -z "${skip_reason}" ]; then
        case "${entry}" in
            *'*'*|*'?'*|*'['*|*']'*|*'\'*|*$'\n'*|'#'*|'!'*|*' ')
                skip_reason="unsafe-pattern"
                ;;
        esac
    fi

    # Writing through a symlink would land the entry outside the repository.
    if [ -z "${skip_reason}" ] && [ -L "${gitignore}" ]; then
        skip_reason="symlink"
    fi

    # An existing literal entry may be overridden by a later negation, so git can report
    # the path as not ignored while the line is already there. Appending a duplicate
    # would not help, so scan before writing.
    if [ -z "${skip_reason}" ] && [ -f "${gitignore}" ]; then
        if [ -r "${gitignore}" ]; then
            local line=""
            local trimmed=""
            while IFS= read -r line || [ -n "${line}" ]; do
                trimmed="${line%$'\r'}"
                trimmed="${trimmed#/}"
                trimmed="${trimmed%/}"
                if [ "${trimmed}" = "${entry}" ]; then
                    skip_reason="already-listed"
                    break
                fi
            done 2>/dev/null < "${gitignore}" || skip_reason="unreadable"
        else
            skip_reason="unreadable"
        fi
    fi

    if [ -z "${skip_reason}" ]; then
        # Do not glue the entry onto a last line that has no newline.
        local lead=""
        if [ -s "${gitignore}" ] && [ -n "$(tail -c 1 "${gitignore}" 2>/dev/null)" ]; then
            lead=$'\n'
        fi
        # Never fatal. `2>/dev/null` is placed BEFORE the append so a failed redirection
        # stays quiet, and testing it in an `if` keeps `set -e` from killing the whole
        # run over an ignore entry.
        if printf '%s%s/\n' "${lead}" "${entry}" 2>/dev/null >> "${gitignore}"; then
            echo -e "${GREEN:-}[OK]${NC:-} Added ${entry}/ to ${gitignore}"
        else
            skip_reason="unwritable"
        fi
    fi

    case "${skip_reason}" in
        ''|already-ignored|already-listed|absolute-outside-work-tree) ;;
        *)
            echo -e "${YELLOW:-}[WARN]${NC:-} Could not gitignore ${report_dir} (${skip_reason})"
            echo "  Keep audit reports out of your commits: they can quote matched secrets"
            ;;
    esac
    return 0
}

# Create the resolved directory and make it safe to write into.
#
# The 0700 is on the DIRECTORY, not on individual files. Redaction means a report no
# longer carries secret VALUES, but it still names the files a secret scanner matched in
# and quotes lines out of the audited source, and on a shared machine the default 0755
# publishes that to every other account. Per-file permissions would have to enumerate
# which reports are sensitive — a classification that goes stale the moment another tool
# writes here, and several write their own files directly (tee, jest --coverageDirectory,
# jq). One directory mode covers all of them, now and later.
#
# Only applied to a directory this run creates. An existing directory belongs to whoever
# made it, and silently tightening a path the caller chose is not this function's call.
cqt_prepare_report_dir() {
    local report_dir="${REPORT_DIR}"

    if [ ! -d "${report_dir}" ]; then
        if mkdir -p "${report_dir}" 2>/dev/null; then
            chmod 700 "${report_dir}" 2>/dev/null || true
            echo -e "${GREEN:-}[OK]${NC:-} Created report directory: ${report_dir}"
        else
            echo -e "${YELLOW:-}[WARN]${NC:-} Could not create report directory: ${report_dir}"
            return 0
        fi
    fi

    cqt_gitignore_report_dir "${report_dir}"

    # The pointer is decided at the END of the run, not here. See
    # cqt_report_dir_latest_pointer for why, and cqt_report_dir_on_exit for how.
    trap 'cqt_report_dir_on_exit' EXIT
    return 0
}

# A stable name for the most recent run under the state root.
#
# The out-of-repo path carries a timestamp, which is what lets successive audits of one
# repository accumulate into something you can compare. It also makes the current run's
# directory unguessable, so without a fixed entry point the reports are effectively
# write-only: anything that wants to read them back — a follow-up command, a script, a
# person — would have to scrape the path out of console output.
#
# Only for the state root. The project path is <project>/audits/<date>/, which is already
# a name you can predict, and dropping a symlink into somebody's project record to solve
# a problem it does not have is not worth the intrusion.
#
# And only for a run that actually WROTE something. This used to be called from
# cqt_prepare_report_dir, one line after the mkdir, so the pointer moved on the strength
# of a directory having been created. Every script in the suite creates that directory,
# including install-tools.sh, which writes a tools-status report only on some paths, and
# rector-fix.sh, which writes nothing at all when rector is missing. `latest` then names
# an empty directory and the last real report becomes unreachable by the only fixed name
# it had. Emptiness is the test because it is the honest one: it asks whether a report is
# there, not whether a script believed it was about to write one.
cqt_report_dir_latest_pointer() {
    [ "${REPORT_DIR_ORIGIN:-}" = "state" ] || return 0
    local run_dir="${1:-}"
    [ -n "${run_dir}" ] && [ -d "${run_dir}" ] || return 0
    local parent="${run_dir%/*}"
    [ -n "${parent}" ] && [ "${parent}" != "${run_dir}" ] || return 0

    local entry="" wrote=0
    for entry in "${run_dir}"/* "${run_dir}"/.[!.]*; do
        if [ -e "${entry}" ]; then wrote=1; break; fi
    done
    [ "${wrote}" -eq 1 ] || return 0

    # -n so an existing pointer is replaced rather than followed into the directory it
    # points at, which would nest a "latest" inside the previous run.
    ln -sfn "${run_dir}" "${parent}/latest" 2>/dev/null || true
    return 0
}

# Installed on EXIT by cqt_prepare_report_dir, because "did this run produce a report"
# is a question only the end of the run can answer. No script in this suite sets its own
# EXIT trap, so there is nothing here to clobber.
#
# The incoming status is captured first and returned, so nothing this handler does can
# change the exit code the caller sees.
cqt_report_dir_on_exit() {
    local rc=$?
    cqt_report_dir_latest_pointer "${REPORT_DIR:-}"
    return "${rc}"
}

# Say where the report went. With the resolution above it is no longer the obvious
# ./.reports, and a report nobody can find is a report nobody reads.
#
# The parenthesised half names the rule that chose the directory — except for the state
# path, where it also makes a claim about a LOCATION. That claim used to be printed on the
# strength of the origin label alone, so a run whose state root resolved back into the
# audited repository created the directory there, appended to that repository's .gitignore
# and then printed "(outside the audited repository)" about it. The resolution above is
# what stops that happening; this is what stops the line asserting it either way.
#
# So the location half is MEASURED, against the same containment test the resolution uses.
# A tool that breaks its invariant is a bug; a tool that breaks it and prints a claim that
# it did not is the failure this whole change exists to remove, so the announcement is not
# allowed to be the last thing still trusting the label.
cqt_announce_report_dir() {
    local why=""
    case "${REPORT_DIR_ORIGIN:-}" in
        explicit)       why="explicit REPORT_DIR" ;;
        project)        why="ai-dev-assistant project" ;;
        state)          why="outside the audited repository" ;;
        in-repo-opt-in) why="in-repo opt-in, REPORT_DIR_IN_REPO=1" ;;
        *)              why="unresolved" ;;
    esac

    if cqt_report_dir_is_inside "${REPORT_DIR:-}"; then
        case "${REPORT_DIR_ORIGIN:-}" in
            # Already says where it is, and being there is what was asked for.
            in-repo-opt-in) ;;
            # The one label that would be a straight contradiction, so it is replaced
            # rather than qualified.
            state) why="INSIDE the audited repository, which the out-of-repo rule must never produce" ;;
            *)     why="${why}, inside the audited repository" ;;
        esac
    fi

    echo "Report directory: ${REPORT_DIR} (${why})"
    return 0
}

# What a script calls. Resolve, then create.
cqt_report_dir_init() {
    cqt_resolve_report_dir
    cqt_prepare_report_dir
    return 0
}

# ---------------------------------------------------------------------------------
# Entry point for consumers that cannot source this file.
#
# The scripts source the rule, so they agree by construction. Everything else in this
# plugin - the slash commands, the pre-compact hook, the reference material a person
# follows by hand - is markdown or a standalone hook, and markdown cannot source a shell
# file. Before this entry point existed, the only thing those consumers could do was
# write down a directory name, and the one they had written down was `.reports`. So the
# agent-driven half of the plugin went on creating the directory inside the audited
# repository that the resolution above exists to stop creating, and went on reading from
# a path the scripts no longer write to.
#
# The fix is not another copy of the rule. It is one command any consumer can run:
#
#     bash "<plugin>/skills/code-quality-audit/scripts/core/report-dir.sh" --print
#
# --print resolves and creates nothing, because a consumer asking where reports go is
# usually not the one about to write them, and a bare question should not leave a
# directory behind. Creation stays with cqt_report_dir_init, which the writing scripts
# already call.
# ---------------------------------------------------------------------------------

# The newest immediate subdirectory of a parent, by name. Both layouts that accumulate
# runs - <project>/audits/<date>/ and <state>/<project>/<timestamp>/ - use names that
# sort chronologically, which is why they are named that way.
#
# `latest` is skipped: it is the pointer, not a run, and it sorts after most timestamps.
cqt_report_dir_newest_child() {
    local parent="${1%/}"
    local newest="" entry="" name=""
    [ -n "${parent}" ] || return 1
    [ -d "${parent}" ] || return 1
    for entry in "${parent}"/*/; do
        entry="${entry%/}"
        if [ ! -d "${entry}" ]; then continue; fi
        name="${entry##*/}"
        if [ "${name}" = "latest" ]; then continue; fi
        if [ -z "${newest}" ] || [[ "${name}" > "${newest##*/}" ]]; then
            newest="${entry}"
        fi
    done
    [ -n "${newest}" ] || return 1
    printf '%s' "${newest}"
    return 0
}

# Where the most recent run's reports actually ARE, which is a different question from
# where the next run would write them, and the one every READER is asking.
#
# Resolving fresh answers the writer's question. The state path carries a per-run
# timestamp, so a fresh resolution names a directory that does not exist yet; the project
# path carries a date, so a fresh resolution on a later day names an empty one. A reader
# handed either would report "no findings" about a report that exists.
#
# Returns 1 and prints nothing when nothing has been written yet. That is the honest
# answer, and it lets a caller say "run the audit first" instead of describing an empty
# directory as a clean result - the exact confusion this branch exists to remove.
cqt_report_dir_latest() {
    cqt_resolve_report_dir
    local parent=""
    case "${REPORT_DIR_ORIGIN:-}" in
        explicit|in-repo-opt-in)
            # The caller named the directory; there is no history to search.
            [ -d "${REPORT_DIR}" ] || return 1
            printf '%s' "${REPORT_DIR%/}"
            return 0
            ;;
        state)
            # The pointer the run drops beside itself is the intended entry point.
            parent="${REPORT_DIR%/*}"
            if [ -d "${parent}/latest" ]; then
                printf '%s' "${parent}/latest"
                return 0
            fi
            cqt_report_dir_newest_child "${parent}"
            return $?
            ;;
        project)
            if [ -d "${REPORT_DIR}" ]; then
                printf '%s' "${REPORT_DIR%/}"
                return 0
            fi
            cqt_report_dir_newest_child "${REPORT_DIR%/*}"
            return $?
            ;;
    esac
    return 1
}

cqt_report_dir_usage() {
    cat <<'CQT_REPORT_DIR_USAGE'
Usage: report-dir.sh [--print | --ensure | --latest | --origin | --help]

  --print   Where the NEXT run would write. Resolves only; creates nothing.
  --ensure  Same path, created and prepared. Use this before writing.
  --latest  Where the MOST RECENT run actually wrote. Prints nothing and exits 1
            when no run has written yet.
  --origin  Which rule --print applied: explicit | project | state | in-repo-opt-in.

Sourced by every script in this suite. Run directly by anything that needs the same
answer without sourcing - a hook, a slash command, a person - so that no consumer has
to write a report directory name down and get it wrong.
CQT_REPORT_DIR_USAGE
}

cqt_report_dir_main() {
    local resolved=""
    case "${1:-}" in
        --print)
            cqt_resolve_report_dir
            printf '%s\n' "${REPORT_DIR}"
            ;;
        --ensure)
            # A caller that is about to WRITE must not create the directory itself. The
            # 0700, the gitignore entry on the in-repo opt-in path, and the pointer are
            # all attached to creation here; a consumer's own `mkdir -p` gets 0755 and
            # publishes reports that quote the audited source to every account on a
            # shared machine. Creation stays in one place, so it keeps happening.
            #
            # cqt_report_dir_init narrates to stdout. That belongs on stderr here, or it
            # would be captured as part of the path by the `$(...)` this mode exists for.
            cqt_report_dir_init >&2
            printf '%s\n' "${REPORT_DIR}"
            ;;
        --origin)
            cqt_resolve_report_dir
            printf '%s\n' "${REPORT_DIR_ORIGIN}"
            ;;
        --latest)
            # No run yet is not an error in this script's own terms, but it IS the
            # caller's branch point, so it has to be visible as a status rather than as
            # an empty string the caller might paste into a path.
            if resolved="$(cqt_report_dir_latest)" && [ -n "${resolved}" ]; then
                printf '%s\n' "${resolved}"
            else
                return 1
            fi
            ;;
        -h|--help)
            cqt_report_dir_usage
            ;;
        *)
            cqt_report_dir_usage >&2
            return 2
            ;;
    esac
    return 0
}

# Sourced or executed. BASH_SOURCE[0] is this file either way; $0 is this file only when
# it was executed. The unset test covers a non-bash shell, where BASH_SOURCE does not
# exist at all and treating the run as "sourced" would exit 0 having printed nothing -
# a silent wrong answer, which is worse than the syntax error that follows.
if [ -z "${BASH_SOURCE+x}" ] || [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    cqt_report_dir_main "$@"
    exit $?
fi
