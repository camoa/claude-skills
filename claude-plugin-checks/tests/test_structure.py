"""A component file contradicting itself."""

from conftest import rules_fired
from cpc.rules import structure

# Built at import time so this file does not carry the marker it asserts on.
EXEC = "!" + "`npm test $1`"


def test_the_same_entry_granted_and_denied_is_reported(plugin, run_rule):
    root = plugin({"agents/a.md":
                   "---\nname: a\ntools: [Read, Write]\ndisallowedTools: [Write]\n---\nbody\n"})
    report = run_rule(structure, root)
    assert rules_fired(report) == ["S01"]
    assert report.findings[0].extra["tools"] == ["Write"]


def test_the_kebab_case_spelling_reaches_the_same_rule(plugin, run_rule):
    root = plugin({"skills/s/SKILL.md":
                   "---\nname: s\ndescription: x\nallowed-tools: Read, Bash\n"
                   "disallowed-tools: Bash\n---\nbody\n"})
    assert rules_fired(run_rule(structure, root)) == ["S01"]


def test_a_grant_field_nobody_has_invented_yet_still_matches(plugin, run_rule):
    # The grant side used to be a closed roster of four spellings while the
    # comment above it claimed matching was by shape. Renaming the field
    # upstream would have silenced the rule.
    root = plugin({"agents/a.md":
                   "---\nname: a\npermittedTools: [Write]\ndisallowedTools: [Write]\n---\nbody\n"})
    assert rules_fired(run_rule(structure, root)) == ["S01"]


def test_a_bare_grant_with_a_scoped_denial_is_not_reported(plugin, run_rule):
    # How an author writes "Bash, but not rm". Which side wins is a fact about
    # Claude Code nobody here has measured, and an earlier version called two
    # working agents in this marketplace broken by guessing at it.
    root = plugin({"agents/a.md":
                   '---\nname: a\ntools: [Read, Bash]\n'
                   'disallowedTools: ["Bash(rm:*)", "Bash(mv:*)"]\n---\nbody\n'})
    assert run_rule(structure, root).findings == []


def test_the_identical_scoped_entry_on_both_sides_is_reported(plugin, run_rule):
    root = plugin({"agents/a.md":
                   '---\nname: a\ntools: ["Bash(rm:*)"]\n'
                   'disallowedTools: ["Bash(rm:*)"]\n---\nbody\n'})
    assert rules_fired(run_rule(structure, root)) == ["S01"]


def test_the_finding_does_not_claim_which_side_wins(plugin, run_rule):
    root = plugin({"agents/a.md":
                   "---\nname: a\ntools: [Write]\ndisallowedTools: [Write]\n---\nbody\n"})
    note = run_rule(structure, root).findings[0].note.lower()
    assert "denial wins" not in note and "grant wins" not in note


def test_disjoint_lists_are_silent(plugin, run_rule):
    root = plugin({"agents/a.md":
                   "---\nname: a\ntools: [Read, Grep]\ndisallowedTools: [Write]\n---\nbody\n"})
    assert run_rule(structure, root).findings == []


def test_a_fence_below_line_one_is_reported(plugin, run_rule):
    # Only blank lines may precede it. See the next test for why.
    for body in ("\n---\nname: late\ndescription: x\n---\nbody\n",
                 "\n\n   \n---\nname: late\ndescription: x\n---\nbody\n"):
        root = plugin({"commands/c.md": body})
        report = run_rule(structure, root)
        assert rules_fired(report) == ["S02"], body[:12]
        assert report.result == "FAIL"


def test_prose_above_a_fence_is_a_document_not_misplaced_frontmatter(plugin, run_rule):
    # A heading and two horizontal rules is an ordinary page, and so is one with
    # a single colon line between two rules, which parses as a YAML mapping.
    # Both were reported. Prose above a fence cannot be told apart from a
    # document, so only whitespace above one counts.
    for body in ("A note for the reader.\n---\nname: late\n---\nbody\n",
                 "# Guide\n\nProse.\n\n---\n\nNote: something\n\n---\n\nMore.\n",
                 "Overview\n---\nThis page explains the thing.\n"):
        root = plugin({"references/g.md": body})
        assert run_rule(structure, root).findings == [], body[:20]


def test_a_byte_order_mark_warns_without_claiming_the_outcome(plugin, run_rule):
    # Stripping the mark makes the block look ordinary, so it is checked first.
    # It warns rather than errors: whether the loader looks past a leading mark
    # is a fact about Claude Code that is not measured here.
    root = plugin({"commands/c.md": "\ufeff---\nname: bom\ndescription: x\n---\nbody\n"})
    report = run_rule(structure, root)
    assert rules_fired(report) == ["S02"]
    assert report.findings[0].severity == "warn"
    assert report.result == "PASS"
    assert run_rule(structure, root, strict=True).result == "FAIL"


