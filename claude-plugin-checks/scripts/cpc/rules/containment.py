"""What must not reach a public marketplace: home paths, credentials, addresses.

Three defects this module was rewritten to remove, each of which reported a
clean scan over a real leak:

  * the old version shelled out to grep and split each row on ":", so a colon
    anywhere in the checkout path produced a non-numeric line number, the record
    was dropped, and the scan finished clean. There is no row splitting now.
  * it took only the first match on a line and then skipped the line if that one
    match was a documentation placeholder, so a tutorial saying "replace the
    example home path with your own" hid the real username in the second half of
    the line. Every match on the line is considered now, not the first.
  * its boundary class excluded "/", so file:///home/<user>/... never matched.
"""

import re

from .. import walk
from ..result import ERROR, WARN, Finding

PREFIX = "P"
NAME = "containment"

# Facts about the world, not about Claude Code: these prefixes belong to the
# vendors who mint them.
SECRET_PATTERNS = (
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"ghp_[A-Za-z0-9]{36}",
    r"github_pat_[A-Za-z0-9_]{40,}",
    r"glpat-[A-Za-z0-9_-]{20,}",
    r"sk-ant-[A-Za-z0-9_-]{20,}",
    r"sk-[A-Za-z0-9]{32,}",
    r"(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}",
    r"whsec_[A-Za-z0-9]{16,}",
    # AWS prints AKIAIOSFODNN7EXAMPLE in its own documentation, and the EXAMPLE
    # suffix is the convention it uses for one. Reporting it turns every
    # tutorial quoting the docs into an error.
    # AWS writes EXAMPLE at the END of the keys in its own documentation, so the
    # exemption has to look there. An earlier lookahead checked the first five
    # characters instead, which let one documented key through and wrongly
    # exempted a real-shaped key that merely began with EXAMPLE.
    r"AKIA(?![0-9A-Z]{9}EXAMPLE\b)[0-9A-Z]{16}",
    r"xox[baprs]-[A-Za-z0-9-]{10,}",
    r"AIza[0-9A-Za-z_-]{35}",
)
SECRET_RE = re.compile("|".join(SECRET_PATTERNS))

# The match has to start a path, not sit in the middle of one. The old version
# enforced that with a character class that excluded "/", which also made
# file:///home/<user>/... invisible. This asks the question properly: what comes
# before has to be a separator, and a "/" only counts when it is the "//" of a
# scheme. So a file:// URL naming a real home directory matches, and an ordinary
# path ending in .../home/screen.snap does not.
HOME_RE = re.compile(r"(/home/|/Users/)([A-Za-z0-9._-]+)")
SEGMENT_CHAR = re.compile(r"[A-Za-z0-9._-]")


def _starts_a_path(line, at):
    """Is the match at `at` the beginning of a path, rather than inside one?

    This also settles web URLs without a separate test: in
    https://example.com/home/x the character before /home/ belongs to the host,
    so the match is inside a longer name and never starts a path. An explicit
    URL check used to sit beside this one and could not change any outcome.
    """
    if at == 0:
        return True
    prev = line[at - 1]
    if SEGMENT_CHAR.match(prev):
        return False          # part of a longer name: snapshots/home/... has "ts" here
    if prev != "/":
        return True           # a space, quote, bracket, equals: a real boundary
    # A slash before it counts only as the second slash of a scheme.
    return at >= 2 and line[at - 2] == "/"
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")

PLACEHOLDER_USER = re.compile(r"^(user|username|youruser|your-user|example|me|name|someone|\.+)$", re.I)
EXEMPT_EMAIL = re.compile(
    r"@(example\.(com|org|net)|domain\.com|email\.com|company\.com|test\.com)$"
    r"|@[A-Za-z0-9.-]+\.(test|invalid|example|localhost)$"
    r"|^git@|^noreply@anthropic\.com$", re.I)

MANIFEST_NAMES = ("plugin.json", "marketplace.json")


def _load_allow(root, report):
    import os
    path = os.path.join(root, ".containment-allow")
    if not os.path.isfile(path):
        return []
    text = walk.read_text(path, report)
    if text is None:
        return []
    out = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            out.append(re.compile(line))
        except re.error:
            report.cannot_look(path, "allowlist pattern is not a valid regex: %s" % line)
    return out


def run(root, report):
    import os
    allow = _load_allow(root, report)

    def allowed(probe):
        return any(p.search(probe) for p in allow)

    if allow:
        report.count("allow_patterns", len(allow))

    for path in walk.files(root, report):
        if walk.is_probably_binary(path):
            # Not a subject for a text rule. Counted rather than reported as a
            # blind spot, because an image in a plugin is normal and turning
            # every one of them into "could not look" would make a plugin with
            # a screenshot permanently unclean. The number stays visible.
            report.count("binary_files_skipped")
            continue
        text = walk.read_text(path, report)
        if text is None:
            continue
        report.subjects += 1
        rel = os.path.relpath(path, root)
        base = os.path.basename(path)

        for n, line in enumerate(text.splitlines(), start=1):
            probe = "%s:%d:%s" % (rel, n, line)
            if allowed(probe):
                continue
            excerpt = line.strip()[:120]

            # Every match on the line, not the first. A placeholder earlier on
            # the line must not shield a real path later on it.
            for m in HOME_RE.finditer(line):
                user = m.group(2)
                if PLACEHOLDER_USER.match(user):
                    continue
                if not _starts_a_path(line, m.start()):
                    continue
                report.add(Finding(
                    "P01", ERROR, "absolute-home-path",
                    "An absolute home path carries a username on disk. It breaks on every "
                    "other machine and says who built the plugin. Use ${CLAUDE_PLUGIN_ROOT}, "
                    "~/ or $HOME.",
                    file=path, line=n, match=m.group(0), excerpt=excerpt))
                break  # one finding per line is enough to act on

            for m in SECRET_RE.finditer(line):
                token = m.group(0)
                report.add(Finding(
                    "P02", ERROR, "secret-token",
                    "This looks like a credential. Never commit one to a published plugin; "
                    "rotate it and read it from the environment instead.",
                    file=path, line=n,
                    match="%s…[redacted %d chars]" % (token[:4], len(token)),
                    excerpt="%s…[redacted]" % token[:4]))
                break

            if base in MANIFEST_NAMES:
                continue  # author and owner addresses belong in a manifest
            for m in EMAIL_RE.finditer(line):
                address = m.group(0)
                if EXEMPT_EMAIL.search(address):
                    continue
                report.add(Finding(
                    "P03", WARN, "personal-email",
                    "A personal address outside an author or owner manifest field. Confirm it "
                    "is meant to ship publicly; use a no-reply or example address otherwise.",
                    file=path, line=n, match=address, excerpt=address))
                break
