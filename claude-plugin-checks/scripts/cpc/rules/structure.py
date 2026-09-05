"""Three ways a component file contradicts itself.

None of these knows a value Claude Code defines. Each compares a file against
itself, so none can go stale.

Four things this module was rewritten to remove:

  * the grant side was a closed roster of four field spellings while the comment
    above it claimed matching was "by shape, not a fixed roster". Both sides are
    substring tests now, so a field renamed upstream does not silence the check.
  * the finding asserted "the denial wins, so the grant reads as true and is
    not". Which side wins is a fact nobody here has measured, and an earlier
    version of this same check called two working agents broken by guessing at
    exactly that. It names the collision and stops.
  * a setext heading followed by ordinary prose was reported as misplaced
    frontmatter. The block has to prove it is frontmatter first.
  * an execution marker in a fenced example was reported in READMEs, changelogs
    and documentation pages. Only a file carrying frontmatter is a component
    body, and only a component body is a subject.
"""

import re

from .. import walk
from ..result import ERROR, WARN, Finding

PREFIX = "S"
NAME = "structure consistency"

# Both sides are substring tests. `tools`, `allowed-tools`, `allowedTools` and a
# spelling nobody has invented yet all reach the grant branch.
DENY_KEY = re.compile(r"disallow|denied|deny", re.I)
GRANT_KEY = re.compile(r"tool", re.I)

FENCE = re.compile(r"^(`{3,}|~{3,})")
EXEC_MARKER = re.compile(r"!`[^`]+`")

SKIP_DIRS = {"tests", "test", "fixtures", "__pycache__"}


def _tool_list(value):
    if isinstance(value, list):
        return [str(v).strip() for v in value if isinstance(v, (str, int, float))]
    if isinstance(value, str):
        return [p.strip() for p in value.split(",") if p.strip()]
    return []


def _literal(name):
    """Compared as written. `Bash` against `Bash(rm:*)` is a different question,
    whose answer is a fact about Claude Code that has not been measured here."""
    return " ".join(name.split())


def _frontmatter_block(lines, accept_malformed=True):
    """(body_start, yaml_text) when the file really opens with frontmatter.

    A block qualifies when the fence is first, it closes, and what is between
    parses as a YAML mapping. Asking the parser is the point: an earlier version
    hand-checked each line against one narrow shape, so a YAML comment, a blank
    line, a quoted key or a block scalar all made a real component body look
    like ordinary prose and silently switched every rule here off for that file.

    A setext heading over prose still fails, because it either never closes or
    parses to a string rather than a mapping.
    """
    import yaml as _yaml
    if not lines or lines[0].lstrip("﻿").strip() != "---":
        return None, None
    for end in range(1, len(lines)):
        if lines[end].strip() != "---":
            continue
        inner = lines[1:end]
        if not inner or not any(l.strip() for l in inner):
            return None, None
        text = "\n".join(inner)
        try:
            parsed = _yaml.safe_load(text)
        except _yaml.YAMLError:
            # Malformed YAML between two fences at the TOP of a file is a
            # component body with broken frontmatter, so hand it back and let
            # the caller report it. Asking whether a fence further down the file
            # would have been frontmatter is a different question, and answering
            # yes there reported every documentation page with two horizontal
            # rules in it.
            return (end, text) if accept_malformed else (None, None)
        if not isinstance(parsed, dict):
            return None, None
        return end, text
    return None, None


KEY_LINE = re.compile(r"^[A-Za-z_][A-Za-z0-9_.-]*\s*:")


def _misplaced_fence(lines):
    """Line number of a fence that would have been frontmatter had it been first.

    Only blank lines may precede it. Prose above a fence means a document, not a
    component whose frontmatter slipped down a line: a page with a heading and
    two horizontal rules was reported here, and so was one with a single colon
    between two rules, because that parses as a YAML mapping. What cannot be
    anything else is a fence preceded by nothing but whitespace.
    """
    for i, line in enumerate(lines[:8]):
        if line.strip() != "---":
            continue
        if any(l.strip() for l in lines[:i]):
            return None
        rest = lines[i:]
        end, _ = _frontmatter_block(rest, accept_malformed=False)
        if end is not None:
            return i + 1
        return None
    return None


