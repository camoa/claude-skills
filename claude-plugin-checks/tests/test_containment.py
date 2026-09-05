"""Leak detection. Most of these guard a defect that shipped a clean scan."""

from conftest import rules_fired
from cpc.rules import containment

# Leak-shaped literals are assembled at import time so this file does not itself
# contain a token the scan would flag when run over its own plugin.
AWS = "AKIA" + "ABCDEFGHIJKLMNOP"
GH = "ghp_" + "a" * 36
STRIPE = "sk_" + "live_" + "b" * 24
WEBHOOK = "whsec_" + "c" * 24
PUBLISHABLE = "pk_" + "live_" + "d" * 24
REAL_HOME = "/home/" + "carlos"
MAC_HOME = "/Users/" + "jane"


def test_a_colon_in_the_path_does_not_silence_the_scan(plugin, run_rule):
    # The worst defect the review found. The old version shelled out to grep and
    # split each row on ":", so a colon anywhere in the path produced a
    # non-numeric line number, jq errored, the record was dropped, and the scan
    # reported PASS over both a home path and an AWS key.
    root = plugin({"we:ird/a.md": "home is %s/here\n%s\n" % (REAL_HOME, AWS)})
    report = run_rule(containment, root)
    assert rules_fired(report) == ["P01", "P02"]


def test_a_placeholder_earlier_on_the_line_does_not_hide_a_real_path(plugin, run_rule):
    # The old version took the first match per line and skipped the line when
    # that one match was a placeholder. A tutorial line has exactly this shape.
    root = plugin({"doc.md": "cp /home/user/a.txt %s/b.txt\n" % REAL_HOME})
    report = run_rule(containment, root)
    assert [f.extra["match"] for f in report.findings] == [REAL_HOME]


def test_a_file_url_does_not_hide_a_home_path(plugin, run_rule):
    # The old boundary class excluded "/", so file:// was invisible.
    root = plugin({"doc.md": "See file://%s/secret/notes.txt\n" % REAL_HOME})
    assert rules_fired(run_rule(containment, root)) == ["P01"]


def test_a_path_segment_called_home_is_not_a_home_path(plugin, run_rule):
    # The regression the file:// fix introduced: dropping the boundary entirely
    # made snapshots/home/screen.snap match. Caught by running against a real
    # plugin, not by a spec, which is why it is a spec now.
    root = plugin({"doc.md": 'diff snapshots/home/screen.snap and x/home/y\n'})
    assert run_rule(containment, root).findings == []


def test_a_web_url_containing_home_is_not_a_home_path(plugin, run_rule):
    root = plugin({"doc.md": "Docs at https://example.com/home/index.html\n"})
    assert run_rule(containment, root).findings == []


def test_a_placeholder_username_alone_is_not_reported(plugin, run_rule):
    root = plugin({"doc.md": "Put it in /home/user/ or /home/username/\n"})
    assert run_rule(containment, root).findings == []


def test_a_macos_home_path_is_reported(plugin, run_rule):
    root = plugin({"doc.md": "path: %s/foo\n" % MAC_HOME})
    assert rules_fired(run_rule(containment, root)) == ["P01"]


def test_secret_prefixes_are_reported_and_redacted(plugin, run_rule):
    for name, secret in (("a", AWS), ("b", GH), ("c", STRIPE), ("d", WEBHOOK)):
        root = plugin({"%s.sh" % name: "export KEY=%s\n" % secret})
        report = run_rule(containment, root)
        assert rules_fired(report) == ["P02"], secret[:6]
        shown = report.findings[0].extra["match"]
        assert secret not in shown and "redacted" in shown


def test_a_publishable_key_is_not_a_secret(plugin, run_rule):
    root = plugin({"doc.md": "Browser key: %s\n" % PUBLISHABLE})
    assert run_rule(containment, root).findings == []


def test_a_personal_address_warns_but_a_reserved_one_does_not(plugin, run_rule):
    root = plugin({"doc.md": "contact someone.real" + "@gmail.com\n"})
    report = run_rule(containment, root)
    assert rules_fired(report) == ["P03"]
    assert report.result == "PASS"           # a warning alone is not a failure
    assert run_rule(containment, root, strict=True).result == "FAIL"

    # RFC 2606 reserves these for documentation. A spec using one is not leaking.
    quiet = plugin({"doc.md": "git config user.email spec@example.invalid\n"
                              "also t@t.test and x@example.com\n"})
    assert run_rule(containment, quiet).findings == []


