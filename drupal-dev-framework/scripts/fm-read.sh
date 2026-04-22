#!/usr/bin/env bash
# fm-read.sh — entry point for the task-frontmatter-reader skill.
# Usage: fm-read.sh <task_folder>
# Always exits 0; emits JSON to stdout per the reader's contract.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=./fm-helpers.sh
. "$SCRIPT_DIR/fm-helpers.sh"

if [ $# -lt 1 ]; then
  echo "usage: $0 <task_folder>" >&2
  exit 2
fi

fm_read "$1"
