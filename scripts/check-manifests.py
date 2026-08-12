#!/usr/bin/env python3
"""Checks each plugin's own manifest against the marketplace catalog.

Rules:
  1. Every plugin folder (one holding .claude-plugin/plugin.json) has an
     entry in .claude-plugin/marketplace.json.
  2. Every entry in marketplace.json has a plugin folder.
  3. The version matches between the two files.
  4. plugin.json declares "$schema".

The two descriptions are deliberately NOT compared. The catalog entry is the
browse-and-choose pitch and plugin.json is the terse identity line; this repo
keeps them different on purpose, and Claude Code defines precedence only for
"version" (plugin.json wins) and "defaultEnabled" (marketplace wins).

Exit 0 when everything matches, 1 otherwise.
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / ".claude-plugin" / "marketplace.json"
SCHEMA_URL = "https://json.schemastore.org/claude-code-plugin-manifest.json"


def load(path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def main():
    if not CATALOG.exists():
        print(f"error: {CATALOG} not found")
        return 1

    catalog = load(CATALOG)
    entries = {entry["name"]: entry for entry in catalog.get("plugins", [])}

    problems = []
    checked = 0

    for manifest_path in sorted(ROOT.glob("*/.claude-plugin/plugin.json")):
        folder = manifest_path.parent.parent.name
        manifest = load(manifest_path)
        name = manifest.get("name", folder)
        checked += 1

        if "$schema" not in manifest:
            problems.append(f'{folder}: plugin.json is missing "$schema" ({SCHEMA_URL})')

        entry = entries.get(name)
        if entry is None:
            problems.append(f"{folder}: no entry named '{name}' in marketplace.json")
            continue

        if manifest.get("version") != entry.get("version"):
            problems.append(
                f"{folder}: version {manifest.get('version')} in plugin.json, "
                f"{entry.get('version')} in marketplace.json"
            )

    listed = set(entries)
    found = {p.parent.parent.name for p in ROOT.glob("*/.claude-plugin/plugin.json")}
    for name in sorted(listed - found):
        problems.append(f"{name}: listed in marketplace.json but no such plugin folder")

    print(f"manifests: {checked} plugins checked")
    for problem in problems:
        print(f"  FAIL  {problem}")
    if problems:
        print(f"manifests: {len(problems)} problem(s)")
        return 1
    print("manifests: all match")
    return 0


if __name__ == "__main__":
    sys.exit(main())
