#!/usr/bin/env bash
# wo-oracle-check.sh — Deterministic oracle tamper-detection kernel.
#
# Scans a WO diff (--name-status format) against the oracle watch-table and emits a JSON verdict.
# Mirrors the shape of wo-risk-classify.sh: shebang, set -euo pipefail, positional WO-file arg +
# --diff-from flag, safe frontmatter read (never eval/source), all JSON via jq, verdict on stdout.
#
# Usage:
#   wo-oracle-check.sh <wo-file> --diff-from <name-status-file>
#
#   <wo-file>           positional; oracle_update.classes extracted safely via awk (no eval).
#   --diff-from         file holding `git diff --name-status` output:
#                       TAB-separated lines "STATUS\tpath"; rename "R###\told\tnew" → treat new as M.
#
# Stdout JSON:
#   { "schema_version": "1.0",
#     "tamper_detected": <bool>,
#     "signals": [ { "type": <str>, "path": <str>, "change": "A|M|D",
#                    "oracle_class": <str>, "severity": "halt|flag",
#                    "allowed_by_scope": <bool> } ],
#     "halt_reason": "oracle_tamper" | null }
#
# Exit: 0 on well-formed run (verdict in JSON). Exit 2 on bad args / unreadable inputs.
#
# Watch-table:
#   baseline_write    tests/visual/*.spec.ts-snapshots/{*.png,*.meta.json}   A,M  baseline           halt
#   vr_spec_delete    tests/visual/*.spec.ts                                  D    test-delete        halt
#   test_delete       tests/**/*Test.php                                      D    test-delete        halt
#                     tests/e2e/**/*.spec.ts                                  D    test-delete        halt
#                     tests/atk/**/*.spec.ts                                  D    test-delete        halt
#   phpstan_baseline  phpstan-baseline.neon                                  A,M  phpstan-baseline   halt
#   phpstan_config    phpstan.neon  phpstan.neon.dist                         M    phpstan-baseline   flag
#   registry_shrink   .visual-review/registry.yml                             M    baseline           flag
#   coverage_threshold jest.config.*  phpunit.xml  phpunit.xml.dist           M    coverage-threshold flag

set -euo pipefail

# --- arg parsing -------------------------------------------------------------
WO_FILE=""
DIFF_FROM=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --diff-from) DIFF_FROM="${2:-}"; shift 2 || shift ;;
    --*)         shift ;;
    *)
      if [ -z "$WO_FILE" ]; then
        WO_FILE="$1"
      fi
      shift
      ;;
  esac
done

# --- validate inputs (exit 2 on bad args / unreadable files) ----------------
if [ -z "$WO_FILE" ] || [ ! -f "$WO_FILE" ]; then
  printf 'wo-oracle-check: wo-file missing or unreadable: %s\n' "${WO_FILE:-<none>}" >&2
  exit 2
fi
if [ -z "$DIFF_FROM" ] || [ ! -f "$DIFF_FROM" ]; then
  printf 'wo-oracle-check: --diff-from file missing or unreadable: %s\n' "${DIFF_FROM:-<none>}" >&2
  exit 2
fi

# --- safe oracle_update parser (never eval/source the WO file) ---------------
# Reads oracle_update.classes from the WO's YAML frontmatter. Output: comma-separated
# class names (e.g. "baseline,phpstan-baseline"), or empty string when absent.
#
# Robustness requirements (security-critical — a parse miss either false-HALTs legit
# work OR fail-opens a tamper bypass):
#   L1  honor oracle_update ONLY inside a properly TERMINATED `---`…`---` frontmatter
#       block — a file with no closing `---` => NO frontmatter => NO exemption (never
#       fail-open by reading body prose).
#   M2  strip quotes (both " and ') from class names.
#   M3  parse BOTH the inline flow list (`classes: [a, b]`) AND the block-style YAML
#       list (`classes:` then indented `- a` / `- b` lines).
#   (d) ignore commented / body-prose / differently-keyed occurrences (case-sensitive,
#       frontmatter-scoped, top-level `oracle_update:` key only).

