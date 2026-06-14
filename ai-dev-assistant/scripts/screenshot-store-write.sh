#!/usr/bin/env bash
# screenshot-store-write.sh — write baselines + parity references with rotation.
#
# Usage:
#   screenshot-store-write.sh write-baseline <project> <component> <viewport> <source.png> <captured_by> <originating_task>
#   screenshot-store-write.sh write-parity-reference <project> <component> <viewport> <source.png> <captured_by> <originating_task> <source_type> <source_uri>
#   screenshot-store-write.sh write-baseline-codepath <codePath> <surface-id> <png-filename> <viewport-name> <captured_by> <originating_task>
#
# write-baseline-codepath (v4.13.0, Task C — codePath-native layout):
#   Writes ONLY the provenance .meta.json sidecar next to a baseline PNG that
#   Playwright has already written (via `npx playwright test --update-snapshots`).
#   The PNG must already exist at
#   <codePath>/tests/visual/<surface-id>.spec.ts-snapshots/<png-filename>.
#   No rotation, no .previous tier — git holds the baseline history.
#
# Performs the 6-step rotation from architecture:
#   1. Compute sha256 of existing <viewport>.png (becomes prior_hash)
#   2. Delete existing .previous.png + .previous.meta.json unconditionally
#   3. Rename current .png → .previous.png; rename meta similarly
#   4. Copy source.png to <viewport>.png
#   5. Write new meta with sha256, prior_hash, captured_at, captured_by, originating_task, role, source
#   6. Verify new sha256 matches meta; on mismatch, rollback via reverse-rename + emit warning
#
# First-baseline special case: no predecessor → skip steps 1-3; new meta has prior_hash: null.
#
# Emits single-line JSON to stdout describing the operation result. Exit codes:
#   0 — success
#   1 — rollback performed (warning in JSON)
#   2 — arg validation failure
#   3 — IO error pre-rotation (safe; no partial state)
#
# captured_by values (from architecture):
#   playwright-mcp | claude-in-chrome | figma-export | html-render | user-upload
#
# source_type values (parity-reference only):
#   figma | html | image | url

set -uo pipefail

MODE="${1:-}"

usage() {
  cat >&2 <<'EOF'
Usage:
  screenshot-store-write.sh write-baseline <project> <component> <viewport> <source.png> <captured_by> <originating_task>
  screenshot-store-write.sh write-parity-reference <project> <component> <viewport> <source.png> <captured_by> <originating_task> <source_type> <source_uri>
EOF
}

emit_result() {
  # $1 = status ("ok"|"rollback"|"error"), $2 = warnings JSON array, $3 = summary object
  jq -nc --arg st "$1" --argjson w "$2" --argjson s "$3" '{status:$st, warnings:$w, summary:$s}'
}

