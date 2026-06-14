#!/usr/bin/env bash
# project-state-read.sh — parse a project's project_state.md header block.
#
# Usage: project-state-read.sh <project_folder>
#
# Always emits a single-line JSON to stdout. Exit 0 regardless of input
# (warnings surface via the warnings[] array). Mirrors the defensive posture
# of task-frontmatter-reader.sh from v3.10.0.
#
# Output shape:
#   {
#     "project_name": "<name or folder basename>",
#     "codePath": "<absolute path or null>",
#     "folder": "<abs path to project folder>",
#     "playbookSets": ["<set-id>", ...],
#     "playbookSetsSource": "explicit" | "explicit-none" | "default",
#     "userPlaybook": "<absolute path or null>",
#     "userPlaybookState": "unset" | "docs-only-no-playbook" | "set",
#     "playbookResolutions": [{"topic": "<t>", "set": "<set-id>"}, ...],
#     "worktreeByDefault": bool,
#     "reviewRequired": bool | null,    # v4.1.0+ — null when absent (legacy default applies in /complete)
#     "visualReview": null | {"enabled": bool, "registryPath": "<rel>" | null},  # v4.11.0+
#     "frameworks": ["<framework-id>", ...],  # e.g. ["nextjs","symfony"]; [] when absent
#     "localGuidesPath": "<rel-path>" | null,  # path to local dev-guides; null when absent
#     "processRecipes": [{"key": "<phase>/<fw>/<name>", "source": "<dev-guides|local|machine-local|research>" | null}, ...],
#     "warnings": [{"code": "<code>", "detail": "..."}]
#   }
#
# Warning codes:
#   missing_arg                — script called without $1 (defensive; emit + exit 0)
#   folder_missing             — project folder does not exist
#   project_state_md_missing   — project_state.md not in folder
#   code_path_unknown          — project_state.md has no Code path line (first-use case)
#   code_path_missing          — Code path declares a directory that does not exist
#   visual_review_bad_state    — **Visual Review:** state token is not enabled|disabled
#   visual_review_no_path      — **Visual Review:** line has a state but no registry path
#   visual_review_path_escape  — **Visual Review:** registry path escapes the project folder
#   process_recipe_bad_source  — a process_recipes slot has source not in dev-guides|local|research
#
# codePath sentinels in project_state.md:
#   **Code path:** /abs/path    → non-null string
#   **Code path:** (docs-only)  → null (docs-only project)
#   (absent)                    → null + warning code_path_unknown
#
# Visual Review field (v4.11.0+):
#   **Visual Review:** enabled .visual-review/registry.yml   → {enabled:true,  registryPath:"..."}
#   **Visual Review:** disabled .visual-review/registry.yml  → {enabled:false, registryPath:"..."}
#   (absent)                                                 → null (feature not set up)
#
# No writes. No side effects. This script only reads.

set -uo pipefail

# Defensive contract: emit JSON-stdout + exit 0 always, even on bad inputs.
# Mirrors task-frontmatter-reader. Caller (e.g., upgrade-project.md) trusts exit 0.
PROJECT_DIR="${1:-}"
FOLDER_NAME=$(basename "${PROJECT_DIR:-(missing)}")
PROJECT_STATE="${PROJECT_DIR}/project_state.md"

emit_json() {
  # $1 = project_name, $2 = codePath (string "null" literal for null), $3 = folder, $4 = warnings JSON array
  # $5 = playbookSets JSON array, $6 = playbookSetsSource string,
  # $7 = userPlaybook (string "null" literal for null), $8 = userPlaybookState string,
  # $9 = playbookResolutions JSON array
  # $10 = worktreeByDefault bool string, $11 = reviewRequired bool|"null", $12 = visualReview JSON
  # $13 = frameworks JSON array, $14 = localGuidesPath (string "null" for null),
  # $15 = processRecipes JSON array
  jq -nc \
    --arg n "$1" --arg cp "$2" --arg d "$3" \
    --argjson w "$4" \
    --argjson ps "${5:-[]}" --arg pss "${6:-default}" \
    --arg up "${7:-null}" --arg ups "${8:-unset}" \
    --argjson pr "${9:-[]}" \
    --argjson wbd "${10:-false}" \
    --arg rr "${11:-null}" \
    --argjson vr "${12:-null}" \
    --argjson fr "${13:-[]}" \
    --arg lgp "${14:-null}" \
    --argjson rec "${15:-[]}" '
    {
      project_name: $n,
      codePath: (if $cp == "null" then null else $cp end),
      folder: $d,
      playbookSets: $ps,
      playbookSetsSource: $pss,
      userPlaybook: (if $up == "null" then null else $up end),
      userPlaybookState: $ups,
      playbookResolutions: $pr,
      worktreeByDefault: $wbd,
      reviewRequired: (if $rr == "null" then null elif $rr == "true" then true else false end),
      visualReview: $vr,
      frameworks: $fr,
      localGuidesPath: (if $lgp == "null" then null else $lgp end),
      processRecipes: $rec,
      warnings: $w
    }'
}