def test_an_author_address_in_a_manifest_is_intentional(plugin, run_rule):
    root = plugin({}, manifest={"name": "x", "version": "1.0.0",
                                "author": {"email": "real.person" + "@gmail.com"}})
    assert run_rule(containment, root).findings == []


def test_the_allowlist_silences_a_finding_and_says_how_many_patterns(plugin, run_rule):
    root = plugin({"doc.md": "path %s/x\n" % REAL_HOME,
                   ".containment-allow": "# a comment\ndoc\\.md\n"})
    report = run_rule(containment, root)
    assert report.findings == []
    assert report.counters["allow_patterns"] == 1


def test_a_broken_allowlist_pattern_is_reported_not_ignored(plugin, run_rule):
    root = plugin({"doc.md": "clean\n", ".containment-allow": "[unclosed\n"})
    report = run_rule(containment, root)
    assert report.blind and "not a valid regex" in report.blind[0].reason


def test_a_binary_file_is_counted_rather_than_called_a_blind_spot(plugin, run_rule):
    # Reporting every image as "could not look" made any plugin with a
    # screenshot permanently unclean. The number stays visible instead.
    root = plugin({"doc.md": "clean\n"})
    with open(root + "/logo.png", "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n\x00\x00binary")
    report = run_rule(containment, root)
    assert report.blind == []
    assert report.counters["binary_files_skipped"] == 1
    assert report.result == "PASS"


def test_an_empty_tree_is_not_a_pass(plugin, run_rule):
    root = plugin({})
    assert run_rule(containment, root).result == "UNCHECKED"


def test_a_nul_byte_early_does_not_hide_a_credential_later(plugin, run_rule):
    root = plugin({"skills/s/SKILL.md": "---\nname: s\ndescription: x\n---\nbody\n"})
    with open(root + "/skills/s/notes.md", "wb") as fh:
        fh.write(b"note\x00\nexport AWS=" + AWS.encode() + b"\n")
    report = run_rule(containment, root)
    assert rules_fired(report) == ["P02"]


def test_the_documented_aws_example_key_is_not_a_leak(plugin, run_rule):
    # The key AWS prints in its own documentation. Reporting it turns every
    # tutorial that quotes the docs into an error.
    root = plugin({"docs/setup.md": "Use AKIAIOSFODNN7EXAMPLE in the example.\n"})
    assert run_rule(containment, root).findings == []


def test_the_documented_aws_keys_are_exempt_by_suffix_not_by_prefix(plugin, run_rule):
    # AWS writes EXAMPLE at the END of the keys in its docs. An earlier lookahead
    # checked the first five characters, so one documented key was still
    # reported and a real-shaped key beginning with EXAMPLE was wrongly exempt.
    for documented in ("AKIAIOSFODNN7EXAMPLE", "AKIAI44QH8DHBEXAMPLE"):
        root = plugin({"docs/setup.md": "Use %s in the example.\n" % documented})
        assert run_rule(containment, root).findings == [], documented

    real_shaped = "AKIA" + "EXAMPLEKEY123456"
    root = plugin({"scripts/deploy.sh": "export KEY=%s\n" % real_shaped})
    assert rules_fired(run_rule(containment, root)) == ["P02"]


def test_utf8_prose_is_scanned_rather_than_skipped_as_binary(plugin, run_rule):
    # A page of box-drawing characters scored 0.53 on a byte-level printable
    # ratio and was excluded from the scan along with eight other plain-text
    # files. Decoding settles it now, not counting bytes.
    art = "\n".join("│  " + "─" * 40 + "  │" for _ in range(40))
    root = plugin({"WORKFLOW.md": art + "\nexport KEY=%s\n" % AWS})
    report = run_rule(containment, root)
    assert rules_fired(report) == ["P02"]
    assert report.counters.get("binary_files_skipped", 0) == 0
