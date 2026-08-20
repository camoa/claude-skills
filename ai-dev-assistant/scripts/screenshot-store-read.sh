#!/usr/bin/env bash
# screenshot-store-read.sh — inspect the codePath-native screenshot store.
#
# Reworked for ai-dev-assistant v4.13.0 (Task C). The store moved from the
# memory project's `.screenshots/` to the codePath-native Playwright layout:
#
#   <codePath>/tests/visual/<surface>.spec.ts-snapshots/
#     <surface>-<ordinal>-<projectName>-<platform>.png
#     <surface>-<ordinal>-<projectName>-<platform>.meta.json   ← provenance sidecar
#
# Usage: screenshot-store-read.sh <codePath> [--registry <path>]
#                                            [--legacy-path <memory_project>]
#
#   <codePath>       project root; the store is <codePath>/tests/visual/
#   --registry       optional surface-registry (registry.yml) path. When given,
#                    every snapshot directory found on disk is cross-referenced
#                    against the registry's `surfaces[]`, and every registered
#                    visual_regression surface is cross-referenced against disk.
#                    Without it the reader lists whatever directories exist and
#                    says so via a `registry_not_checked` warning — a snapshot
#                    directory left behind by a removed surface is then
#                    indistinguishable from a registered surface that has not
#                    been baselined yet, which is the whole point of the flag.
#   --legacy-path    optional memory-project folder; when given, the output
#                    carries `legacy_store_present: true` if a v3.13.0
#                    `.screenshots/` directory still exists there. Lets
#                    /validate:all report migration status without a second
#                    reader invocation. The legacy store is NOT scanned.
#
# Telling the three cases apart (only possible with --registry):
#
#   registered, has baselines    registered: true,  orphan: false, viewports[] non-empty
#   registered, no baselines     registered: true,  orphan: false, viewports[] empty
#                                + store warning `surface_without_baselines`
#   unregistered leftover        registered: false, orphan: true
#                                + store warning `orphan_snapshot_dir`
#
# Without --registry both `registered` and `orphan` are null on every component
# and `registry_checked` is false, so a consumer can never mistake "not checked"
# for "checked and clean".
#
# Always emits single-line JSON to stdout. Exit 0 regardless of input
# (warnings surface via the warnings[] array).
#
# Output shape (per references/screenshot-store-schema.md):
#   {
#     "schema_version": "1.0",
#     "project_path": "<codePath>",
#     "store_path": "<codePath>/tests/visual",
#     "store_exists": true|false,
#     "registry_checked": true|false,       # false ⇒ no cross-reference ran
#     "registry_path": "<path>",            # present only with --registry
#     "legacy_store_present": true|false,   # present only with --legacy-path
#     "components": [
#       { "name": "<surface>",
#         "registered": true|false|null,    # null when registry_checked false
#         "orphan": true|false|null,        # null when registry_checked false
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
# Registry cross-reference codes (v5.24.0):
#   registry_not_checked      no --registry, or the registry could not be read
#   orphan_snapshot_dir       snapshot dir whose id is not in surfaces[]
#   surface_without_baselines registered visual_regression surface with no PNG
#
# No writes. No side effects. This script only reads.

set -uo pipefail

# Checksum tool. macOS ships `shasum` and no `sha256sum`; coreutils ships the
# reverse. Calling either one bare means the command substitution returns EMPTY on
# the other platform and an empty hash gets written or compared as though it were
# real. Resolve once, and fail loudly when neither exists rather than recording a
# blank where a digest belongs.
if command -v shasum >/dev/null 2>&1; then
  SUM_CMD=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
  SUM_CMD=(sha256sum)
else
  SUM_CMD=()
fi
sha256_of() {
  [ "${#SUM_CMD[@]}" -gt 0 ] || return 1
  "${SUM_CMD[@]}" "$1" 2>/dev/null | awk '{print $1}'
}


CODE_PATH="${1:?codePath required}"
LEGACY_PATH=""
REGISTRY_PATH=""
shift || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --legacy-path)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then LEGACY_PATH="$2"; shift 2
      else shift; fi
      ;;
    --registry)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then REGISTRY_PATH="$2"; shift 2
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