def test_a_setext_heading_is_not_misplaced_frontmatter(plugin, run_rule):
    # Valid CommonMark: a heading underlined with dashes. The old rule read the
    # dashes as a frontmatter fence and reported an ordinary docs page.
    root = plugin({"references/guide.md":
                   "Overview\n---\nThis page explains the thing.\n\nMore prose here.\n"})
    assert run_rule(structure, root).findings == []


def test_a_horizontal_rule_in_a_readme_is_not_frontmatter(plugin, run_rule):
    root = plugin({"README.md": "# Title\n\nProse.\n\n---\n\nMore prose.\n"})
    assert run_rule(structure, root).findings == []


def test_frontmatter_that_does_not_parse_is_reported(plugin, run_rule):
    root = plugin({"agents/a.md": "---\nname: a\ntools: [Read, Write\n---\nbody\n"})
    assert rules_fired(run_rule(structure, root)) == ["S02"]


def test_an_execution_marker_in_a_component_body_is_reported(plugin, run_rule):
    # The shape that makes one shipped skill uninvocable.
    for fence in ("```", "~~~"):
        root = plugin({"skills/s/SKILL.md":
                       "---\nname: s\ndescription: x\n---\nExample:\n\n"
                       "%s\nRun tests: %s\n%s\n" % (fence, EXEC, fence)})
        assert rules_fired(run_rule(structure, root)) == ["S03"], fence


def test_documentation_prose_is_not_a_component_body(plugin, run_rule):
    # A README or changelog explaining the syntax is not loaded as a component,
    # so the marker in it never runs. The old rule reported both.
    for name in ("README.md", "CHANGELOG.md", "references/writing-commands.md"):
        root = plugin({name: "# Doc\n\nWrite it like this:\n\n```\nRun: %s\n```\n" % EXEC})
        assert run_rule(structure, root).findings == [], name


def test_an_ordinary_command_in_a_fence_is_silent(plugin, run_rule):
    root = plugin({"skills/s/SKILL.md":
                   "---\nname: s\ndescription: x\n---\nExample:\n\n```\nnpm test\n```\n"})
    assert run_rule(structure, root).findings == []


def test_a_tree_with_no_markdown_is_not_a_pass(plugin, run_rule):
    root = plugin({"scripts/x.sh": "echo hi\n"})
    assert run_rule(structure, root).result == "UNCHECKED"


def test_its_own_test_fixtures_are_not_subjects(plugin, run_rule):
    root = plugin({"tests/fixture.md": "\n---\nname: deliberately-broken\n---\nx\n"})
    assert run_rule(structure, root).result == "UNCHECKED"


def test_an_unterminated_fence_is_reported_without_a_manifest_declaration(plugin, run_rule):
    # This used to live with the component-file rules, which only see files a
    # manifest declares by path. No plugin in this repository declares any, so
    # the rule fired on nothing at all: the same broken file passed at a
    # conventional location and failed only when the manifest named it.
    root = plugin({"commands/broken.md": "---\nname: broken\ndescription: x\n"})
    assert rules_fired(run_rule(structure, root)) == ["S04"]


def test_a_yaml_comment_or_blank_line_does_not_switch_the_rules_off(plugin, run_rule):
    # The block used to be validated line by line against one narrow shape, so
    # legal YAML that did not match it made a real component body look like
    # prose and silently disabled every rule here for that file.
    for extra in ("# which tools this agent gets\n",
                  "\n",
                  '"quoted": yes\n',
                  "description: |\n  one\n\n  two\n"):
        body = "---\nname: a\n%stools: [Read, Write]\ndisallowedTools: [Write]\n---\nbody\n" % extra
        root = plugin({"agents/a.md": body})
        assert rules_fired(run_rule(structure, root)) == ["S01"], extra


def test_a_docs_page_with_horizontal_rules_is_not_misplaced_frontmatter(plugin, run_rule):
    # The shape of an ordinary reference page: a title, prose, a rule, more
    # prose. Fourteen files in one plugin were reported when the "broken
    # frontmatter still counts" branch leaked into this path.
    root = plugin({"references/guide.md":
                   "# Carousels Guide\n\nContent type guide for carousels.\n\n"
                   "---\n\n## Zen Foundation\n\n### Three Principles\n\n"
                   "Some prose.\n\n---\n\nMore prose.\n"})
    assert run_rule(structure, root).findings == []