# ─── write-baseline-codepath (v4.13.0 — codePath-native sidecar) ─────────────
# Handled up front: a distinct flow from the rotating .screenshots/ writer.
if [ "$MODE" = "write-baseline-codepath" ]; then
  if [ $# -ne 7 ]; then usage; exit 2; fi
  CODE_PATH="$2"; SURFACE_ID="$3"; PNG_NAME="$4"; VP_NAME="$5"; CB="$6"; OT="$7"

  if [ ! -d "$CODE_PATH" ]; then
    emit_result "error" '[{"code":"codepath_missing","detail":"codePath does not exist"}]' '{}'
    exit 3
  fi
  if ! echo "$SURFACE_ID" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
    emit_result "error" '[{"code":"invalid_surface_id","detail":"surface id must match ^[a-z0-9][a-z0-9-]*$"}]' '{}'
    exit 2
  fi
  if ! echo "$VP_NAME" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
    emit_result "error" '[{"code":"invalid_viewport","detail":"viewport name must match ^[a-z0-9][a-z0-9-]*$"}]' '{}'
    exit 2
  fi
  case "$PNG_NAME" in
    *.png) ;;
    *) emit_result "error" '[{"code":"invalid_png_name","detail":"png-filename must end in .png"}]' '{}'; exit 2 ;;
  esac
  case "$PNG_NAME" in
    */*|..*) emit_result "error" '[{"code":"invalid_png_name","detail":"png-filename must be a bare filename"}]' '{}'; exit 2 ;;
  esac
  # captured_by enum — v4.13.0 adds lullabot-playwright + migrated-from-screenshots-store.
  case "$CB" in
    playwright-mcp|claude-in-chrome|figma-export|html-render|user-upload|lullabot-playwright|migrated-from-screenshots-store) ;;
    *)
      emit_result "error" '[{"code":"invalid_captured_by","detail":"captured_by not in the v4.13.0 enum"}]' '{}'
      exit 2 ;;
  esac

  SNAP_DIR="$CODE_PATH/tests/visual/$SURFACE_ID.spec.ts-snapshots"
  PNG_PATH="$SNAP_DIR/$PNG_NAME"
  if [ ! -f "$PNG_PATH" ]; then
    emit_result "error" '[{"code":"png_missing","detail":"baseline PNG not found — Playwright must write it first via --update-snapshots"}]' '{}'
    exit 3
  fi

  META_PATH="$SNAP_DIR/${PNG_NAME%.png}.meta.json"
  PRIOR_HASH_JSON='null'
  if [ -f "$META_PATH" ]; then
    EXISTING=$(jq -r '.sha256 // empty' "$META_PATH" 2>/dev/null)
    [ -n "$EXISTING" ] && PRIOR_HASH_JSON=$(jq -nc --arg h "$EXISTING" '$h')
  fi

  NEW_HASH=$(sha256sum "$PNG_PATH" | awk '{print $1}')
  NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  META_JSON=$(jq -nc \
    --arg vp "$VP_NAME" --arg ca "$NOW_ISO" --arg sha "$NEW_HASH" \
    --arg ot "$OT" --arg cb "$CB" --argjson ph "$PRIOR_HASH_JSON" '
    { schema_version: "1.0", role: "baseline", viewport: $vp,
      captured_at: $ca, sha256: $sha, originating_task: $ot,
      captured_by: $cb, prior_hash: $ph, source: null }')

  if ! echo "$META_JSON" > "$META_PATH" 2>/dev/null; then
    emit_result "error" '[{"code":"meta_write_failed"}]' '{}'
    exit 3
  fi

  SUMMARY=$(jq -nc --arg s "$SURFACE_ID" --arg vp "$VP_NAME" \
    --arg png "$PNG_PATH" --arg meta "$META_PATH" --arg sha "$NEW_HASH" '
    { surface_id: $s, viewport: $vp, png_path: $png,
      meta_path: $meta, sha256: $sha }')
  emit_result "ok" '[]' "$SUMMARY"
  exit 0
fi

case "$MODE" in
  write-baseline)
    if [ $# -ne 7 ]; then usage; exit 2; fi
    PROJECT="$2"; COMPONENT="$3"; VIEWPORT="$4"; SOURCE="$5"; CAPTURED_BY="$6"; ORIGIN_TASK="$7"
    ROLE="baseline"
    SOURCE_TYPE=""
    SOURCE_URI=""
    ;;
  write-parity-reference)
    if [ $# -ne 9 ]; then usage; exit 2; fi
    PROJECT="$2"; COMPONENT="$3"; VIEWPORT="$4"; SOURCE="$5"; CAPTURED_BY="$6"; ORIGIN_TASK="$7"
    SOURCE_TYPE="$8"; SOURCE_URI="$9"
    ROLE="parity_reference"
    ;;
  *)
    usage; exit 2 ;;
esac

# Validate inputs
if [ ! -f "$SOURCE" ]; then
  emit_result "error" '[{"code":"source_missing","detail":"source png does not exist"}]' '{}'
  exit 3
fi
if [ ! -d "$PROJECT" ]; then
  emit_result "error" '[{"code":"project_missing","detail":"project folder does not exist"}]' '{}'
  exit 3
fi

# Component name sanity (kebab-case; caller should sanitize, but check)
if ! echo "$COMPONENT" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
  emit_result "error" '[{"code":"invalid_component","detail":"component name must match ^[a-z0-9][a-z0-9-]*$"}]' '{}'
  exit 2
fi
# Viewport format
if ! echo "$VIEWPORT" | grep -qE '^[0-9]+x[0-9]+$'; then
  emit_result "error" '[{"code":"invalid_viewport","detail":"viewport must match ^[0-9]+x[0-9]+$"}]' '{}'
  exit 2
fi
# captured_by enum
case "$CAPTURED_BY" in
  playwright-mcp|claude-in-chrome|figma-export|html-render|user-upload) ;;
  *)
    emit_result "error" '[{"code":"invalid_captured_by","detail":"captured_by must be one of: playwright-mcp, claude-in-chrome, figma-export, html-render, user-upload"}]' '{}'
    exit 2 ;;
esac
# source_type enum (parity-reference only)
if [ "$ROLE" = "parity_reference" ]; then
  case "$SOURCE_TYPE" in
    figma|html|image|url) ;;
    *)
      emit_result "error" '[{"code":"invalid_source_type","detail":"source_type must be one of: figma, html, image, url"}]' '{}'
      exit 2 ;;
  esac
fi

STORE="$PROJECT/.screenshots"
COMP_DIR="$STORE/$COMPONENT"
CURRENT_PNG="$COMP_DIR/$VIEWPORT.png"
CURRENT_META="$COMP_DIR/$VIEWPORT.meta.json"
PREV_PNG="$COMP_DIR/$VIEWPORT.previous.png"
PREV_META="$COMP_DIR/$VIEWPORT.previous.meta.json"

mkdir -p "$COMP_DIR" || { emit_result "error" '[{"code":"mkdir_failed"}]' '{}'; exit 3; }

IS_FIRST_BASELINE="true"
PRIOR_HASH="null"

# STEP 1 — compute prior_hash if predecessor exists
if [ -f "$CURRENT_PNG" ]; then
  IS_FIRST_BASELINE="false"
  PRIOR_HASH=$(sha256sum "$CURRENT_PNG" | awk '{print $1}')
fi

# STEPS 2-3 — rotation (only if predecessor exists)
if [ "$IS_FIRST_BASELINE" = "false" ]; then
  # Step 2: delete existing .previous.* unconditionally
  rm -f "$PREV_PNG" "$PREV_META"
  # Step 3: rename current → previous
  mv "$CURRENT_PNG" "$PREV_PNG" || { emit_result "error" '[{"code":"rotation_mv_failed","detail":"could not rename current png to previous"}]' '{}'; exit 3; }
  if [ -f "$CURRENT_META" ]; then
    mv "$CURRENT_META" "$PREV_META" || {
      # Rollback: move .previous.png back
      mv "$PREV_PNG" "$CURRENT_PNG"
      emit_result "rollback" '[{"code":"rotation_meta_mv_failed"}]' '{}'
      exit 1
    }
  fi
fi

# STEP 4 — copy source to current
cp "$SOURCE" "$CURRENT_PNG" || {
  # Rollback: restore previous as current if we rotated
  if [ "$IS_FIRST_BASELINE" = "false" ]; then
    mv "$PREV_PNG" "$CURRENT_PNG"
    [ -f "$PREV_META" ] && mv "$PREV_META" "$CURRENT_META"
  fi
  emit_result "rollback" '[{"code":"copy_failed","detail":"source copy failed; rotation rolled back"}]' '{}'
  exit 1
}

# STEP 5 — write new meta
NEW_HASH=$(sha256sum "$CURRENT_PNG" | awk '{print $1}')
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ "$ROLE" = "parity_reference" ]; then
  SOURCE_JSON=$(jq -nc --arg t "$SOURCE_TYPE" --arg u "$SOURCE_URI" '{type:$t, uri:$u}')
else
  SOURCE_JSON='null'
fi

if [ "$PRIOR_HASH" = "null" ]; then
  PRIOR_HASH_JSON='null'
else
  PRIOR_HASH_JSON=$(jq -nc --arg h "$PRIOR_HASH" '$h')
fi

META_JSON=$(jq -nc \
  --arg role "$ROLE" --arg vp "$VIEWPORT" --arg ca "$NOW_ISO" \
  --arg sha "$NEW_HASH" --arg ot "$ORIGIN_TASK" --arg cb "$CAPTURED_BY" \
  --argjson ph "$PRIOR_HASH_JSON" --argjson src "$SOURCE_JSON" '
  {
    schema_version: "1.0",
    role: $role,
    viewport: $vp,
    captured_at: $ca,
    sha256: $sha,
    originating_task: $ot,
    captured_by: $cb,
    prior_hash: $ph,
    source: $src
  }')

echo "$META_JSON" > "$CURRENT_META" || {
  # Rollback: remove the new current, restore previous
  rm -f "$CURRENT_PNG"
  if [ "$IS_FIRST_BASELINE" = "false" ]; then
    mv "$PREV_PNG" "$CURRENT_PNG"
    [ -f "$PREV_META" ] && mv "$PREV_META" "$CURRENT_META"
  fi
  emit_result "rollback" '[{"code":"meta_write_failed"}]' '{}'
  exit 1
}

# STEP 6 — verify integrity
VERIFY_HASH=$(sha256sum "$CURRENT_PNG" | awk '{print $1}')
if [ "$VERIFY_HASH" != "$NEW_HASH" ]; then
  # Extremely unlikely — would mean mid-write corruption. Rollback.
  rm -f "$CURRENT_PNG" "$CURRENT_META"
  if [ "$IS_FIRST_BASELINE" = "false" ]; then
    mv "$PREV_PNG" "$CURRENT_PNG"
    [ -f "$PREV_META" ] && mv "$PREV_META" "$CURRENT_META"
  fi
  emit_result "rollback" '[{"code":"hash_verification_failed","detail":"new PNG hash does not match meta after write; rotation rolled back"}]' '{}'
  exit 1
fi

# Success
SUMMARY=$(jq -nc --arg comp "$COMPONENT" --arg vp "$VIEWPORT" --arg role "$ROLE" \
  --arg cur "$CURRENT_PNG" --arg prev "$PREV_PNG" --argjson first "$([ "$IS_FIRST_BASELINE" = "true" ] && echo true || echo false)" \
  --arg sha "$NEW_HASH" '
  {
    component: $comp,
    viewport: $vp,
    role: $role,
    current_path: $cur,
    previous_path: (if $first then null else $prev end),
    first_baseline: $first,
    new_sha256: $sha
  }')

emit_result "ok" '[]' "$SUMMARY"
exit 0