# ─── surface registry ────────────────────────────────────────────────────────
# Parsed with python3 + PyYAML, the same reader scripts/fm-helpers.sh uses for
# task frontmatter and scripts/baseline-manager.sh uses for the viewport matrix.
# No new dependency, and python3 or PyYAML being absent degrades to the
# no-registry behaviour (announced in a warning) rather than failing.
#
# Emits {"ids":[…all surface ids…],"vr_ids":[…ids gated on visual_regression…]}
# on stdout, or nothing at all when the registry cannot be read.
read_registry_surfaces() {
  [ -f "$REGISTRY_PATH" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -c '
import sys, json
try:
    import yaml
except ImportError:
    sys.exit(1)
try:
    with open(sys.argv[1]) as fh:
        data = yaml.safe_load(fh.read())
except Exception:
    sys.exit(1)
if not isinstance(data, dict):
    sys.exit(1)
surfaces = data.get("surfaces")
if surfaces is None:
    surfaces = []
if not isinstance(surfaces, list):
    sys.exit(1)
ids, vr_ids = [], []
for entry in surfaces:
    if isinstance(entry, dict):
        sid, gates = entry.get("id"), entry.get("gates")
    else:
        sid, gates = entry, None
    if not isinstance(sid, str) or not sid.strip():
        continue
    sid = sid.strip()
    if sid not in ids:
        ids.append(sid)
    # A surface with no gates key predates the flag and is treated as gated on
    # visual_regression; one that lists gates without it (e2e-only) is not.
    gated = gates is None or (isinstance(gates, list) and "visual_regression" in gates)
    if gated and sid not in vr_ids:
        vr_ids.append(sid)
print(json.dumps({"ids": ids, "vr_ids": vr_ids}))
' "$REGISTRY_PATH" 2>/dev/null
}

REGISTRY_CHECKED=false
REGISTRY_JSON=''
REGISTRY_SKIP_REASON=''
if [ -z "$REGISTRY_PATH" ]; then
  REGISTRY_SKIP_REASON="no --registry was supplied, so no snapshot directory was cross-referenced against surfaces[]; an orphan directory cannot be told from a registered surface with no baselines"
else
  REGISTRY_JSON=$(read_registry_surfaces || true)
  if [ -n "$REGISTRY_JSON" ] && printf '%s' "$REGISTRY_JSON" | jq -e 'has("ids") and has("vr_ids")' >/dev/null 2>&1; then
    REGISTRY_CHECKED=true
  else
    REGISTRY_JSON=''
    REGISTRY_SKIP_REASON="registry $REGISTRY_PATH could not be read (missing file, unparseable YAML, or python3/PyYAML unavailable); the cross-reference did not run"
  fi
fi

emit_json() {
  # $1 store_exists, $2 components array, $3 warnings array
  lg_arg="$LEGACY_FLAG_JSON"
  [ -n "$lg_arg" ] || lg_arg=null
  jq -nc --arg pp "$CODE_PATH" --arg sp "$STORE_DIR" \
         --argjson se "$1" --argjson comps "$2" --argjson warns "$3" \
         --argjson rc "$REGISTRY_CHECKED" --arg rp "$REGISTRY_PATH" \
         --argjson lg "$lg_arg" '
    { schema_version: "1.0", project_path: $pp, store_path: $sp,
      store_exists: $se, registry_checked: $rc }
    + (if $rp == "" then {} else {registry_path: $rp} end)
    + (if $lg == null then {} else {legacy_store_present: $lg} end)
    + { components: $comps, warnings: $warns }'
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

# A check that silently did not run is the defect this reader is being hardened
# against, so the absence of the cross-reference is itself a warning.
if [ "$REGISTRY_CHECKED" != "true" ]; then
  STORE_WARNINGS=$(jq -cn --argjson p "$STORE_WARNINGS" --arg d "$REGISTRY_SKIP_REASON" \
    '$p + [{code:"registry_not_checked",detail:$d}]')
fi

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

    # Filename: <stem>[-<ordinal>]-visual-chromium-<viewport>[-<ctx>]-<platform>.png
    #
    # BOTH shapes are real and both are read. The plugin's own starter template
    # NAMES its snapshot (`toHaveScreenshot('<id>.png')`), which suppresses the
    # ordinal entirely — so the no-ordinal form is what a default setup produces,
    # and it is what the migration script writes. Playwright assigns an ordinal
    # only when a capture call passes no name, which is what a recipe-supplied
    # anonymous capture does.
    #
    # An earlier revision hardcoded the ordinal as always present. Against the
    # plugin's own default output it computed ordinal="visual", project="chromium-<vp>",
    # failed its own prefix test, and warned-and-skipped EVERY file — so the reader
    # could not tell fifteen baselines from fourteen, and the "loud failure on a
    # missing baseline" guarantee built on it reported every baseline as absent.
    rest="${png_base#"$stem"-}"
    if [ "$rest" = "$png_base" ]; then
      STORE_WARNINGS=$(jq -cn --argjson p "$STORE_WARNINGS" --arg f "$png_base" \
        '$p + [{code:"meta_schema_mismatch",detail:("baseline \($f) does not begin with its surface stem")}]' )
      continue
    fi

    platform="${rest##*-}"
    body="${rest%-"$platform"}"

    # Strip a leading numeric ordinal when one is present. Only digits — a
    # viewport or context name never leads with a bare integer segment.
    case "$body" in
      [0-9]*-*)
        maybe_ordinal="${body%%-*}"
        case "$maybe_ordinal" in
          *[!0-9]*) ;;                       # not purely numeric — leave it alone
          *) body="${body#"$maybe_ordinal"-}" ;;
        esac
        ;;
    esac

    # The project segment must be visual-chromium-<viewport>[-<ctx>]; anything else
    # is a stray file (a renamed surface's leftover, a hand-placed PNG) — warn +
    # skip, never emit a garbage viewport name.
    if [ "${body#visual-chromium-}" = "$body" ]; then
      STORE_WARNINGS=$(jq -cn --argjson p "$STORE_WARNINGS" --arg f "$png_base" \
        '$p + [{code:"meta_schema_mismatch",detail:("baseline \($f) project segment is not visual-chromium-<viewport>")}]' )
      continue
    fi
    viewport="${body#visual-chromium-}"

    # An authenticated surface carries a trailing -<ctx> segment. Do NOT guess
    # where the viewport ends: the context is knowable from the path, because
    # authed specs are scaffolded under tests/visual/auth/<ctx>/. Folding the
    # context into the viewport name emits a viewport no consumer will match on.
    case "$snap_dir" in
      */tests/visual/auth/*)
        ctx_from_path="${snap_dir#*/tests/visual/auth/}"
        ctx_from_path="${ctx_from_path%%/*}"
        if [ -n "$ctx_from_path" ] && [ "${viewport%-"$ctx_from_path"}" != "$viewport" ]; then
          viewport="${viewport%-"$ctx_from_path"}"
        fi
        ;;
    esac

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
        actual_hash=$(sha256_of "$png_file")
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

  # Cross-reference against the registry. Removing a surface deletes its spec
  # and its PNGs but leaves the now-empty <id>.spec.ts-snapshots/ behind — twelve
  # of them in one observed run. Listing the directory is the only evidence the
  # reader has, and on its own it cannot separate a leftover from a registered
  # surface awaiting its first baseline. The orphan is reported, never dropped:
  # a consumer that wants it gone has to be told it is there.
  registered_json='null'
  orphan_json='null'
  if [ "$REGISTRY_CHECKED" = "true" ]; then
    if printf '%s' "$REGISTRY_JSON" | jq -e --arg s "$stem" '.ids | index($s) != null' >/dev/null 2>&1; then
      registered_json='true'
      orphan_json='false'
    else
      registered_json='false'
      orphan_json='true'
      STORE_WARNINGS=$(jq -c -n --argjson prev "$STORE_WARNINGS" --arg s "$stem" --arg d "$dir_name" \
        '$prev + [{code:"orphan_snapshot_dir",detail:("\($s): \($d)/ has no matching id in the registry surfaces[] — a leftover from a removed surface, not a live one")}]')
    fi
  fi

  COMPONENTS_JSON=$(jq -c -n --argjson cur "$COMPONENTS_JSON" --arg n "$stem" --argjson vps "$viewports_json" \
    --argjson reg "$registered_json" --argjson orph "$orphan_json" \
    '$cur + [{name:$n, registered:$reg, orphan:$orph, viewports:$vps}]')
