#!/usr/bin/env bash
# change-impact-classify.sh — classify a code diff into recommended review gates.
#
# Usage: change-impact-classify.sh <task_folder> [--base <ref>] [--files-from <path>] [--rules-from <path>]
#
#   <task_folder>   absolute path to the task folder. Used only to locate the
#                   project (walk up to project_state.md) for the optional
#                   per-project rule override. May be omitted/invalid — the
#                   script then uses the shipped default rules.
#   --base <ref>    git ref to diff against. Default: merge-base of main..HEAD,
#                   matching commands/review.md step 4.
#   --files-from    newline-delimited file list, used INSTEAD of git diff.
#                   Makes the classifier testable without a git fixture.
#   --rules-from    OPTIONAL JSON file ({ "rules": [ {glob,gates[]}, ... ] }) of
#                   ADDITIONAL, framework-specific rules to UNION onto the base
#                   ruleset. The caller RECONSTRUCTS this list on the fly from
#                   the active framework's first-party review recipe each run
#                   (the `## Change-impact globs` declaration) — the kernel ships
#                   NO framework-specific globs of its own. Because gates are
#                   unioned across every matching rule, merge order is irrelevant.
#                   A missing/malformed file is ignored with a warning (the base
#                   floor still classifies); it never fails the run.
#
# The classifier is a RECOMMENDER input: it maps changed files to the gates a
# change could justify (commands/review.md step 6 / change-impact-dispatch.md).
# It never runs a gate and never blocks.
#
# Rules: references/visual-review/change-impact-rules.json (shipped FRAMEWORK-NEUTRAL
#        floor — stylesheet / plain-script / markup extensions only, no framework
#        file types).
# Framework globs: supplied per run via --rules-from from the stack's review recipe.
# Override: <project>/.visual-review/change-impact.json (full replacement of the floor).
# See references/visual-review/change-impact-rules.md.
#
# Output: single JSON object to stdout. ALWAYS exit 0 (recoverable issues
# surface in warnings[]); non-zero only on a bash-level failure that prevents
# emitting JSON at all.
#
#   {
#     "schema_version": "1.0",
#     "diff_signature": ["**/*.css", "**/*.ts"],     # distinct matched rule globs
#     "gates_recommended": ["visual_regression"],     # sorted union over all files
#     "rule_source": "default" | "project-override" | "default+recipe" | "project-override+recipe",
#     "files_classified": 7,
#     "warnings": [ "<code>: <detail>", ... ]
#   }

set -uo pipefail

WARNINGS=()
add_warning() { WARNINGS+=("$1"); }

emit() {
  # $1 diff_signature JSON array, $2 gates_recommended JSON array,
  # $3 rule_source, $4 files_classified int
  local warn_json
  if [ "${#WARNINGS[@]}" -eq 0 ]; then
    warn_json='[]'
  else
    warn_json=$(printf '%s\n' "${WARNINGS[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))')
  fi
  jq -nc \
    --argjson sig "${1:-[]}" \
    --argjson gates "${2:-[]}" \
    --arg src "${3:-default}" \
    --argjson n "${4:-0}" \
    --argjson w "$warn_json" \
    '{schema_version: "1.0", diff_signature: $sig, gates_recommended: $gates,
      rule_source: $src, files_classified: $n, warnings: $w}'
  exit 0
}

# --- arg parsing ---------------------------------------------------------
TASK_FOLDER=""
BASE_REF=""
FILES_FROM=""
RULES_FROM=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then BASE_REF="$2"; shift 2
      else add_warning "bad_arg: --base requires a value — ignored"; shift; fi
      ;;
    --files-from)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then FILES_FROM="$2"; shift 2
      else add_warning "bad_arg: --files-from requires a value — ignored"; shift; fi
      ;;
    --rules-from)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then RULES_FROM="$2"; shift 2
      else add_warning "bad_arg: --rules-from requires a value — ignored"; shift; fi
      ;;
    *)
      if [ -z "$TASK_FOLDER" ]; then TASK_FOLDER="$1"; fi
      shift
      ;;
  esac
done

# --- resolve the ruleset -------------------------------------------------
# Shipped defaults live next to this script's plugin root.
PLUGIN_ROOT="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
DEFAULT_RULES="$PLUGIN_ROOT/references/visual-review/change-impact-rules.json"

RULES_JSON=""
RULE_SOURCE="default"

# Walk up from the task folder to find the project root (the dir with
# project_state.md), then look for a per-project override.
find_project_root() {
  local d="$1"
  d="$(readlink -f "$d" 2>/dev/null || echo "$d")"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -f "$d/project_state.md" ]; then echo "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  return 1
}

if [ -n "$TASK_FOLDER" ] && [ -d "$TASK_FOLDER" ]; then
  if PROJECT_ROOT="$(find_project_root "$TASK_FOLDER")"; then
    OVERRIDE="$PROJECT_ROOT/.visual-review/change-impact.json"
    if [ -f "$OVERRIDE" ]; then
      # `.rules` must be an ARRAY — `jq -e '.rules'` alone is truthy for a JSON
      # object too, which would accept a malformed `rules: {}` override silently.
      if jq -e '.rules | type == "array"' "$OVERRIDE" >/dev/null 2>&1; then
        RULES_JSON="$(cat "$OVERRIDE")"
        RULE_SOURCE="project-override"
      else
        add_warning "override_malformed: $OVERRIDE has no \`rules\` array — using defaults"
      fi
    fi
  fi