# extract_frontmatter — prints the frontmatter body ONLY if a CLOSING `---` exists (L1).
# No leading `---` on line 1, or no closing `---`, => prints nothing.
extract_frontmatter() {
  awk '
    NR==1 { if ($0 ~ /^---[[:space:]]*$/) { started=1; next } else { exit } }
    started && $0 ~ /^---[[:space:]]*$/ { closed=1; exit }
    started { buf = buf $0 "\n" }
    END { if (closed) printf "%s", buf }
  ' "$WO_FILE"
}

parse_oracle_classes() {
  local _fm
  _fm="$(extract_frontmatter)"
  [ -z "$_fm" ] && return 0
  printf '%s' "$_fm" | awk '
    BEGIN { in_ou=0; in_classes=0; out="" }
    # top-level oracle_update mapping key (case-sensitive, column 0, no leading #)
    /^oracle_update:[[:space:]]*$/ { in_ou=1; in_classes=0; next }
    # any other top-level key (non-space, non-#) ends the oracle_update block
    in_ou && /^[^[:space:]#]/ { in_ou=0; in_classes=0 }
    # inline flow list: classes: [a, b]
    in_ou && /^[[:space:]]+classes:[[:space:]]*\[/ {
      line=$0
      sub(/^[[:space:]]*classes:[[:space:]]*/, "", line)
      sub(/#.*/, "", line)            # strip a trailing inline comment
      gsub(/[\[\]]/, "", line)
      gsub(/"/, "", line)             # M2: strip double quotes
      gsub(/\047/, "", line)          # M2: strip single quotes (octal 047)
      gsub(/[[:space:]]/, "", line)
      if (line != "") out = (out == "" ? line : out "," line)
      in_classes=0
      next
    }
    # block-style list header: classes: (value continues on indented `- item` lines)
    in_ou && /^[[:space:]]+classes:[[:space:]]*$/ { in_classes=1; next }
    # block-style list item: `- baseline`
    in_classes && /^[[:space:]]+-[[:space:]]*/ {
      item=$0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      sub(/#.*/, "", item)            # strip a trailing inline comment
      gsub(/"/, "", item)             # M2: strip double quotes
      gsub(/\047/, "", item)          # M2: strip single quotes
      gsub(/[[:space:]]/, "", item)
      if (item != "") out = (out == "" ? item : out "," item)
      next
    }
    # a sibling key under oracle_update (reason:, by:) ends the classes list
    in_classes && /^[[:space:]]+[^[:space:]-]/ { in_classes=0 }
    END { print out }
  '
}

ORACLE_CLASSES="$(parse_oracle_classes || true)"

# --- glob-to-regex converter -------------------------------------------------
# Converts a file glob pattern to a bash ERE regex anchored at start and end.
#   *  matches any string within one path segment (no slash)  → [^/]*
#   ** matches any string across path segments               → .*
#   .  is literal in a path                                  → \.
# Input:  glob pattern string (e.g. "tests/**/*Test.php")
# Output: ERE regex string  (e.g. "^tests/(.*/)?[^/]*Test\.php$")
glob_to_regex() {
  local _g="$1" _r
  # 1. Escape literal dots
  _r="$(printf '%s' "$_g" | sed -e 's/[.]/\\./g')"
  # 2. Replace **/ and ** with placeholders (no * chars) to prevent the
  #    single-* pass from re-processing the .* introduced by these replacements
  _r="$(printf '%s' "$_r" | sed -e 's|\*\*/|__GLOBSTAR_SLASH__|g')"
  _r="$(printf '%s' "$_r" | sed -e 's|\*\*|__GLOBSTAR__|g')"
  # 3. Replace remaining single * with one-segment wildcard
  _r="$(printf '%s' "$_r" | sed -e 's|\*|[^/]*|g')"
  # 4. Restore placeholders to their ERE regex equivalents
  _r="$(printf '%s' "$_r" \
    | sed -e 's|__GLOBSTAR_SLASH__|(.*/)?|g' \
    | sed -e 's|__GLOBSTAR__|.*|g')"
  printf '^%s$' "$_r"
}

# path_matches <path> <glob-pattern>  — returns 0 if the path matches the glob, 1 otherwise
path_matches() {
  local _pm_path="$1" _pm_pat="$2" _pm_rx
  _pm_rx="$(glob_to_regex "$_pm_pat")"
  [[ "$_pm_path" =~ $_pm_rx ]]
}

# is_in_oracle_classes <oracle-class>  — returns 0 if class is in ORACLE_CLASSES, 1 if not
is_in_oracle_classes() {
  local _cls="$1"
  if [ -z "$ORACLE_CLASSES" ]; then
    return 1
  fi
  # ORACLE_CLASSES is comma-separated; wrap with commas to avoid partial matches
  case ",$ORACLE_CLASSES," in
    *,"$_cls",*) return 0 ;;
  esac
  return 1
}

# classify_path <status> <path>
# Sets _CLS_TYPE, _CLS_ORACLE_CLASS, _CLS_SEVERITY on match and returns 0.
# Returns 1 if the path+status combination matches no watch-table row.
classify_path() {
  local _cp_st="$1" _cp_p="$2"
  _CLS_TYPE=""; _CLS_ORACLE_CLASS=""; _CLS_SEVERITY=""

  # --- A or M changes ----------------------------------------------------------
  case "$_cp_st" in
    A|M)
      # baseline_write: visual snapshot images and meta files (** => nested baselines
      # under the snapshots dir still match; the **/ => (.*/)? regex keeps flat matching)
      if path_matches "$_cp_p" "tests/visual/*.spec.ts-snapshots/**/*.png" ||
         path_matches "$_cp_p" "tests/visual/*.spec.ts-snapshots/**/*.meta.json"; then
        _CLS_TYPE="baseline_write"
        _CLS_ORACLE_CLASS="baseline"
        _CLS_SEVERITY="halt"
        return 0
      fi
      # phpstan_baseline: baseline neon file written or modified
      if path_matches "$_cp_p" "phpstan-baseline.neon"; then
        _CLS_TYPE="phpstan_baseline"
        _CLS_ORACLE_CLASS="phpstan-baseline"
        _CLS_SEVERITY="halt"
        return 0
      fi
      ;;
  esac

  # --- D (delete) changes only -------------------------------------------------
  case "$_cp_st" in
    D)
      # vr_spec_delete: visual spec file deleted
      if path_matches "$_cp_p" "tests/visual/*.spec.ts"; then
        _CLS_TYPE="vr_spec_delete"
        _CLS_ORACLE_CLASS="test-delete"
        _CLS_SEVERITY="halt"
        return 0
      fi
      # test_delete: PHPUnit test, e2e spec, or ATK spec deleted
      if path_matches "$_cp_p" "tests/**/*Test.php" ||
         path_matches "$_cp_p" "tests/e2e/**/*.spec.ts" ||
         path_matches "$_cp_p" "tests/atk/**/*.spec.ts"; then
        _CLS_TYPE="test_delete"
        _CLS_ORACLE_CLASS="test-delete"
        _CLS_SEVERITY="halt"
        return 0
      fi
      ;;
  esac

  # --- M (modify) only — flag-severity rows ------------------------------------
  case "$_cp_st" in
    M)
      # phpstan_config: phpstan config files modified
      if path_matches "$_cp_p" "phpstan.neon" ||
         path_matches "$_cp_p" "phpstan.neon.dist"; then
        _CLS_TYPE="phpstan_config"
        _CLS_ORACLE_CLASS="phpstan-baseline"
        _CLS_SEVERITY="flag"
        return 0
      fi
      # registry_shrink: visual review registry modified
      if path_matches "$_cp_p" ".visual-review/registry.yml"; then
        _CLS_TYPE="registry_shrink"
        _CLS_ORACLE_CLASS="baseline"
        _CLS_SEVERITY="flag"
        return 0
      fi
      # coverage_threshold: test runner config files modified
      if path_matches "$_cp_p" "jest.config.*" ||
         path_matches "$_cp_p" "phpunit.xml" ||
         path_matches "$_cp_p" "phpunit.xml.dist"; then
        _CLS_TYPE="coverage_threshold"
        _CLS_ORACLE_CLASS="coverage-threshold"
        _CLS_SEVERITY="flag"
        return 0
      fi
      ;;
  esac

  return 1
}

# --- process diff lines -------------------------------------------------------
SIGNALS_JSON="[]"
N_HALT=0
_CLS_TYPE=""; _CLS_ORACLE_CLASS=""; _CLS_SEVERITY=""

# process_change <status A|M|D> <path>
# Classifies ONE (status, path) pair against the watch table; on a match appends the
# signal to SIGNALS_JSON and bumps N_HALT for an un-exempted halt. No-op on no match.
# Mutates globals SIGNALS_JSON / N_HALT. Returns 0 always (no match is not an error).
process_change() {
  local _pc_status="$1" _pc_path="$2"
  [ -z "$_pc_path" ] && return 0

  _CLS_TYPE=""; _CLS_ORACLE_CLASS=""; _CLS_SEVERITY=""
  classify_path "$_pc_status" "$_pc_path" || return 0

  # allowed_by_scope via oracle_update.classes
  local _sig_allowed="false"
  if is_in_oracle_classes "$_CLS_ORACLE_CLASS"; then
    _sig_allowed="true"
  fi

  # Effective severity: downgrade halt -> flag when allowed by oracle_update
  local _sig_severity="$_CLS_SEVERITY"
  if [ "$_CLS_SEVERITY" = "halt" ] && [ "$_sig_allowed" = "true" ]; then
    _sig_severity="flag"
  fi

  # Append signal to JSON array (all JSON built with jq — no string concatenation)
  SIGNALS_JSON="$(jq -c \
    --arg   type          "$_CLS_TYPE" \
    --arg   path          "$_pc_path" \
    --arg   change        "$_pc_status" \
    --arg   oracle_class  "$_CLS_ORACLE_CLASS" \
    --arg   severity      "$_sig_severity" \
    --argjson allowed_by_scope "$_sig_allowed" \
    '. + [{"type":$type,"path":$path,"change":$change,
           "oracle_class":$oracle_class,"severity":$severity,
           "allowed_by_scope":$allowed_by_scope}]' \
    <<< "$SIGNALS_JSON")"

  # Count un-exempted halt signals on ORIGINAL severity (drives tamper_detected)
  if [ "$_CLS_SEVERITY" = "halt" ] && [ "$_sig_allowed" = "false" ]; then
    N_HALT=$((N_HALT + 1))
  fi
  return 0
}

