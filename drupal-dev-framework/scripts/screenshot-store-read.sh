#!/usr/bin/env bash
# screenshot-store-read.sh — inspect the screenshot store for a project.
#
# Usage: screenshot-store-read.sh <project_folder>
#
# Always emits single-line JSON to stdout. Exit 0 regardless of input
# (warnings surface via the warnings[] array). Mirrors the defensive posture
# of alignment-read.sh and project-state-read.sh.
#
# Output shape (per references/screenshot-store-schema.md v1.0):
#   {
#     "schema_version": "1.0",
#     "project_path": "<abs path>",
#     "store_path": "<abs path to .screenshots/>",
#     "store_exists": true|false,
#     "components": [
#       {
#         "name": "<component>",
#         "viewports": [
#           {
#             "viewport": "1920x1080",
#             "has_current": true|false,
#             "has_previous": true|false,
#             "meta": { ... 9-field meta.json content ... },
#             "previous_meta": { ... | null },
#             "warnings": [ ... per-viewport warnings ... ]
#           }
#         ]
#       }
#     ],
#     "warnings": [ ... store-level warnings ... ]
#   }
#
# Warning codes (per architecture §4.5):
#   store_missing            — .screenshots/ folder does not exist
#   component_missing_meta   — <viewport>.png exists but no .meta.json sibling
#   meta_schema_mismatch     — .meta.json doesn't have expected v1.0 fields
#   hash_mismatch            — .meta.json sha256 does not match the actual PNG
#   orphan_meta              — <viewport>.meta.json exists but no PNG sibling
#   error                    — unrecoverable read failure (permissions, IO)
#
# No writes. No side effects. This script only reads.

set -uo pipefail

PROJECT_DIR="${1:?path to project folder required}"
STORE_DIR="$PROJECT_DIR/.screenshots"

emit_json() {
  # $1 = store_exists (true/false literal), $2 = components JSON array, $3 = warnings JSON array
  jq -nc --arg pp "$PROJECT_DIR" --arg sp "$STORE_DIR" \
         --argjson se "$1" --argjson comps "$2" --argjson warns "$3" '
    {
      schema_version: "1.0",
      project_path: $pp,
      store_path: $sp,
      store_exists: $se,
      components: $comps,
      warnings: $warns
    }'
}

# Short-circuit: project folder missing (caller error, but stay defensive)
if [ ! -d "$PROJECT_DIR" ]; then
  emit_json false '[]' '[{"code":"error","detail":"project folder does not exist"}]'
  exit 0
fi

# Short-circuit: store doesn't exist (normal for projects that never ran visual tests)
if [ ! -d "$STORE_DIR" ]; then
  emit_json false '[]' '[{"code":"store_missing","detail":".screenshots/ does not exist; no visual baselines yet"}]'
  exit 0
fi

# Gather per-viewport data
# For each component directory under .screenshots/:
#   - iterate current .png files (non-.previous, non-.candidate)
#   - check for sibling .meta.json, .previous.png, .previous.meta.json
#   - read metas, verify hashes, emit per-viewport record

STORE_WARNINGS='[]'
COMPONENTS_JSON='[]'

