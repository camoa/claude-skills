"""Component files the first-party validator declares and never opens."""

from conftest import rules_fired
from cpc.rules import external


def test_an_absolute_path_outside_the_plugin_is_reported(plugin, run_rule):
    # The fatal one. The old version collected a path only when the string
    # started with "./", so this reported clean and every rule below it fired
    # on nothing across all eight plugins in this repository.
    root = plugin({}, manifest={"name": "x", "version": "1.0.0",
                                "outputStyles": "/etc/passwd"})
    assert "E01" in rules_fired(run_rule(external, root))


def test_the_plugin_root_placeholder_is_expanded_before_resolving(plugin, run_rule):
    # The form this plugin's own containment check tells authors to use.
    root = plugin({}, manifest={"name": "x", "version": "1.0.0",
                                "mcpServers": "${CLAUDE_PLUGIN_ROOT}/config/gone.json"})
    assert "E02" in rules_fired(run_rule(external, root))


def test_a_relative_escape_is_reported(plugin, run_rule):
    root = plugin({}, manifest={"name": "x", "version": "1.0.0",
                                "mcpServers": "./../outside/mcp.json"})
    assert "E01" in rules_fired(run_rule(external, root))


def test_a_path_inside_the_plugin_is_silent(plugin, run_rule):
    root = plugin({".mcp.json": '{"mcpServers":{"a":{"command":"x"}}}'},
                  manifest={"name": "x", "version": "1.0.0", "mcpServers": "./.mcp.json"})
    assert run_rule(external, root).findings == []


def test_prose_containing_a_slash_is_not_a_declared_path(plugin, run_rule):
    # A plugin description reading "deeper SOLID/DRY analysis" was collected as
    # a component path and reported missing. A path has no spaces in it.
    root = plugin({}, manifest={"name": "x", "version": "1.0.0",
                                "description": "Audits with deeper SOLID/DRY analysis and more"})
    assert run_rule(external, root).findings == []


def test_a_bare_directory_name_counts_when_something_is_there(plugin, run_rule):
    root = plugin({"commands/a.md": "---\nname: a\n---\nbody\n"},
                  manifest={"name": "x", "version": "1.0.0",
                            "commands": "commands", "license": "MIT"})
    report = run_rule(external, root)
    assert report.counters["declared_paths"] == 1      # commands, not MIT
    assert report.findings == []


def test_a_file_that_does_not_parse_is_reported(plugin, run_rule):
    root = plugin({"config/m.json": '[{"name":"cpu",}]'},
                  manifest={"name": "x", "version": "1.0.0",
                            "experimental": {"monitors": "./config/m.json"}})
    assert "E03" in rules_fired(run_rule(external, root))


def test_a_manifest_that_does_not_parse_is_reported(plugin, run_rule):
    root = plugin({}, manifest='{"name":"x",')
    assert "E03" in rules_fired(run_rule(external, root))


def test_a_repeated_key_is_reported_though_json_hides_it(plugin, run_rule):
    # json.load keeps the last one and discards the rest with no message.
    root = plugin({".mcp.json": '{"mcpServers":{"a":{}},"mcpServers":{"b":{}}}'},
                  manifest={"name": "x", "version": "1.0.0"})
    assert "E04" in rules_fired(run_rule(external, root))


def test_colliding_identifiers_are_reported(plugin, run_rule):
    # The reproduction this rule exists for: inline, the first-party validator
    # says "Found 1 error"; in an external file it returns 0.
    root = plugin({"config/monitors.json":
                   '[{"name":"cpu"},{"name":"cpu"},{"name":"disk"}]'},
                  manifest={"name": "x", "version": "1.0.0",
                            "experimental": {"monitors": "./config/monitors.json"}})
    report = run_rule(external, root)
    assert "E06" in rules_fired(report)
    assert [f.extra["duplicates"] for f in report.findings if f.rule == "E06"] == [["cpu"]]


def test_distinct_identifiers_are_silent(plugin, run_rule):
    root = plugin({"config/monitors.json": '[{"name":"cpu"},{"name":"mem"}]'},
                  manifest={"name": "x", "version": "1.0.0",
                            "experimental": {"monitors": "./config/monitors.json"}})
    assert run_rule(external, root).findings == []


def test_a_declared_empty_container_warns_but_a_conventional_one_does_not(plugin, run_rule):
    declared = plugin({"config/m.json": "[]"},
                      manifest={"name": "x", "version": "1.0.0",
                                "experimental": {"monitors": "./config/m.json"}})
    assert rules_fired(run_rule(external, declared)) == ["E05"]

    # Nothing was promised about a file the manifest never mentioned.
    incidental = plugin({".mcp.json": "{}"}, manifest={"name": "y", "version": "1.0.0"})
    assert run_rule(external, incidental).findings == []


def test_a_closed_fence_is_silent(plugin, run_rule):
    root = plugin({"commands/fine.md": "---\nname: fine\n---\nbody\n"},
                  manifest={"name": "x", "version": "1.0.0", "commands": "./commands"})
    assert run_rule(external, root).findings == []


def test_no_manifest_is_not_a_pass(plugin, run_rule):
    root = plugin({"stray.md": "hello\n"})
    report = run_rule(external, root)
    assert report.result == "UNCHECKED"
    assert report.blind


def test_a_manifest_declaring_nothing_is_still_examined(plugin, run_rule):
    # The manifest itself is a subject, so this is a real pass rather than the
    # UNCHECKED the old version returned for a plugin with no component files.
    root = plugin({}, manifest={"name": "x", "version": "1.0.0"})
    report = run_rule(external, root)
    assert report.subjects >= 1
    assert report.result == "PASS"
