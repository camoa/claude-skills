"""The component files the first-party validator declares and never opens.

The gap, reproduced against the real CLI: three monitor entries sharing a name
written inline in plugin.json give "Found 1 error"; the identical content at
./config/monitors.json gives "Validation passed with warnings" and exit 0. The
same holds for .lsp.json, .mcp.json and output-style files.

The defect this module was rewritten to remove: it collected a declared path
only when the string started with "./" or "../". An absolute path and the
${CLAUDE_PLUGIN_ROOT} form were both invisible, so a manifest pointing a
component at /etc/passwd reported clean, and across the eight plugins in this
repository the containment and existence rules fired on nothing at all. Path
collection now lives in cpc.manifest and is deliberately generous.

What this does NOT check is which fields belong inside one of these files. That
is a fact Anthropic owns and can change; a repeated key and a colliding
identifier are properties of the file itself.
"""

import os

from .. import manifest, walk
from ..result import ERROR, WARN, Finding

PREFIX = "E"
NAME = "external components"

# Locations Claude Code reads by convention. Kept because a plugin that declares
# nothing still ships these, but they no longer decide the outcome on their own:
# whether anything was examined is counted in report.subjects, so one incidental
# file cannot turn "nothing was checked" into a clean pass.
CONVENTIONAL = (".mcp.json", ".lsp.json", os.path.join("hooks", "hooks.json"))

# Compared only against its own siblings. "These two entries collide" is
# self-consistency; "this field must be called name" would not be.
ID_FIELDS = ("name", "id", "key")


def _collisions(entries, path, where, report):
    for field in ID_FIELDS:
        seen, dup = set(), []
        for entry in entries:
            if isinstance(entry, dict) and isinstance(entry.get(field), str):
                value = entry[field]
                if value in seen and value not in dup:
                    dup.append(value)
                seen.add(value)
        if dup:
            report.add(Finding(
                "E06", ERROR, "duplicate-entry-id",
                "Two entries carry the same identifier. One wins and the other is dropped, or "
                "the whole file is rejected, depending on the component.",
                file=path, field=field, duplicates=dup, container=where))


def _read_component_json(path, report, declared):
    data, err, dups = manifest.load_json(path)
    if err is not None:
        report.add(Finding(
            "E03", ERROR, "unparsable-json",
            "A component file that does not parse. Claude Code skips a component whose file is "
            "invalid and says so only under --debug.",
            file=path, detail=err))
        return
    if dups:
        report.add(Finding(
            "E04", ERROR, "duplicate-json-key",
            "A repeated key. JSON keeps the last one and discards the rest with no message, so "
            "part of this file is not in effect.",
            file=path, keys=dups))

    # An empty container is only worth reporting when the manifest declared it.
    # A conventional file somebody left empty is not a promise broken.
    if declared and isinstance(data, (dict, list)) and len(data) == 0:
        report.add(Finding(
            "E05", WARN, "declared-empty",
            "Declared as a component and parses to an empty container. It is wired up and "
            "contributes nothing, which reads at a glance as a component that exists.",
            file=path))

    if isinstance(data, list):
        _collisions(data, path, "(root)", report)
    elif isinstance(data, dict):
        for key, value in data.items():
            if isinstance(value, list):
                _collisions(value, path, key, report)


def run(root, report):
    manifest_path = os.path.join(root, manifest.MANIFEST_REL)
    if not os.path.isfile(manifest_path):
        report.cannot_look(manifest.MANIFEST_REL,
                           "no plugin manifest, so nothing declares a component path")
        return

    data, err, dups = manifest.load_json(manifest_path)
    report.subjects += 1
    if err is not None:
        report.add(Finding(
            "E03", ERROR, "unparsable-json",
            "The manifest itself does not parse, so no component path could be read.",
            file=manifest_path, detail=err))
        return
    if dups:
        report.add(Finding(
            "E04", ERROR, "duplicate-json-key",
            "A repeated key in the manifest. JSON keeps the last one and discards the rest with "
            "no message, so part of the manifest is not in effect.",
            file=manifest_path, keys=dups))

    declared = manifest.declared_paths(data, root)
    report.count("declared_paths", len(declared))

    json_targets, md_targets, declared_files = set(), set(), set()

    for field, raw, target in declared:
        if not manifest.inside(root, target):
            report.add(Finding(
                "E01", ERROR, "path-escapes-plugin",
                "A component path resolving outside the plugin directory. Some fields the "
                "first-party validator catches and some it does not; a manifest pointing "
                "mcpServers outside the plugin started the server.",
                field=field, declared=raw, resolved=target))
            continue
        if not os.path.exists(target):
            report.add(Finding(
                "E02", ERROR, "path-missing",
                "The manifest declares this path and there is nothing at it. The component is "
                "dropped and the plugin loads without it.",
                field=field, declared=raw))
            continue
        if os.path.isfile(target):
            declared_files.add(target)
            (json_targets if target.endswith(".json") else md_targets).add(target)
        else:
            for found in walk.files(target, report):
                declared_files.add(found)
                if found.endswith(".json"):
                    json_targets.add(found)
                elif found.endswith(".md"):
                    md_targets.add(found)

    for name in CONVENTIONAL:
        path = os.path.join(root, name)
        if os.path.isfile(path):
            json_targets.add(os.path.realpath(path))

    json_targets.discard(os.path.realpath(manifest_path))

    for path in sorted(json_targets):
        report.subjects += 1
        _read_component_json(path, report, declared=path in declared_files)

    # Markdown reached through a declared path is counted as examined, but the
    # frontmatter rules live in the structure module, which walks every markdown
    # file rather than only the declared ones.
    report.subjects += len(md_targets)