# Depth 3, not 1. Authenticated surfaces are scaffolded under
# tests/visual/auth/<ctx>/, so their snapshot directories sit two levels deeper.
# At maxdepth 1 the reader never scanned them — an authed baseline was not
# mis-read, it was invisible, and any count built on this reader silently omitted
# every authenticated surface.
done < <(find "$STORE_DIR" -maxdepth 3 -mindepth 1 -type d -name '*.spec.ts-snapshots' 2>/dev/null | sort)

# The other direction: a registered visual_regression surface with no baseline.
# Usually it has no snapshot directory at all, so the disk scan above cannot see
# it, and a pre-check that only counts what the scan found reports nothing wrong.
# Emit it as a component with an empty viewports[] so "registered but never
# baselined" is a state a caller can read, not an absence it has to infer.
if [ "$REGISTRY_CHECKED" = "true" ]; then
  while IFS= read -r reg_id; do
    [ -z "$reg_id" ] && continue
    vp_count=$(printf '%s' "$COMPONENTS_JSON" \
      | jq -r --arg s "$reg_id" '[.[] | select(.name == $s) | (.viewports | length)] | if length == 0 then -1 else add end' 2>/dev/null) || vp_count=''
    [ -n "$vp_count" ] || vp_count='-1'
    if [ "$vp_count" = "-1" ]; then
      COMPONENTS_JSON=$(jq -c -n --argjson cur "$COMPONENTS_JSON" --arg n "$reg_id" \
        '$cur + [{name:$n, registered:true, orphan:false, viewports:[]}]')
    fi
    if [ "$vp_count" = "-1" ] || [ "$vp_count" = "0" ]; then
      STORE_WARNINGS=$(jq -c -n --argjson prev "$STORE_WARNINGS" --arg s "$reg_id" \
        '$prev + [{code:"surface_without_baselines",detail:("\($s): registered with the visual_regression gate but has no baseline PNG in the store")}]')
    fi
  done < <(printf '%s' "$REGISTRY_JSON" | jq -r '.vr_ids[]' 2>/dev/null)
fi

emit_json true "$COMPONENTS_JSON" "$STORE_WARNINGS"
