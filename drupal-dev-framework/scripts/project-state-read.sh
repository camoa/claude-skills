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
#     "warnings": [{"code": "<code>", "detail": "..."}]
#   }
#
# Warning codes:
#   missing_arg               — script called without $1 (defensive; emit + exit 0)
#   folder_missing            — project folder does not exist
#   project_state_md_missing  — project_state.md not in folder
#   code_path_unknown         — project_state.md has no Code path line (first-use case)
#   code_path_missing         — Code path declares a directory that does not exist
#
# codePath sentinels in project_state.md:
#   **Code path:** /abs/path    → non-null string
#   **Code path:** (docs-only)  → null (docs-only project)
#   (absent)                    → null + warning code_path_unknown
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
  jq -nc \
    --arg n "$1" --arg cp "$2" --arg d "$3" \
    --argjson w "$4" \
    --argjson ps "${5:-[]}" --arg pss "${6:-default}" \
    --arg up "${7:-null}" --arg ups "${8:-unset}" \
    --argjson pr "${9:-[]}" \
    --argjson wbd "${10:-false}" \
    --arg rr "${11:-null}" '
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
      warnings: $w
    }'
}

# Resolve framework default playbook sets from plugin.json
PLUGIN_JSON_PATH="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/.claude-plugin/plugin.json"
get_default_playbook_sets() {
  if [ -f "$PLUGIN_JSON_PATH" ]; then
    jq -c '.defaults.playbookSets // []' "$PLUGIN_JSON_PATH" 2>/dev/null || echo "[]"
  else
    echo "[]"
  fi
}

DEFAULT_PB_SETS=$(get_default_playbook_sets)

# H1 fix (v4.1.0): missing arg → defensive emit, do NOT exit 1
if [ -z "$PROJECT_DIR" ]; then
  emit_json "(no project)" "null" "" '[{"code": "missing_arg", "detail": "path to project folder required as $1"}]' \
    "$DEFAULT_PB_SETS" "default" "null" "unset" "[]" "false"
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
    "$DEFAULT_PB_SETS" "default" "null" "unset" "[]" "false"
  exit 0
fi

if [ ! -f "$PROJECT_STATE" ]; then
  emit_json "$FOLDER_NAME" "null" "$PROJECT_DIR" '[{"code": "project_state_md_missing", "detail": "project_state.md not found in folder"}]' \
    "$DEFAULT_PB_SETS" "default" "null" "unset" "[]" "false"
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

emit_json "$PROJECT_NAME" "$CODE_PATH_OUT" "$PROJECT_DIR" "$WARNINGS" \
  "$PB_SETS_OUT" "$PB_SETS_SOURCE" "$UP_OUT" "$UP_STATE" "$PB_RESOLUTIONS" "$WBD_OUT" "$RR_OUT"
