"""One tree walk, one exclusion list, one place that knows a read can fail.

Every rule module used to walk the tree itself, which is how the same defect —
a directory that cannot be read silently shrinking what gets checked — ended up
present three times. There is one walk now, and it reports what it could not
open instead of quietly returning fewer files.
"""

import os

PRUNE = {".git", "node_modules", ".claude-telemetry", ".worktrees", "__pycache__"}


def files(root, report, suffixes=None, prune=None):
    """Every file under root, with unreadable directories reported, not dropped.

    `report` is a cpc.result.Report. A directory os.walk cannot descend into
    becomes a `could_not_look` entry, so the outcome can never be a clean pass
    over a tree that was only partly read.
    """
    skip = PRUNE if prune is None else set(prune)
    found = []

    def on_error(exc):
        where = getattr(exc, "filename", None) or str(exc)
        report.cannot_look(where, "directory could not be read: %s" % exc.strerror
                           if hasattr(exc, "strerror") else str(exc))

    # followlinks=True because a vendored or shared directory reached by symlink
    # is ordinary plugin layout, and os.walk's default silently contributed
    # nothing for it: no files, no counter, no blind spot. `seen` keeps a
    # symlink loop from walking forever.
    seen = set()
    for base, dirnames, filenames in os.walk(root, onerror=on_error, followlinks=True):
        real = os.path.realpath(base)
        if real in seen:
            dirnames[:] = []
            continue
        seen.add(real)
        # Pruning children by realpath as well would be dead code: os.walk
        # descends into each one and the check at the top of this loop catches a
        # target already reached by another name. Removing that second guard
        # changes no outcome and no test, which is how it was found.
        dirnames[:] = [d for d in dirnames if d not in skip]
        for name in filenames:
            if suffixes and not any(name.endswith(s) for s in suffixes):
                continue
            found.append(os.path.join(base, name))
    return sorted(set(found))


def read_text(path, report):
    """File contents, or None with the reason recorded.

    A file that cannot be decoded is not the same as a file with nothing in it,
    and the caller must not be able to confuse the two.
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read()
    except UnicodeDecodeError:
        # Mostly text with some undecodable bytes in it. Read it anyway with the
        # bad bytes replaced, so one stray byte cannot hide the rest of a file.
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except OSError as exc:
            report.cannot_look(path, "file could not be read: %s" % exc)
            return None
    except OSError as exc:
        report.cannot_look(path, "file could not be read: %s" % exc)
        return None


def is_probably_binary(path):
    """Binary enough that scanning it for text would be noise, not a leak check.

    Decoding settles it, not counting bytes. Two earlier versions got this
    wrong in opposite directions: one treated a single NUL as proof of binary,
    so a markdown file with one stray byte was skipped whole and a credential
    three lines later went unseen; the next counted how many BYTES were ASCII
    printable, which scores ordinary UTF-8 prose as binary. A page of
    box-drawing characters came out at 0.53 and was excluded from the leak scan
    along with eight other plain-text files.

    So: if the sample decodes as text it is text, whatever its bytes look like.
    Only something that does not decode, or decodes into mostly control
    characters, is binary.
    """
    try:
        with open(path, "rb") as fh:
            sample = fh.read(8192)
    except OSError:
        return False
    if not sample:
        return False
    # The read can land mid-character, which is not evidence of anything.
    for trim in range(0, 4):
        head = sample[:len(sample) - trim] if trim else sample
        try:
            text = head.decode("utf-8")
            break
        except UnicodeDecodeError:
            text = None
    if text is None:
        return True
    if not text:
        return False
    printable = sum(1 for c in text if c in "\t\n\r" or c >= " ")
    return (printable / len(text)) < 0.85
