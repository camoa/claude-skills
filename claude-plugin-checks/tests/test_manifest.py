"""Reading a manifest, and deciding which of its strings name a path."""

import os

from cpc import manifest


def test_the_path_forms_that_used_to_be_invisible(tmp_path):
    # An absolute path and the plugin-root placeholder were both skipped by the
    # old "starts with ./" test, so a component pointed at /etc/passwd reported
    # clean. These say they are paths on their own, so a missing target is a
    # real finding without asking the filesystem.
    for value in ("./a.json", "../b", "/etc/passwd",
                  "${CLAUDE_PLUGIN_ROOT}/c.json", "$CLAUDE_PLUGIN_ROOT/d.json"):
        assert manifest.looks_like_path(value), value


def test_a_bare_string_does_not_claim_to_be_a_path():
    # `camoa/claude-skills` is a repository shorthand and `config/e.json` might
    # be a path; neither says so on its own. declared_paths settles it by asking
    # whether anything is there. Treating every slash-bearing string as a path
    # reported a repository field and a homepage as missing components.
    for value in ("MIT", "1.0.0", "", "   ", "https://example.com/a",
                  "camoa/claude-skills", "ci/cd", "next.js", "commands",
                  "Audits with deeper SOLID/DRY analysis and more",
                  "a description mentioning commands/ somewhere"):
        assert not manifest.looks_like_path(value), value


def test_two_bare_shapes_do_say_they_are_paths():
    # A trailing separator and a last segment with an extension are
    # unambiguous, so a missing target is still a real finding. Accepting only
    # the explicit prefixes made a manifest declaring `agents/` and
    # `config/mcp.json`, with neither present, report clean.
    for value in ("agents/", "config/mcp.json", "hooks/hooks.json"):
        assert manifest.looks_like_path(value), value


def test_a_repository_shorthand_is_not_reported_as_a_missing_component(tmp_path):
    fields = {f for f, _, _ in manifest.declared_paths(
        {"repository": "camoa/claude-skills",
         "keywords": "ci/cd",
         "outputStyles": "/etc/passwd"}, str(tmp_path))}
    assert fields == {"outputStyles"}


def test_a_bare_missing_directory_is_the_documented_blind_spot(tmp_path):
    # `commands` with nothing there is indistinguishable from a keyword, so it
    # is not reported. Named here so the limit is deliberate rather than
    # discovered later.
    assert manifest.declared_paths({"commands": "commands"}, str(tmp_path)) == []


def test_the_placeholder_is_expanded_against_the_plugin_root():
    assert manifest.resolve("/p", "${CLAUDE_PLUGIN_ROOT}/c.json") == "/p/c.json"
    assert manifest.resolve("/p", "./c.json") == "/p/c.json"
    assert manifest.resolve("/p", "/etc/passwd") == "/etc/passwd"


def test_containment():
    assert manifest.inside("/p", "/p/a")
    assert manifest.inside("/p", "/p")
    assert not manifest.inside("/p", "/etc/passwd")
    assert not manifest.inside("/p", "/ps/a")


def test_existence_settles_a_bare_name(tmp_path):
    os.makedirs(tmp_path / "commands")
    fields = {field for field, _, _ in manifest.declared_paths(
        {"commands": "commands", "license": "MIT"}, str(tmp_path))}
    assert fields == {"commands"}


def test_a_repeated_key_is_visible_though_json_hides_it(tmp_path):
    p = tmp_path / "m.json"
    p.write_text('{"a":1,"a":2}')
    data, err, dups = manifest.load_json(str(p))
    assert err is None and dups == ["a"] and data == {"a": 2}


def test_a_broken_file_reports_the_reason(tmp_path):
    p = tmp_path / "m.json"
    p.write_text('{"a":')
    data, err, dups = manifest.load_json(str(p))
    assert data is None and err


def test_every_string_is_walked_with_its_field_path():
    found = dict(manifest.walk_strings({"a": {"b": ["x", "y"]}}))
    assert found == {"a.b.0": "x", "a.b.1": "y"}
