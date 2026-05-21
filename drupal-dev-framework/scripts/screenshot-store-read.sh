#!/usr/bin/env bash
# screenshot-store-read.sh — inspect the codePath-native screenshot store.
#
# Reworked for drupal-dev-framework v4.13.0 (Task C). The store moved from the
# memory project's `.screenshots/` to the codePath-native Playwright layout:
#
#   <codePath>/tests/visual/<surface>.spec.ts-snapshots/
#     <surface>-<ordinal>-<projectName>-<platform>.png
#     <surface>-<ordinal>-<projectName>-<platform>.meta.json   ← provenance sidecar
#
# Usage: screenshot-store-read.sh <codePath> [--legacy-path <memory_project>]
#
#   <codePath>       Drupal project root; the store is <codePath>/tests/visual/
#   --legacy-path    optional memory-project folder; when given, the output
#                    carries `legacy_store_present: true` if a v3.13.0
#                    `.screenshots/` directory still exists there. Lets
#                    /validate:all report migration status without a second
#                    reader invocation. The legacy store is NOT scanned.
#
# Always emits single-line JSON to stdout. Exit 0 regardless of input
# (warnings surface via the warnings[] array).
#
# Output shape (per references/screenshot-store-schema.md §7):
#   {
#     "schema_version": "1.0",
#     "project_path": "<codePath>",
#     "store_path": "<codePath>/tests/visual",
#     "store_exists": true|false,
#     "legacy_store_present": true|false,   # present only with --legacy-path
#     "components": [
#       { "name": "<surface>",
#         "viewports": [
#           { "viewport": "<viewport-name>",
#             "has_current": true,
#             "has_previous": false,        # always false in codePath-native
#             "meta": { ...9-field meta... },
#             "previous_meta": null,        # always null — git holds history
#             "warnings": [ ... ] } ] } ],
#     "warnings": [ ... ]
#   }
#
# Warning codes (unchanged from v3.13.0 — store_missing now means the
# codePath-native tests/visual/ directory is absent):
#   store_missing  component_missing_meta  meta_schema_mismatch
#   hash_mismatch  orphan_meta  error
#
# No writes. No side effects. This script only reads.

set -uo pipefail

CODE_PATH="${1:?codePath required}"
LEGACY_PATH=""
shift || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --legacy-path)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then LEGACY_PATH="$2"; shift 2
      else shift; fi
      ;;
    *) shift ;;
  esac
done

STORE_DIR="$CODE_PATH/tests/visual"

# legacy_store_present is emitted only when --legacy-path is supplied.
LEGACY_FLAG_JSON=""
if [ -n "$LEGACY_PATH" ]; then
  if [ -d "$LEGACY_PATH/.screenshots" ]; then
    LEGACY_FLAG_JSON='true'
  else
    LEGACY_FLAG_JSON='false'
  fi
fi

emit_json() {
  # $1 store_exists, $2 components array, $3 warnings array
  if [ -n "$LEGACY_FLAG_JSON" ]; then
    jq -nc --arg pp "$CODE_PATH" --arg sp "$STORE_DIR" \
           --argjson se "$1" --argjson comps "$2" --argjson warns "$3" \
           --argjson lg "$LEGACY_FLAG_JSON" '
      { schema_version: "1.0", project_path: $pp, store_path: $sp,
        store_exists: $se, legacy_store_present: $lg,
        components: $comps, warnings: $warns }'
  else
    jq -nc --arg pp "$CODE_PATH" --arg sp "$STORE_DIR" \
           --argjson se "$1" --argjson comps "$2" --argjson warns "$3" '
      { schema_version: "1.0", project_path: $pp, store_path: $sp,
        store_exists: $se, components: $comps, warnings: $warns }'
  fi
}

if [ ! -d "$CODE_PATH" ]; then
  emit_json false '[]' '[{"code":"error","detail":"codePath does not exist"}]'
  exit 0
fi

if [ ! -d "$STORE_DIR" ]; then
  emit_json false '[]' '[{"code":"store_missing","detail":"tests/visual/ does not exist; run /setup-visual-regression"}]'
  exit 0
fi

STORE_WARNINGS='[]'
COMPONENTS_JSON='[]'

