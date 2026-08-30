#!/usr/bin/env python3
"""emitted-json-paths.py — which JSON paths a gate script actually WRITES.

This exists because every previous version of the gate-coverage work compared our prose
to our prose. Not one assertion opened `security-check.sh`, and that is why three field
paths that do not exist survived four rounds of review:

  * `.status` on security-report.json  — it is `.summary.overall_status`
  * `.meta.tools` in `--changed` mode   — that mode emits `tools_run` / `tools_skipped`
  * `.tools_failed` on dry-report.json  — dry emits no such key on any path

Each is a claim about a producer, and a claim about a producer can only be checked by
reading the producer. This script reads the JSON-emitting blocks out of a gate script and
reports the paths they build, so the suite can hold the resolver to them.

Usage:
    emitted-json-paths.py <gate-script>              # list every emitted path
    emitted-json-paths.py <gate-script> <path> ...   # exit 0 iff EVERY path is emitted

Two block shapes cover every emitter in the suite:
    heredoc  cat > "${REPORT_DIR}/x-report.json" << EOF { ... } EOF
    jq       jq -n --arg ... '{ ... }' > "${REPORT_DIR}/x-report.json"

Depth comes from a real brace walk, not from indentation, so a key nested under `summary`
is never mistaken for a top-level one — which is the exact mistake being defended against.
Shell interpolations (`${VAR}`) are stripped before the walk: they carry balanced braces
that would otherwise push and pop a phantom level.
"""

import re
import sys

# A key line in either shape: `"status":` in a heredoc, `overall_status:` in a jq program.
KEY_RE = re.compile(r'^\s*"?([A-Za-z_][A-Za-z0-9_]*)"?\s*:')
# ${VAR}, $(cmd) and ${VAR:-default} all carry braces that are not JSON structure.
INTERP_RE = re.compile(r'\$\{[^}]*\}|\$\([^)]*\)')


def _blocks(text):
    """Every region of the script that constructs a JSON object for a report."""
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]

        # heredoc: `cat > "<something>.json" << EOF` (quoted or bare delimiter)
        m = re.search(r'cat\s*>\s*.*\.json"?\s*<<-?\s*[\'"]?(\w+)[\'"]?\s*$', line)
        if m:
            delim, j, buf = m.group(1), i + 1, []
            while j < len(lines) and lines[j].strip() != delim:
                buf.append(lines[j])
                j += 1
            # A heredoc body opens with its own bare `{`, while a jq block's `'{` was
            # consumed as the opener. Drop it so both shapes start INSIDE the object and
            # a top-level key is at depth 0 in either.
            while buf and not buf[0].strip():
                buf.pop(0)
            if buf and buf[0].strip() == "{":
                buf.pop(0)
                while buf and not buf[-1].strip():
                    buf.pop()
                if buf and buf[-1].strip() in ("}", "},"):
                    buf.pop()
            out.append("\n".join(buf))
            i = j + 1
            continue

        # jq program: a line whose content opens a single-quoted object literal.
        if re.search(r"'\{\s*$", line):
            j, buf, depth = i + 1, [], 1
            while j < len(lines):
                if re.match(r"^\s*\}'", lines[j]):
                    break
                buf.append(lines[j])
                j += 1
            out.append("\n".join(buf))
            i = j + 1
            continue

        i += 1
    return out


def emitted_paths(text):
    """Set of dotted paths (`.summary.overall_status`) the script's emitters build."""
    found = set()
    for block in _blocks(text):
        stack = []
        for raw in block.split("\n"):
            line = INTERP_RE.sub("X", raw)
            km = KEY_RE.match(line)
            pending = km.group(1) if km else None
            if pending:
                found.add("." + ".".join(stack + [pending]))
            # Walk the structural braces left to right. A `{` after a key opens that
            # key's object; any other `{` opens an anonymous level we still must pop.
            after = line[km.end():] if km else line
            for ch in after:
                if ch == "{":
                    stack.append(pending if pending else "?")
                    pending = None
                elif ch == "}":
                    if stack:
                        stack.pop()
    return found


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as exc:
        print("cannot read %s: %s" % (argv[1], exc), file=sys.stderr)
        return 2

    paths = emitted_paths(text)
    if not paths:
        # A producer we could not parse must not read as a producer that emits nothing:
        # that would pass every path check by finding no contradiction.
        print("NO-EMITTER-FOUND %s" % argv[1], file=sys.stderr)
        return 3

    wanted = argv[2:]
    if not wanted:
        for p in sorted(paths):
            print(p)
        return 0

    missing = [w for w in wanted if w not in paths]
    for w in missing:
        print("MISSING %s" % w)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