def run(root, report):
    import os
    import yaml

    for path in walk.files(root, report, suffixes=(".md",)):
        rel = os.path.relpath(path, root)
        if any(part in SKIP_DIRS for part in rel.split(os.sep)):
            continue
        text = walk.read_text(path, report)
        if text is None:
            continue
        report.subjects += 1
        lines = text.split("\n")

        # S04 — a fence that opens and never closes, so the whole file is read
        # as frontmatter and the body disappears. This lives here rather than
        # with the component-file rules because those only see files a manifest
        # declares by path, and no plugin in this repository declares any, so
        # the check fired on nothing at all.
        # The line under the fence has to look like a YAML key, or this reports
        # every documentation page that opens with a horizontal rule.
        if lines and lines[0].lstrip("\ufeff").strip() == "---" \
                and len(lines) > 1 and KEY_LINE.match(lines[1]) \
                and not any(l.strip() == "---" for l in lines[1:]):
            report.add(Finding(
                "S04", ERROR, "unterminated-frontmatter",
                "The frontmatter fence opens and never closes, so the whole file is read as "
                "frontmatter and the body disappears.",
                file=path, line=1))
            continue

        # A byte-order mark ahead of the fence is checked before anything else,
        # because stripping it makes the block look ordinary. It is a WARNING,
        # not an error: whether the loader tolerates a leading mark is a fact
        # about Claude Code that is not measured here, so this names the anomaly
        # without claiming the consequence.
        if lines and lines[0].startswith("\ufeff") and lines[0].lstrip("\ufeff").strip() == "---":
            report.add(Finding(
                "S02", WARN, "byte-order-mark-before-frontmatter",
                "A byte-order mark sits before the opening fence, so the fence is not the first "
                "byte of the file. Whether the loader looks past it is not something this check "
                "measures; remove the mark and the question does not arise.",
                file=path, line=1))

        body_start, yaml_text = _frontmatter_block(lines)

        # S02 — the block that should have been frontmatter and is not.
        if body_start is None:
            at = _misplaced_fence(lines)
            if at is not None and at > 1:
                report.add(Finding(
                    "S02", ERROR, "frontmatter-not-at-start",
                    "The frontmatter fence is not on line one, so the block is body text and "
                    "every field in it is silently ignored.",
                    file=path, line=at,
                    preceded_by=repr("\n".join(lines[:at - 1])[:80])))
            continue

        front = None
        try:
            front = yaml.safe_load(yaml_text) or {}
        except yaml.YAMLError as exc:
            report.add(Finding(
                "S02", ERROR, "unparsable-frontmatter",
                "The frontmatter block does not parse as YAML, so none of it applies.",
                file=path, line=1, detail=str(exc).split("\n")[0]))

        # S01 — the same entry granted and denied.
        if isinstance(front, dict):
            granted, denied = {}, {}
            for key, value in front.items():
                name = str(key)
                if DENY_KEY.search(name):
                    for tool in _tool_list(value):
                        denied.setdefault(_literal(tool), name)
                elif GRANT_KEY.search(name):
                    for tool in _tool_list(value):
                        granted.setdefault(_literal(tool), name)
            both = sorted(set(granted) & set(denied))
            if both:
                report.add(Finding(
                    "S01", ERROR, "tool-granted-and-denied",
                    "The same entry appears verbatim in a grant list and a denial list. One of "
                    "the two is not doing what its author reads it as doing. Which side wins is "
                    "not something this check measures; list a tool in one place.",
                    file=path, line=1, tools=both,
                    granted_in=sorted({granted[t] for t in both}),
                    denied_in=sorted({denied[t] for t in both})))

        # S03 — an execution marker inside a fenced example, in a component body.
        in_fence, mark = False, None
        for n, line in enumerate(lines[body_start:], start=body_start + 1):
            stripped = line.strip()
            fence = FENCE.match(stripped)
            if fence:
                if not in_fence:
                    in_fence, mark = True, fence.group(1)[0]
                elif stripped[0] == mark:
                    in_fence, mark = False, None
                continue
            if in_fence and EXEC_MARKER.search(line):
                report.add(Finding(
                    "S03", ERROR, "execution-line-in-example",
                    "An execution marker inside a fenced example, in a file that carries "
                    "frontmatter and so is loaded as a component. A fence stops a person "
                    "expecting the line to run; one shipped skill is uninvocable because of "
                    "exactly this shape.",
                    file=path, line=n, excerpt=line.strip()[:120]))