# One *.spec.ts-snapshots/ directory per surface.
while IFS= read -r snap_dir; do
  [ -z "$snap_dir" ] && continue
  dir_name=$(basename "$snap_dir")
  # Strip the trailing ".spec.ts-snapshots" to get the surface stem.
  stem="${dir_name%.spec.ts-snapshots}"
  [ "$stem" = "$dir_name" ] && continue   # not a snapshot dir
  viewports_json='[]'

  while IFS= read -r png_file; do
    [ -z "$png_file" ] && continue
    png_base=$(basename "$png_file" .png)

    # Filename: <stem>-<ordinal>-<projectName>-<platform>.png
    # We know <stem> from the directory name, so strip it deterministically.
    rest="${png_base#"$stem"-}"
    if [ "$rest" = "$png_base" ]; then
      STORE_WARNINGS=$(jq -cn --argjson p "$STORE_WARNINGS" --arg f "$png_base" \
        '$p + [{code:"meta_schema_mismatch",detail:("baseline \($f) does not match <stem>-<ordinal>-<project>-<platform>")}]' )
      continue
    fi
    ordinal="${rest%%-*}"
    platform="${rest##*-}"
    project="${rest#"$ordinal"-}"
    project="${project%-"$platform"}"
    # The project segment must be visual-chromium-<viewport>; anything else is a
    # stray file (a renamed surface's leftover, a hand-placed PNG) — warn + skip,
    # never emit a garbage viewport name.
    if [ "${project#visual-chromium-}" = "$project" ]; then
      STORE_WARNINGS=$(jq -cn --argjson p "$STORE_WARNINGS" --arg f "$png_base" \
        '$p + [{code:"meta_schema_mismatch",detail:("baseline \($f) project segment is not visual-chromium-<viewport>")}]' )
      continue
    fi
    viewport="${project#visual-chromium-}"

    meta_file="$snap_dir/$png_base.meta.json"
    vp_warnings='[]'
    meta_obj='null'

    if [ ! -f "$meta_file" ]; then
      vp_warnings='[{"code":"component_missing_meta","detail":"png present without .meta.json sibling"}]'
    else
      meta_raw=$(cat "$meta_file" 2>/dev/null)
      if ! meta_obj=$(echo "$meta_raw" | jq -c . 2>/dev/null); then
        vp_warnings='[{"code":"meta_schema_mismatch","detail":".meta.json is not valid JSON"}]'
        meta_obj='null'
      else
        req_ok=$(echo "$meta_obj" | jq -r '
          (has("schema_version") and has("role") and has("viewport")
           and has("captured_at") and has("sha256") and has("originating_task")
           and has("captured_by") and has("prior_hash") and has("source"))' 2>/dev/null)
        if [ "$req_ok" != "true" ]; then
          vp_warnings=$(jq -c -n --argjson prev "$vp_warnings" \
            '$prev + [{code:"meta_schema_mismatch",detail:"missing one or more required v1.0 fields"}]')
        fi
        actual_hash=$(sha256sum "$png_file" 2>/dev/null | awk '{print $1}')
        declared_hash=$(echo "$meta_obj" | jq -r '.sha256 // empty' 2>/dev/null)
        if [ -n "$actual_hash" ] && [ -n "$declared_hash" ] && [ "$actual_hash" != "$declared_hash" ]; then
          vp_warnings=$(jq -c -n --argjson prev "$vp_warnings" --arg a "$actual_hash" --arg d "$declared_hash" \
            '$prev + [{code:"hash_mismatch",detail:("meta.sha256=\($d) does not match actual=\($a)")}]')
        fi
      fi
    fi

    viewports_json=$(jq -c -n --argjson cur "$viewports_json" \
      --arg vp "$viewport" --argjson meta "$meta_obj" --argjson vw "$vp_warnings" '
      $cur + [{
        viewport: $vp,
        has_current: true,
        has_previous: false,
        meta: $meta,
        previous_meta: null,
        warnings: $vw
      }]')
  done < <(find "$snap_dir" -maxdepth 1 -type f -name '*.png' 2>/dev/null | sort)

  # Orphan .meta.json files (meta without a sibling PNG).
  while IFS= read -r meta_file; do
    [ -z "$meta_file" ] && continue
    meta_base=$(basename "$meta_file" .meta.json)
    if [ ! -f "$snap_dir/$meta_base.png" ]; then
      STORE_WARNINGS=$(jq -c -n --argjson prev "$STORE_WARNINGS" --arg s "$stem" --arg m "$meta_base" \
        '$prev + [{code:"orphan_meta",detail:("\($s): \($m).meta.json exists without PNG sibling")}]')
    fi
  done < <(find "$snap_dir" -maxdepth 1 -type f -name '*.meta.json' 2>/dev/null | sort)

  COMPONENTS_JSON=$(jq -c -n --argjson cur "$COMPONENTS_JSON" --arg n "$stem" --argjson vps "$viewports_json" \
    '$cur + [{name:$n, viewports:$vps}]')
done < <(find "$STORE_DIR" -maxdepth 1 -mindepth 1 -type d -name '*.spec.ts-snapshots' 2>/dev/null | sort)

emit_json true "$COMPONENTS_JSON" "$STORE_WARNINGS"