elif [ -n "$TASK_FOLDER" ]; then
  add_warning "task_folder_missing: $TASK_FOLDER does not exist — override lookup skipped"
fi

if [ -z "$RULES_JSON" ]; then
  if [ -f "$DEFAULT_RULES" ] && jq -e '.rules | type == "array"' "$DEFAULT_RULES" >/dev/null 2>&1; then
    RULES_JSON="$(cat "$DEFAULT_RULES")"
  else
    add_warning "default_rules_missing: $DEFAULT_RULES not found or malformed"
    emit '[]' '[]' "$RULE_SOURCE" 0
  fi
fi

# Flatten rules to TAB-separated lines: <glob>\t<comma-gates>.
# Defensive per-rule: skip rules whose `glob` is not a string, and coerce a
# non-array `gates` to []. One malformed rule must not poison the whole batch.
RULE_LINES="$(echo "$RULES_JSON" | jq -r '
  .rules[]
  | select((.glob | type) == "string")
  | .glob + "\t" + ((.gates // []) | (if type == "array" then . else [] end) | join(","))
' 2>/dev/null || true)"
DEFAULT_GATES="$(echo "$RULES_JSON" | jq -r '(.default_gates // []) | join(",")' 2>/dev/null || true)"

# --- merge the per-run, recipe-reconstructed framework rules (--rules-from) ----
# These are UNIONED onto the base floor: the same per-rule defensive flattening,
# appended to RULE_LINES. Because gates are unioned across every matching rule,
# append order does not change the result. A missing/malformed file is ignored
# with a warning — the base floor still classifies (never fail the run).
if [ -n "$RULES_FROM" ]; then
  if [ ! -f "$RULES_FROM" ]; then
    add_warning "rules_from_missing: $RULES_FROM does not exist — framework globs not merged"
  elif ! jq -e '.rules | type == "array"' "$RULES_FROM" >/dev/null 2>&1; then
    add_warning "rules_from_malformed: $RULES_FROM has no \`rules\` array — framework globs not merged"
  else
    RECIPE_RULE_LINES="$(jq -r '
      .rules[]
      | select((.glob | type) == "string")
      | .glob + "\t" + ((.gates // []) | (if type == "array" then . else [] end) | join(","))
    ' "$RULES_FROM" 2>/dev/null || true)"
    if [ -n "$RECIPE_RULE_LINES" ]; then
      if [ -n "$RULE_LINES" ]; then
        RULE_LINES="$RULE_LINES"$'\n'"$RECIPE_RULE_LINES"
      else
        RULE_LINES="$RECIPE_RULE_LINES"
      fi
      RULE_SOURCE="${RULE_SOURCE}+recipe"
    fi
  fi
fi

# --- collect the changed-file list --------------------------------------
FILES=""
if [ -n "$FILES_FROM" ]; then
  if [ -f "$FILES_FROM" ]; then
    FILES="$(cat "$FILES_FROM")"
  else
    add_warning "files_from_missing: $FILES_FROM does not exist — empty file list"
  fi
else
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BASE="$BASE_REF"
    if [ -z "$BASE" ]; then
      BASE="$(git merge-base main HEAD 2>/dev/null || true)"
    fi
    if [ -n "$BASE" ]; then
      # Capture git's exit code — a bad/unknown --base ref must surface a
      # warning, not silently yield an empty diff the dispatcher trusts.
      if ! FILES="$(git diff "$BASE"..HEAD --name-only 2>/dev/null)"; then
        add_warning "bad_base_ref: git diff $BASE..HEAD failed (unknown ref?) — empty file list"
        FILES=""
      fi
    else
      add_warning "no_merge_base: could not resolve merge-base of main..HEAD — empty file list"
    fi
  else
    add_warning "not_a_git_repo: not inside a git work tree — empty file list"
  fi
fi

# --- classify ------------------------------------------------------------
matched_gates=""
matched_globs=""
count=0

while IFS= read -r file; do
  file="${file%$'\r'}"          # strip trailing CR — CRLF-terminated --files-from lists
  [ -z "$file" ] && continue
  count=$((count + 1))
  file_matched=0
  while IFS=$'\t' read -r glob gates; do
    [ -z "$glob" ] && continue
    core="${glob#'**/'}"          # leading **/ is "any depth"; bash * spans /
    # shellcheck disable=SC2053
    if [[ "$file" == $core ]]; then
      file_matched=1
      matched_globs+="${glob}"$'\n'
      [ -n "$gates" ] && matched_gates+="${gates//,/$'\n'}"$'\n'
    fi
  done <<< "$RULE_LINES"
  if [ "$file_matched" -eq 0 ] && [ -n "$DEFAULT_GATES" ]; then
    matched_gates+="${DEFAULT_GATES//,/$'\n'}"$'\n'
  fi
done <<< "$FILES"

SIG_JSON=$(printf '%s' "$matched_globs" | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique')
GATES_JSON=$(printf '%s' "$matched_gates" | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique')

emit "$SIG_JSON" "$GATES_JSON" "$RULE_SOURCE" "$count"
