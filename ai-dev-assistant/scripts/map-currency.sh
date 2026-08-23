#!/usr/bin/env bash
# map-currency.sh — is a code map current enough to trust?
#
# A stale map is worse than no map. One that has not seen this morning's commit answers "nothing like
# this exists" and sends the research phase off to build a duplicate, with a citation attached. So
# this kernel decides currency from the ARTIFACT against the REPOSITORY — the map file's mtime versus
# the repository's last commit — and never from a tool-provided signal. The recommended tool
# documents neither a build timestamp nor a status command, so anything resting on a tool API would
# rest on nothing.
#
# Usage:
#   map-currency.sh --map-path <path> --repo <repo-root> [--freshness-report <path>]
#
# Emits ONE JSON object to stdout:
#   { present, map_path, map_mtime, last_commit_at, status, reason,
#     freshness_report: { given, used, status }, warnings: [] }
#
# status:
#   current  — the map is at least as new as the last commit
#   stale    — code landed after the map was built; the map cannot know about it
#   absent   — no map. The DEFAULT, and not a problem: the search reads code directly.
#   unknown  — there is an artifact but currency is not decidable (no git, no commits, git failed).
#              Never reported as `current`. Not knowing is its own answer; guessing is how a stale
#              map gets trusted.
#
# THE FRAMEWORK NEVER EXECUTES THE MAPPING TOOL. Setup is consented and manual, and the contract
# forbids running it unattended. `--freshness-report` reads a file the USER's tool already wrote; it
# is a bonus input folded in when present and valid, and nothing depends on it. No tool binary is
# ever invoked from here — not to check a version, not to ask a status.
#
# Defensive posture (project-state-read.sh): always JSON, always exit 0 on a recoverable state,
# problems in warnings[].
set -uo pipefail

MAP_PATH=""; REPO=""; FRESHNESS_REPORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --map-path)          MAP_PATH="${2:-}"; shift 2 || shift ;;
    --repo)              REPO="${2:-}"; shift 2 || shift ;;
    --freshness-report)  FRESHNESS_REPORT="${2:-}"; shift 2 || shift ;;
    *)                   shift ;;
  esac
done

WARNINGS='[]'
add_warn(){ WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS" 2>/dev/null || printf '[]'); }

if ! command -v jq >/dev/null 2>&1; then
  printf '{"present":false,"status":"unknown","reason":"jq_missing","warnings":["jq_missing"]}\n'
  exit 0
fi

emit(){ # emit <present> <status> <reason> <map_mtime|null> <last_commit|null> <fr_given> <fr_used> <fr_status>
  jq -n --argjson present "$1" --arg status "$2" --arg reason "$3" \
        --argjson mtime "$4" --argjson commit "$5" \
        --argjson frgiven "$6" --argjson frused "$7" --arg frstatus "$8" \
        --arg map "$MAP_PATH" --argjson warnings "$WARNINGS" \
    '{schema_version:"1.0",
      present:$present, map_path:(if $map=="" then null else $map end),
      map_mtime:$mtime, last_commit_at:$commit,
      status:$status, reason:$reason,
      freshness_report:{given:$frgiven, used:$frused,
                        status:(if $frstatus=="" then null else $frstatus end)},
      warnings:$warnings}'
  exit 0
}

FR_GIVEN=false; FR_STATUS=""
[ -n "$FRESHNESS_REPORT" ] && FR_GIVEN=true

# --- the map artifact --------------------------------------------------------------------------
if [ -z "$MAP_PATH" ]; then
  add_warn "no_map_path_given"
  emit false absent "no map path given" null null "$FR_GIVEN" false ""
fi
if [ ! -e "$MAP_PATH" ]; then
  emit false absent "no map artifact at the recorded path" null null "$FR_GIVEN" false ""
fi
if [ -d "$MAP_PATH" ]; then
  # A directory is not an artifact whose mtime means anything: it changes when any child is touched.
  add_warn "map_path_is_a_directory"
  emit false unknown "map path is a directory, not a map artifact" null null "$FR_GIVEN" false ""
fi
if [ ! -r "$MAP_PATH" ]; then
  add_warn "map_unreadable"
  emit true unknown "map artifact is not readable" null null "$FR_GIVEN" false ""
fi

MAP_MTIME="$(stat -c %Y "$MAP_PATH" 2>/dev/null || stat -f %m "$MAP_PATH" 2>/dev/null || printf '')"
if [ -z "$MAP_MTIME" ]; then
  add_warn "map_mtime_unavailable"
  emit true unknown "could not read the map artifact's modification time" null null "$FR_GIVEN" false ""
fi

# --- the tool's own freshness report: a bonus, never a dependency -------------------------------
# Read from a file the user's tool wrote. NEVER invoke a tool to produce one.
if [ "$FR_GIVEN" = true ]; then
  if [ ! -r "$FRESHNESS_REPORT" ]; then
    add_warn "freshness_report_unreadable"
  elif ! jq empty "$FRESHNESS_REPORT" >/dev/null 2>&1; then
    add_warn "freshness_report_malformed"
  else
    FR_STATUS="$(jq -r '.status // ""' "$FRESHNESS_REPORT" 2>/dev/null)"
    case "$FR_STATUS" in
      stale|current)
        # emit's 7th argument IS the "report was used" flag; no separate variable to drift from it.
        emit true "$FR_STATUS" "the tool's own freshness report says $FR_STATUS" \
             "$MAP_MTIME" null true true "$FR_STATUS"
        ;;
      "") add_warn "freshness_report_has_no_status" ;;
      *)  add_warn "freshness_report_status_unrecognised:$FR_STATUS" ;;
    esac
  fi
fi

# --- the repository's last commit ---------------------------------------------------------------
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
  add_warn "repo_not_a_directory"
  emit true unknown "no repository to compare against" "$MAP_MTIME" null "$FR_GIVEN" false "$FR_STATUS"
fi
if ! command -v git >/dev/null 2>&1; then
  add_warn "git_missing"
  emit true unknown "git is not available, so currency cannot be established" "$MAP_MTIME" null "$FR_GIVEN" false "$FR_STATUS"
fi
if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  add_warn "not_a_git_repository"
  emit true unknown "the code path is not a git repository" "$MAP_MTIME" null "$FR_GIVEN" false "$FR_STATUS"
fi

# Capture first, then test the captured text. Never branch on a pipeline's exit status under
# pipefail — that is what silently corrupted ledger-index.sh's output.
LAST_COMMIT="$(git -C "$REPO" log -1 --format=%ct 2>/dev/null)" || LAST_COMMIT=""
case "$LAST_COMMIT" in
  ''|*[!0-9]*)
    add_warn "no_commits_or_git_failed"
    emit true unknown "the repository has no commits to compare against" "$MAP_MTIME" null "$FR_GIVEN" false "$FR_STATUS"
    ;;
esac

if [ "$MAP_MTIME" -ge "$LAST_COMMIT" ]; then
  emit true current "the map is newer than the last commit" "$MAP_MTIME" "$LAST_COMMIT" "$FR_GIVEN" false "$FR_STATUS"
else
  emit true stale "code was committed after the map was built, so the map cannot know about it" \
       "$MAP_MTIME" "$LAST_COMMIT" "$FR_GIVEN" false "$FR_STATUS"
fi
