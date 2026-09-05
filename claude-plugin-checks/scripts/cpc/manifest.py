"""Reading a plugin manifest, and finding every path it declares.

The path half is the part that was wrong: an earlier version collected a string
only when it started with `./` or `../`, so an absolute path and the
`${CLAUDE_PLUGIN_ROOT}/...` form were both invisible. A manifest pointing a
component at /etc/passwd reported clean. The plugin's own containment check
recommends the placeholder form, so it is the expected spelling, not an edge case.
"""

import json
import os
import re

MANIFEST_REL = os.path.join(".claude-plugin", "plugin.json")

# The runtime substitutes this before resolving a path, so we do too.
PLUGIN_ROOT_VAR = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}|\$CLAUDE_PLUGIN_ROOT\b")


class DuplicateKeys(Exception):
    def __init__(self, keys):
        super().__init__(", ".join(keys))
        self.keys = keys


def _pairs(pairs):
    seen, dups = set(), []
    for k, _ in pairs:
        if k in seen and k not in dups:
            dups.append(k)
        seen.add(k)
    if dups:
        raise DuplicateKeys(dups)
    return dict(pairs)


def load_json(path):
    """(data, error, duplicate_keys).

    json.load keeps the last of a repeated key and discards the rest with no
    message, so half a file can vanish and still parse. The hook catches that.
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        return None, str(exc), None
    try:
        return json.loads(text, object_pairs_hook=_pairs), None, None
    except DuplicateKeys as exc:
        return json.loads(text), None, exc.keys
    except (ValueError, UnicodeDecodeError) as exc:
        return None, str(exc), None


def walk_strings(node, trail=()):
    """Every string in the manifest with the dotted field path that reached it."""
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk_strings(v, trail + (str(k),))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk_strings(v, trail + (str(i),))
    elif isinstance(node, str):
        yield ".".join(trail), node


def looks_like_path(value):
    """Does this manifest string SAY it is a path, on its own?

    Only the explicit forms: ./, ../, a leading slash, or the plugin-root
    placeholder. Those are unambiguous, so a missing target is a real finding.

    Plus two shapes that are unambiguous on their own: a trailing separator, and
    a last segment carrying a file extension.

    A bare word like `commands`, or a slashed pair with no extension like
    `camoa/claude-skills` or `ci/cd`, says nothing either way. declared_paths
    settles those by asking whether anything is there, which means a bare word
    naming a directory that does not exist is not reported. That is the
    deliberate cost of not reporting every repository shorthand and keyword in
    every manifest as a missing component.
    """
    if not value or value.isspace():
        return False
    # A declared path has no whitespace in it. Without this, any prose field
    # containing a slash is collected: a plugin description reading
    # "deeper SOLID/DRY analysis" was reported as a component that does not exist.
    if any(c.isspace() for c in value):
        return False
    if PLUGIN_ROOT_VAR.search(value):
        return True
    if value.startswith(("./", "../", "/")):
        return True
    if "://" in value:
        return False
    # Two more shapes that say "path" on their own, so a missing target is still
    # a real finding: a trailing separator, and a last segment with a file
    # extension on it. Narrowing to the explicit prefixes alone made a manifest
    # declaring `agents/` and `config/mcp.json` with neither present report
    # clean, which is the case the missing-path rule exists for.
    if value.endswith("/"):
        return True
    last = value.rsplit("/", 1)[-1]
    if "/" in value and "." in last and not last.startswith("."):
        stem, _, ext = last.rpartition(".")
        return bool(stem) and ext.isalnum() and 1 <= len(ext) <= 5
    return False


def resolve(root, value):
    """Absolute path for a declared value, with the placeholder expanded."""
    expanded = PLUGIN_ROOT_VAR.sub(root, value)
    if not os.path.isabs(expanded):
        expanded = os.path.join(root, expanded)
    return os.path.realpath(expanded)


def inside(root, target):
    return target == root or target.startswith(root + os.sep)


def declared_paths(manifest, root):
    """[(field, raw value, resolved absolute path)] for every declared path."""
    import os as _os
    out = []
    if not isinstance(manifest, (dict, list)):
        return out
    for field, value in walk_strings(manifest):
        target = resolve(root, value) if value and not value.isspace() else None
        # Either it is shaped like a path, or something is actually there. The
        # second test settles the ambiguous bare name: "commands" is a path when
        # a commands directory exists beside the manifest, and a plain word when
        # it does not. "MIT" resolves to nothing and stays a plain word.
        spaced = bool(value) and any(c.isspace() for c in value)
        if looks_like_path(value) or (target and not spaced and _os.path.exists(target)):
            out.append((field, value, target))
    return out
