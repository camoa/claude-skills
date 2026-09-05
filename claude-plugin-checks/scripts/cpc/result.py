"""The output shape, the outcome vocabulary and the exit codes, in one place.

Every check reports three outcomes, not two. `unchecked` means the check could
not look: a missing dependency, an unreadable directory, an empty subject set.
It is never folded into a pass, because a false all-clear is worse than silence.
"""

PASS = "PASS"
FAIL = "FAIL"
UNCHECKED = "UNCHECKED"

ERROR = "error"
WARN = "warn"

# Exit codes, shared by the single entry point and by anything wrapping it.
EXIT_CLEAN = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_UNCHECKED = 3


def clean(value):
    """Text taken from a scanned file, safe to print to a terminal.

    An excerpt is a quotation from a file this tool did not write, and the
    readable summary goes to a terminal. A raw escape sequence in there can move
    the cursor, recolour the screen or hide the rest of a line, so a plugin could
    shape what a person sees about itself. Stripping the control characters
    removes that.

    NOT for JSON validity: `json.dumps` escapes control characters correctly and
    they round-trip. An earlier version of this docstring claimed otherwise and
    was wrong, and the test that guarded it asserted only that this function does
    what it does.
    """
    if not isinstance(value, str):
        return value
    return "".join(c if c >= " " or c == "\t" else " " for c in value)


class Finding:
    """One defect, at one place, with the reason it matters."""

    def __init__(self, rule, severity, kind, note, file=None, line=None, **extra):
        if severity not in (ERROR, WARN):
            raise ValueError("severity must be %r or %r, got %r" % (ERROR, WARN, severity))
        self.rule = rule
        self.severity = severity
        self.kind = kind
        self.note = note
        self.file = file
        self.line = line
        self.extra = {k: clean(v) for k, v in extra.items()}

    def as_dict(self, root=None):
        import os
        out = {
            "rule": self.rule,
            "severity": self.severity,
            "kind": self.kind,
            "file": None,
            "line": self.line,
            "note": self.note,
        }
        if self.file is not None:
            out["file"] = os.path.relpath(self.file, root) if root else self.file
        out.update(self.extra)
        return {k: clean(v) for k, v in out.items()}


class Blind:
    """A place the check could not look, and why.

    Carrying these is the whole point of the three-outcome vocabulary: a rule
    that skipped half a tree because a directory was unreadable has not passed.
    """

    def __init__(self, where, reason):
        self.where = where
        self.reason = reason

    def as_dict(self):
        return {"where": self.where, "reason": self.reason}


class Report:
    """What one run of one or more rules produced."""

    def __init__(self, root, strict=False):
        self.root = root
        self.strict = strict
        self.findings = []
        self.blind = []
        self.subjects = 0          # how many things were actually examined
        self.counters = {}         # rule-module specific, surfaced for honesty

    def add(self, finding):
        self.findings.append(finding)

    def cannot_look(self, where, reason):
        self.blind.append(Blind(where, reason))

    def count(self, name, n=1):
        self.counters[name] = self.counters.get(name, 0) + n

    @property
    def errors(self):
        return sum(1 for f in self.findings if f.severity == ERROR)

    @property
    def warnings(self):
        return sum(1 for f in self.findings if f.severity == WARN)

    @property
    def result(self):
        if self.errors or (self.strict and self.warnings):
            return FAIL
        # Nothing examined is not a clean bill of health, and neither is a
        # verdict gathered from a tree that was only partly read. The second
        # test used to be "blind AND no findings", which meant one warning
        # anywhere turned an unreadable directory holding a credential into a
        # pass. A blind spot outranks a clean-looking remainder, always.
        if self.subjects == 0 or self.blind:
            return UNCHECKED
        return PASS

    @property
    def exit_code(self):
        r = self.result
        if r == FAIL:
            return EXIT_FINDING
        if r == UNCHECKED:
            return EXIT_UNCHECKED
        return EXIT_CLEAN

    def as_dict(self):
        out = {
            "schema_version": "2.0",
            "dir": self.root,
            "strict": self.strict,
            "subjects": self.subjects,
            "findings": [f.as_dict(self.root) for f in self.findings],
            "errors": self.errors,
            "warnings": self.warnings,
            "could_not_look": [b.as_dict() for b in self.blind],
            "result": self.result,
        }
        if self.counters:
            out["counters"] = dict(sorted(self.counters.items()))
        return out


def merge(reports, root, strict=False):
    """Fold per-rule reports into one. Used by the single entry point."""
    combined = Report(root, strict)
    seen = set()
    for r in reports:
        combined.findings.extend(r.findings)
        for b in r.blind:
            # Every rule walks through the same shared walk, so one unreadable
            # directory is reported once per rule. Report the place, not the
            # number of rules that tripped over it.
            key = (b.where, b.reason)
            if key not in seen:
                seen.add(key)
                combined.blind.append(b)
        combined.subjects += r.subjects
        for k, v in r.counters.items():
            combined.count(k, v)
    return combined