# Append a {code, detail} object to the WARNINGS JSON array (v4.11.0+).
# WARNINGS is initialized below; this helper resolves it at call time.
add_warning() {
  WARNINGS=$(jq -c -n --argjson w "$WARNINGS" --arg c "$1" --arg d "$2" \
    '$w + [{code: $c, detail: $d}]')
}

# Resolve framework default playbook sets from the plugin's defaults.json.
# Kept out of plugin.json: non-standard manifest keys trip `claude plugin
# validate`. Forks override the default by editing defaults.json.
PLUGIN_DEFAULTS_PATH="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/defaults.json"
get_default_playbook_sets() {
  if [ -f "$PLUGIN_DEFAULTS_PATH" ]; then
    jq -c '.playbookSets // []' "$PLUGIN_DEFAULTS_PATH" 2>/dev/null || echo "[]"
  else
    echo "[]"
  fi
}

DEFAULT_PB_SETS=$(get_default_playbook_sets)

# H1 fix (v4.1.0): missing arg → defensive emit, do NOT exit 1
if [ -z "$PROJECT_DIR" ]; then
  emit_json "(no project)" "null" "" '[{"code": "missing_arg", "detail": "path to project folder required as $1"}]' \
    "$DEFAULT_PB_SETS" "default" "null" "unset" "[]" "false" "[]" "null" "[]"
  exit 0
fi

# Normalize bool string from project_state.md value (DRY — used by Worktree By Default + Review Required).
# Truthy variants: true, True, TRUE, yes, y, 1, on (case-insensitive). Empty input → "null" sentinel
# (caller decides how to treat absence). All other values → "false".
parse_bool() {
  local raw="$1" norm
  norm=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  case "$norm" in
    true|yes|y|1|on)  echo "true" ;;
    "")               echo "null" ;;
    *)                echo "false" ;;
  esac
}

if [ ! -d "$PROJECT_DIR" ]; then
  emit_json "$FOLDER_NAME" "null" "$PROJECT_DIR" '[{"code": "folder_missing", "detail": "project folder does not exist"}]' \
    "$DEFAULT_PB_SETS" "default" "null" "unset" "[]" "false" "[]" "null" "[]"
  exit 0
fi

if [ ! -f "$PROJECT_STATE" ]; then
  emit_json "$FOLDER_NAME" "null" "$PROJECT_DIR" '[{"code": "project_state_md_missing", "detail": "project_state.md not found in folder"}]' \
    "$DEFAULT_PB_SETS" "default" "null" "unset" "[]" "false" "[]" "null" "[]"
  exit 0
fi

# Extract the H1 project name (first `# <name>` line)
PROJECT_NAME=$(awk '/^# / {sub(/^# */,""); print; exit}' "$PROJECT_STATE")
[ -z "$PROJECT_NAME" ] && PROJECT_NAME="$FOLDER_NAME"