# Process component directories
while IFS= read -r comp_dir; do
  [ -z "$comp_dir" ] && continue
  comp_name=$(basename "$comp_dir")
  viewports_json='[]'

  # Find all current PNGs (exclude .previous.png, .candidate.png)
  while IFS= read -r png_file; do
    [ -z "$png_file" ] && continue
    png_base=$(basename "$png_file" .png)

    # Skip siblings-of-current
    case "$png_base" in
      *.previous|*.candidate) continue ;;
    esac

    viewport="$png_base"
    meta_file="$comp_dir/$viewport.meta.json"
    prev_png="$comp_dir/$viewport.previous.png"
    prev_meta="$comp_dir/$viewport.previous.meta.json"

    vp_warnings='[]'
    meta_obj='null'
    prev_meta_obj='null'
    has_current='true'
    has_previous='false'

    # Read meta
    if [ ! -f "$meta_file" ]; then
      vp_warnings=$(jq -c -n '[{code:"component_missing_meta",detail:"png present without .meta.json sibling"}]')
    else
      meta_raw=$(cat "$meta_file" 2>/dev/null)
      if ! meta_obj=$(echo "$meta_raw" | jq -c . 2>/dev/null); then
        vp_warnings=$(jq -c -n '[{code:"meta_schema_mismatch",detail:".meta.json is not valid JSON"}]')
        meta_obj='null'
      else
        # Schema sanity check — required v1.0 fields
        req_ok=$(echo "$meta_obj" | jq -r '
          (has("schema_version") and has("role") and has("viewport")
           and has("captured_at") and has("sha256") and has("originating_task")
           and has("captured_by") and has("prior_hash") and has("source"))
        ' 2>/dev/null)
        if [ "$req_ok" != "true" ]; then
          vp_warnings=$(jq -c -n --argjson prev "$vp_warnings" '$prev + [{code:"meta_schema_mismatch",detail:"missing one or more required v1.0 fields"}]')
        fi

        # Hash verification — compute actual, compare to meta
        actual_hash=$(sha256sum "$png_file" 2>/dev/null | awk '{print $1}')
        declared_hash=$(echo "$meta_obj" | jq -r '.sha256 // empty' 2>/dev/null)
        if [ -n "$actual_hash" ] && [ -n "$declared_hash" ] && [ "$actual_hash" != "$declared_hash" ]; then
          vp_warnings=$(jq -c -n --argjson prev "$vp_warnings" --arg a "$actual_hash" --arg d "$declared_hash" \
            '$prev + [{code:"hash_mismatch",detail:("meta.sha256=\($d) does not match actual=\($a)")}]')
        fi
      fi
    fi

    # Previous sibling
    if [ -f "$prev_png" ]; then
      has_previous='true'
      if [ -f "$prev_meta" ]; then
        prev_meta_raw=$(cat "$prev_meta" 2>/dev/null)
        prev_meta_obj=$(echo "$prev_meta_raw" | jq -c . 2>/dev/null || echo 'null')
      fi
    fi

    # Append to viewports
    viewports_json=$(jq -c -n --argjson cur "$viewports_json" \
      --arg vp "$viewport" --argjson hc "$has_current" --argjson hp "$has_previous" \
      --argjson meta "$meta_obj" --argjson pmeta "$prev_meta_obj" --argjson vw "$vp_warnings" '
      $cur + [{
        viewport: $vp,
        has_current: $hc,
        has_previous: $hp,
        meta: $meta,
        previous_meta: $pmeta,
        warnings: $vw
      }]')
  done < <(find "$comp_dir" -maxdepth 1 -type f -name '*.png' 2>/dev/null | sort)

  # Also check for orphan .meta.json files (meta without PNG)
  while IFS= read -r meta_file; do
    [ -z "$meta_file" ] && continue
    meta_base=$(basename "$meta_file" .meta.json)
    # Skip .previous + .candidate metas; only check current-tier orphans
    case "$meta_base" in
      *.previous|*.candidate) continue ;;
    esac
    if [ ! -f "$comp_dir/$meta_base.png" ]; then
      STORE_WARNINGS=$(jq -c -n --argjson prev "$STORE_WARNINGS" --arg c "$comp_name" --arg v "$meta_base" \
        '$prev + [{code:"orphan_meta",detail:("\($c)/\($v).meta.json exists without PNG sibling")}]')
    fi
  done < <(find "$comp_dir" -maxdepth 1 -type f -name '*.meta.json' 2>/dev/null | sort)

  COMPONENTS_JSON=$(jq -c -n --argjson cur "$COMPONENTS_JSON" --arg n "$comp_name" --argjson vps "$viewports_json" \
    '$cur + [{name:$n, viewports:$vps}]')

done < <(find "$STORE_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

emit_json true "$COMPONENTS_JSON" "$STORE_WARNINGS"