while IFS=$'\t' read -r _f1 _f2 _f3 || [ -n "${_f1:-}" ]; do
  # Strip carriage returns (Windows line endings)
  _f1="${_f1%$'\r'}"; _f2="${_f2%$'\r'}"; _f3="${_f3%$'\r'}"

  # Skip empty lines
  [ -z "$_f1" ] && continue

  case "$_f1" in
    # RENAME (R###, or bare R): the OLD path (_f2) is classified as D against the
    # D-watched rows (C1 evasion — git mv of a test OUT of tests/ deletes its coverage),
    # AND the NEW path (_f3) as A against the A-watched rows (rename INTRODUCES a baseline).
    R*)
      process_change "D" "$_f2"
      process_change "A" "$_f3"
      ;;
    # COPY (C###, or bare C): only the NEW path (_f3) is new => classify as A
    # (the original is untouched, so no delete signal for the old path).
    C*)
      process_change "A" "$_f3"
      ;;
    # Plain single-path status: path is in _f2, _f3 empty.
    A|M|D)
      process_change "$_f1" "$_f2"
      ;;
    *)
      continue
      ;;
  esac
done < "$DIFF_FROM"

# --- verdict -----------------------------------------------------------------
TAMPER_DETECTED="false"
if [ "$N_HALT" -gt 0 ]; then
  TAMPER_DETECTED="true"
fi

HALT_REASON="null"
if [ "$TAMPER_DETECTED" = "true" ]; then
  HALT_REASON='"oracle_tamper"'
fi

# --- emit verdict on stdout (always exit 0 from here) -----------------------
jq -nc \
  --argjson tamper      "$TAMPER_DETECTED" \
  --argjson signals     "$SIGNALS_JSON" \
  --argjson halt_reason "$HALT_REASON" \
  '{"schema_version":"1.0","tamper_detected":$tamper,"signals":$signals,"halt_reason":$halt_reason}'
