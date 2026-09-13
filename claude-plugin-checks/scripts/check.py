#!/usr/bin/env python3
"""One entry point over the rule modules in cpc/rules.

    check.py <plugin-dir> [--strict] [--only P,E01,S] [--json]

Exit codes are the ones in cpc.result and mean the same thing everywhere:

    0  everything was examined and everything was clean
    1  at least one finding (warnings count only under --strict)
    2  the arguments were wrong
    3  something could not be looked at, so the run is not a clean result

Three is not a soft pass. A check that could not look must never report that it
looked, so a run that skipped an unreadable directory, examined nothing, or
found no subject at all lands here rather than on zero.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

from cpc import rules  # noqa: E402
from cpc.result import EXIT_USAGE, Report, merge  # noqa: E402


def parse_args(argv):
    p = argparse.ArgumentParser(prog="check.py", add_help=True,
                                description="Check a Claude Code plugin.")
    p.add_argument("plugin_dir", help="the plugin directory to check")
    p.add_argument("--strict", action="store_true",
                   help="treat warnings as failures too")
    p.add_argument("--only", default="",
                   help="comma-separated rule prefixes or ids, e.g. P or E01,S")
    p.add_argument("--json", action="store_true",
                   help="print only the JSON result, with no human summary")
    return p.parse_args(argv)


def human(payload):
    out = []
    out.append("%s  %s" % (payload["result"], payload["dir"]))
    for f in payload["findings"]:
        where = f["file"] or f.get("declared") or "(manifest)"
        line = ":%s" % f["line"] if f.get("line") else ""
        out.append("  %-5s %-8s %s%s" % (f["rule"], f["severity"], where, line))
        if f.get("excerpt"):
            # The offending line itself, so a person can act without opening the
            # file. It is a quotation from a file this tool did not write, which
            # is why cpc.result.clean strips control characters from it before
            # it reaches a terminal.
            out.append("        > %s" % f["excerpt"])
        out.append("        %s" % f["note"])
    for b in payload["could_not_look"]:
        out.append("  could not look: %s (%s)" % (b["where"], b["reason"]))
    out.append("  %d examined, %d error(s), %d warning(s), %d not looked at"
               % (payload["subjects"], payload["errors"], payload["warnings"],
                  len(payload["could_not_look"])))
    return "\n".join(out)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)

    root = args.plugin_dir
    if not os.path.isdir(root):
        print(json.dumps({"schema_version": "2.0", "dir": root,
                          "error": "plugin directory not found",
                          "findings": [], "errors": 0, "warnings": 0,
                          "result": "ERROR"}))
        print("check: plugin directory not found: %s" % root, file=sys.stderr)
        return EXIT_USAGE
    root = os.path.realpath(root)

    only = [t.strip() for t in args.only.split(",") if t.strip()]
    try:
        selected = rules.select(only)
    except ValueError as exc:
        print("check: %s" % exc, file=sys.stderr)
        return EXIT_USAGE

    reports = []
    for module in selected:
        sub = Report(root, args.strict)
        try:
            module.run(root, sub)
        except ImportError as exc:
            # A missing dependency is a blind spot, never a pass.
            sub.cannot_look(module.NAME, "a dependency is missing: %s" % exc)
        except Exception as exc:  # noqa: BLE001 - one broken rule must not hide the rest
            sub.cannot_look(module.NAME, "the rule failed to run: %r" % exc)
        reports.append(sub)

    combined = merge(reports, root, args.strict)
    combined.count("rules_run", len(selected))
    payload = combined.as_dict()

    print(json.dumps(payload, ensure_ascii=False))
    if not args.json:
        print(human(payload), file=sys.stderr)
    return combined.exit_code


if __name__ == "__main__":
    sys.exit(main())
