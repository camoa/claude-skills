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
#     "warnings": [{"code": "<code>", "detail": "..."}]
#   }
#
# Warning codes:
#   folder_missing            — project folder does not exist
#   project_state_md_missing  — project_state.md not in folder
#   code_path_unknown         — project_state.md has no Code path line (first-use case)
#   code_path_missing         — Code path declares a directory that does not exist
#   malformed_header          — metadata block could not be parsed
#
# codePath sentinels in project_state.md:
#   **Code path:** /abs/path    → non-null string
#   **Code path:** (docs-only)  → null (docs-only project)
#   (absent)                    → null + warning code_path_unknown
#
# No writes. No side effects. This script only reads.

set -uo pipefail

PROJECT_DIR="${1:?path to project folder required}"
FOLDER_NAME=$(basename "$PROJECT_DIR")
PROJECT_STATE="$PROJECT_DIR/project_state.md"

emit_json() {
  # $1 = project_name, $2 = codePath (string "null" literal for null), $3 = folder, $4 = warnings JSON array
  jq -nc --arg n "$1" --arg cp "$2" --arg d "$3" --argjson w "$4" '
    {
      project_name: $n,
      codePath: (if $cp == "null" then null else $cp end),
      folder: $d,
      warnings: $w
    }'
}

if [ ! -d "$PROJECT_DIR" ]; then
  emit_json "$FOLDER_NAME" "null" "$PROJECT_DIR" '[{"code": "folder_missing", "detail": "project folder does not exist"}]'
  exit 0
fi

if [ ! -f "$PROJECT_STATE" ]; then
  emit_json "$FOLDER_NAME" "null" "$PROJECT_DIR" '[{"code": "project_state_md_missing", "detail": "project_state.md not found in folder"}]'
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
  BEGIN { IGNORECASE=1 }
  /^\*\*Code path:\*\*/ {
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
  # Normalize: expand ~, realpath -m (doesn't require existence)
  CODE_PATH_EXPANDED=$(eval echo "$CODE_PATH_RAW")
  CODE_PATH_NORM=$(realpath -m "$CODE_PATH_EXPANDED" 2>/dev/null || echo "$CODE_PATH_EXPANDED")
  if [ ! -d "$CODE_PATH_NORM" ]; then
    WARNINGS=$(jq -c -n --arg p "$CODE_PATH_NORM" '[{code: "code_path_missing", detail: ("directory does not exist: " + $p)}]')
  fi
  CODE_PATH_OUT="$CODE_PATH_NORM"
fi

emit_json "$PROJECT_NAME" "$CODE_PATH_OUT" "$PROJECT_DIR" "$WARNINGS"
