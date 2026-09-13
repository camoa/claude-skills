import os
import sys

import pytest

SCRIPTS = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "scripts")
if SCRIPTS not in sys.path:
    sys.path.insert(0, SCRIPTS)

from cpc.result import Report  # noqa: E402


@pytest.fixture
def plugin(tmp_path):
    """Build a plugin tree from a {relative path: contents} mapping."""

    def build(files, manifest=None):
        if manifest is not None:
            import json
            d = tmp_path / ".claude-plugin"
            d.mkdir(parents=True, exist_ok=True)
            (d / "plugin.json").write_text(
                manifest if isinstance(manifest, str) else json.dumps(manifest))
        for rel, body in (files or {}).items():
            target = tmp_path / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body)
        return str(tmp_path)

    return build


@pytest.fixture
def run_rule():
    """Run one rule module over a root and hand back its report."""

    def go(module, root, strict=False):
        report = Report(os.path.realpath(root), strict)
        module.run(os.path.realpath(root), report)
        return report

    return go


def rules_fired(report):
    return sorted({f.rule for f in report.findings})