# Extract the code path line. Accepts any of:
#   **Code path:** /abs/path
#   **Code Path:** /abs/path
#   **code path:** /abs/path
# Plus the (docs-only) sentinel.
CODE_PATH_RAW=$(awk '
  /^\*\*[Cc]ode [Pp]ath:\*\*/ {
    sub(/^\*\*[Cc]ode [Pp]ath:\*\*[[:space:]]*/, "")
    print
    exit
  }
' "$PROJECT_STATE")

WARNINGS='[]'

if [ -z "$CODE_PATH_RAW" ]; then
  WARNINGS='[{"code": "code_path_unknown", "detail": "project_state.md has no **Code path:** line"}]'
  CODE_PATH_OUT="null"
elif [ "$CODE_PATH_RAW" = "(docs-only)" ] || [ "$CODE_PATH_RAW" = "docs-only" ]; then
  CODE_PATH_OUT="null"
else
  # Normalize: expand leading ~ via parameter expansion (NO eval — adversarial
  # input like `$(rm -rf ~)` would execute under eval); realpath -m doesn't
  # require existence.
  CODE_PATH_EXPANDED="${CODE_PATH_RAW/#\~/$HOME}"
  CODE_PATH_NORM=$(realpath -m "$CODE_PATH_EXPANDED" 2>/dev/null || echo "$CODE_PATH_EXPANDED")
  if [ ! -d "$CODE_PATH_NORM" ]; then
    WARNINGS=$(jq -c -n --arg p "$CODE_PATH_NORM" '[{code: "code_path_missing", detail: ("directory does not exist: " + $p)}]')
  fi
  CODE_PATH_OUT="$CODE_PATH_NORM"
fi

# === Playbook Sets parsing ===
PB_SETS_RAW=$(awk '
  /^\*\*[Pp]laybook [Ss]ets:\*\*/ {
    sub(/^\*\*[Pp]laybook [Ss]ets:\*\*[[:space:]]*/, "")
    print
    exit
  }
' "$PROJECT_STATE")

if [ -z "$PB_SETS_RAW" ]; then
  PB_SETS_OUT="$DEFAULT_PB_SETS"
  PB_SETS_SOURCE="default"
elif [ "$PB_SETS_RAW" = "none" ]; then
  PB_SETS_OUT="[]"
  PB_SETS_SOURCE="explicit-none"
else
  # Comma-split, trim, drop empties, JSON-encode (M2 fix v4.1.0: filter empty strings)
  PB_SETS_OUT=$(echo "$PB_SETS_RAW" | jq -R -c 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')
  [ -z "$PB_SETS_OUT" ] && PB_SETS_OUT="[]"
  PB_SETS_SOURCE="explicit"
fi

# === User Playbook + State parsing ===
UP_RAW=$(awk '
  /^\*\*[Uu]ser [Pp]laybook:\*\*/ {
    sub(/^\*\*[Uu]ser [Pp]laybook:\*\*[[:space:]]*/, "")
    print
    exit
  }
' "$PROJECT_STATE")

UPS_RAW=$(awk '
  /^\*\*[Uu]ser [Pp]laybook [Ss]tate:\*\*/ {
    sub(/^\*\*[Uu]ser [Pp]laybook [Ss]tate:\*\*[[:space:]]*/, "")
    print
    exit
  }
' "$PROJECT_STATE")

if [ -n "$UPS_RAW" ]; then
  UP_STATE="$UPS_RAW"
elif [ -z "$UP_RAW" ]; then
  UP_STATE="unset"
elif [ "$UP_RAW" = "(docs-only-no-playbook)" ] || [ "$UP_RAW" = "docs-only-no-playbook" ]; then
  UP_STATE="docs-only-no-playbook"
else
  UP_STATE="set"
fi

if [ "$UP_STATE" = "set" ] && [ -n "$UP_RAW" ]; then
  UP_OUT="$UP_RAW"
else
  UP_OUT="null"
fi

# === Playbook Resolutions parsing ===
# Format: multi-line list under **Playbook Resolutions:** heading
#   - topic1 → set-id-1
#   - topic2 → set-id-2
# H2 fix (v4.1.0): emit topic/set as TAB-separated plain text from awk (no JSON construction
# in awk where backslash/quote escaping is fragile). Pipe to jq -R for safe JSON encoding.
PB_RESOLUTIONS=$(awk -v FS='\t' '
  BEGIN { in_block = 0 }
  /^\*\*[Pp]laybook [Rr]esolutions:\*\*/ { in_block = 1; next }
  in_block && /^\*\*[A-Z]/ { in_block = 0 }
  in_block && /^- / {
    line = $0
    sub(/^- */, "", line)
    if (match(line, / *(→|->|=) */)) {
      topic = substr(line, 1, RSTART-1)
      set = substr(line, RSTART+RLENGTH)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", topic)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", set)
      gsub(/\t/, " ", topic)
      gsub(/\t/, " ", set)
      printf("%s\t%s\n", topic, set)
    }
  }
' "$PROJECT_STATE" | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(split("\t")) | map({topic: .[0], set: .[1]})')

[ -z "$PB_RESOLUTIONS" ] && PB_RESOLUTIONS="[]"

# === Worktree By Default parsing (v3.16.0+; truthy-variant aware in v4.1.0+) ===
WBD_RAW=$(awk '
  /^\*\*[Ww]orktree [Bb]y [Dd]efault:\*\*/ {
    sub(/^\*\*[Ww]orktree [Bb]y [Dd]efault:\*\*[[:space:]]*/, "")
    print
    exit
  }
' "$PROJECT_STATE")
WBD_OUT=$(parse_bool "$WBD_RAW")
# v3.16.0 contract: absent → false (not null) for boolean compatibility with consumers
[ "$WBD_OUT" = "null" ] && WBD_OUT="false"

# === Review Required parsing (v4.1.0+) ===
# Output: "true" | "false" | "null" (absent → null per emit_json; legacy default applied in /complete)
RR_RAW=$(awk '
  /^\*\*[Rr]eview [Rr]equired:\*\*/ {
    sub(/^\*\*[Rr]eview [Rr]equired:\*\*[[:space:]]*/, "")
    print
    exit
  }
' "$PROJECT_STATE")
RR_OUT=$(parse_bool "$RR_RAW")

# === Visual Review parsing (v4.11.0+) ===
# Grammar: **Visual Review:** <state> <relative-path>
#   <state> ∈ {enabled, disabled}; <relative-path> must resolve WITHIN the project.
# Absent line → visualReview: null (feature not set up).
VR_RAW=$(awk '
  /^\*\*[Vv]isual [Rr]eview:\*\*/ {
    sub(/^\*\*[Vv]isual [Rr]eview:\*\*[[:space:]]*/, "")
    print
    exit
  }
' "$PROJECT_STATE")

VR_OUT="null"
if [ -n "$VR_RAW" ]; then
  VR_STATE="${VR_RAW%%[[:space:]]*}"               # first whitespace-delimited token
  VR_REST="${VR_RAW#"$VR_STATE"}"
  VR_PATH="${VR_REST#"${VR_REST%%[![:space:]]*}"}"  # ltrim
  VR_PATH="${VR_PATH%"${VR_PATH##*[![:space:]]}"}"  # rtrim

  case "$(printf '%s' "$VR_STATE" | tr '[:upper:]' '[:lower:]')" in
    enabled)  VR_ENABLED="true" ;;
    disabled) VR_ENABLED="false" ;;
    *)        VR_ENABLED="false"
              add_warning "visual_review_bad_state" "expected enabled|disabled, got: $VR_STATE" ;;
  esac

  if [ -z "$VR_PATH" ]; then
    add_warning "visual_review_no_path" "**Visual Review:** has a state but no registry path"
    VR_OUT=$(jq -nc --argjson e "$VR_ENABLED" '{enabled: $e, registryPath: null}')
  else
    # The registry path MUST be relative (surface-registry-schema.md). An
    # absolute path would survive the realpath prefix check below — joining
    # "$PROJ_REAL/$VR_PATH" with an absolute $VR_PATH string-concatenates to
    # "$PROJ_REAL/etc/passwd" (shell join, not Python os.path.join), which
    # passes the prefix guard while the raw absolute path stays in registryPath.
    # Reject leading-slash and the degenerate ./.. forms up front.
    case "$VR_PATH" in
      /*)
        add_warning "visual_review_path_escape" "registry path must be relative, not absolute: $VR_PATH"
        VR_OUT="null"
        ;;
      . | .. | ./ | ../)
        add_warning "visual_review_path_escape" "registry path is not a file path: $VR_PATH"
        VR_OUT="null"
        ;;
      *)
        # Path-escape guard: the registry path must stay within the project
        # folder. realpath -m resolves `..` without requiring the path to exist.
        PROJ_REAL=$(realpath -m "$PROJECT_DIR" 2>/dev/null || echo "$PROJECT_DIR")
        VR_ABS=$(realpath -m "$PROJ_REAL/$VR_PATH" 2>/dev/null || echo "")
        if [ "$VR_ABS" = "$PROJ_REAL" ]; then
          add_warning "visual_review_path_escape" "registry path resolves to the project folder, not a file: $VR_PATH"
          VR_OUT="null"
        else
          case "${VR_ABS}/" in
            "$PROJ_REAL"/*)
              VR_OUT=$(jq -nc --argjson e "$VR_ENABLED" --arg p "$VR_PATH" \
                '{enabled: $e, registryPath: $p}')
              ;;
            *)
              add_warning "visual_review_path_escape" "registry path escapes the project folder: $VR_PATH"
              VR_OUT="null"
              ;;
          esac
        fi
        ;;
    esac
  fi
fi

# === Frameworks parsing ===
# Comma-separated flat list, same idiom as Playbook Sets.
FRAMEWORKS_RAW=$(awk '
  /^\*\*[Ff]rameworks:\*\*/ {
    sub(/^\*\*[Ff]rameworks:\*\*[[:space:]]*/, "")
    print
    exit
  }
' "$PROJECT_STATE")

if [ -z "$FRAMEWORKS_RAW" ]; then
  FRAMEWORKS_OUT="[]"
else
  FRAMEWORKS_OUT=$(echo "$FRAMEWORKS_RAW" | jq -R -c 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')
  [ -z "$FRAMEWORKS_OUT" ] && FRAMEWORKS_OUT="[]"
fi

# === Local Guides Path parsing ===
# Single trimmed value, same idiom as Code path. No path-escape validation (configured dir name).
LGP_RAW=$(awk '
  /^\*\*[Ll]ocal [Gg]uides [Pp]ath:\*\*/ {
    sub(/^\*\*[Ll]ocal [Gg]uides [Pp]ath:\*\*[[:space:]]*/, "")
    print
    exit
  }
' "$PROJECT_STATE")

if [ -z "$LGP_RAW" ]; then
  LGP_OUT="null"
else
  LGP_OUT="$LGP_RAW"
fi

# === Process Recipes parsing ===
# Format: multi-line list under **Process Recipes:** heading
#   - e2e-setup/nextjs/playwright → source=dev-guides
#   - e2e-setup/symfony/panther → source=local
# Only → and -> are accepted as key/attrs separator (= would collide with attr key=value pairs).
# Source-only records — nothing is pinned. Lenient: any other token on the line
# (e.g. a leftover pinned_sha=... from an older format) is ignored; we parse the
# source and drop the rest so stale files do not break.
# H2 fix rationale: emit key/source as TAB-separated text from awk; build JSON in jq.
PROC_REC_LINES=$(awk '
  BEGIN { in_block = 0 }
  /^\*\*[Pp]rocess [Rr]ecipes:\*\*/ { in_block = 1; next }
  in_block && (/^\*\*[A-Z]/ || /^## /) { in_block = 0 }
  in_block && /^- / {
    line = $0
    sub(/^- */, "", line)
    if (match(line, / *(→|->) */)) {
      key = substr(line, 1, RSTART-1)
      attrs = substr(line, RSTART+RLENGTH)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", attrs)
      gsub(/\t/, " ", key)
      gsub(/\t/, " ", attrs)
      src = ""
      n = split(attrs, pairs, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        if (pairs[i] ~ /^source=/) {
          src = substr(pairs[i], 8)
        }
        # Any other token (e.g. a stale pinned_sha=...) is ignored on purpose.
      }
      printf("%s\t%s\n", key, src)
    }
  }
' "$PROJECT_STATE")

# Validate sources and add warnings (must run before building the JSON array so WARNINGS is up to date)
if [ -n "$PROC_REC_LINES" ]; then
  while IFS=$'\t' read -r rec_key rec_src; do
    [ -z "$rec_key" ] && continue
    case "$rec_src" in
      dev-guides|local|machine-local|research) ;;
      "") add_warning "process_recipe_bad_source" "process_recipes slot '$rec_key' missing source" ;;
      *)  add_warning "process_recipe_bad_source" "expected source dev-guides|local|machine-local|research, got: $rec_src (slot: $rec_key)" ;;
    esac
  done <<< "$PROC_REC_LINES"
fi

if [ -z "$PROC_REC_LINES" ]; then
  PROCESS_RECIPES="[]"
else
  PROCESS_RECIPES=$(echo "$PROC_REC_LINES" | jq -R -s -c '
    split("\n") | map(select(length > 0)) | map(split("\t")) |
    map({
      key: .[0],
      source: (if .[1] == "" then null else .[1] end)
    })')
  [ -z "$PROCESS_RECIPES" ] && PROCESS_RECIPES="[]"
fi

emit_json "$PROJECT_NAME" "$CODE_PATH_OUT" "$PROJECT_DIR" "$WARNINGS" \
  "$PB_SETS_OUT" "$PB_SETS_SOURCE" "$UP_OUT" "$UP_STATE" "$PB_RESOLUTIONS" "$WBD_OUT" "$RR_OUT" \
  "$VR_OUT" "$FRAMEWORKS_OUT" "$LGP_OUT" "$PROCESS_RECIPES"
