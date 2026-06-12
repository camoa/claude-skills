#!/usr/bin/env bash
# lib-changed-mapping.sh — changed-source → co-located-test mapping library
# Sourced by tdd-workflow.sh and coverage-report.sh. Pure path manipulation;
# no ddev, no PHPUnit, no network. Fully hermetic and testable in isolation.
#
# Mapping convention (Drupal module layout):
#   changed  web/modules/custom/<mod>/src/<Dir>/<File>.php
#   → Unit   web/modules/custom/<mod>/tests/src/Unit/<Dir>/<File>Test.php
#   → Kernel web/modules/custom/<mod>/tests/src/Kernel/<Dir>/<File>Test.php
#
# Module root = ancestor directory whose direct child is the /src/ segment
# (found via longest-suffix strip on the first /src/ occurrence — see tests).
#
# Mapping limit (documented here and in commands/{tdd,coverage}.md):
#   PHPUnit has no --findRelatedTests equivalent; that flag is Jest/Next.js only.
#   The mapping is structural (co-location by path convention) not semantic.
#   Sources with no co-located *Test.php are recorded as coverage gaps — they
#   are NOT test failures. See: scripts/tests/changed-mode-spec.sh.

# map_source_to_test_paths <src_file>
# Prints candidate test paths (one per line) for a changed source file.
# The file does NOT need to exist on disk — only path manipulation is done here.
# Exits non-zero and prints nothing for non-.php files or files without /src/.
map_source_to_test_paths() {
  local src_file="$1"

  # Only .php source files inside a /src/ directory segment
  [[ "$src_file" == *.php ]]     || return 1
  [[ "$src_file" == *"/src/"* ]] || return 1

  # module_root = everything before the FIRST /src/ segment.
  # %%/src/* strips the LONGEST suffix matching /src/*, which starts at the
  # rightmost /src/ that can be followed by anything — i.e. the last /src/.
  # Combined with the fact that /src/* requires a literal slash after "src",
  # this correctly resolves even when the module name contains "src_": the
  # pattern /src/* requires the slash, so /src_tools/ does not match.
  local module_root="${src_file%%/src/*}"

  # rel_from_src = path relative to the first /src/ separator.
  # #*/src/ strips the SHORTEST prefix ending in /src/ — so we anchor at the
  # first /src/ even when the path contains a nested src/ later.
  local rel_from_src="${src_file#*/src/}"

  # Split dir/file and build test name
  local no_ext="${rel_from_src%.php}"
  local dir_part file_part
  if [[ "$no_ext" == *"/"* ]]; then
    dir_part="${no_ext%/*}"
    file_part="${no_ext##*/}"
  else
    dir_part=""
    file_part="$no_ext"
  fi

  local test_name="${file_part}Test.php"

  for tier in Unit Kernel; do
    if [[ -n "$dir_part" ]]; then
      echo "${module_root}/tests/src/${tier}/${dir_part}/${test_name}"
    else
      echo "${module_root}/tests/src/${tier}/${test_name}"
    fi
  done
}

# find_mapped_tests <src_file>
# Like map_source_to_test_paths but filters to candidate paths that EXIST on
# disk. Call from the project root so relative paths resolve correctly; absolute
# src_file paths produce absolute candidates (checked as-is).
# Always exits 0: printing nothing means a gap, which is informational not a
# failure. The CALLER decides how to handle an empty result.
find_mapped_tests() {
  local src_file="$1"
  local candidate
  while IFS= read -r candidate; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
    fi
  done < <(map_source_to_test_paths "$src_file")
  return 0
}
