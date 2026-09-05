"""The outcome vocabulary. Every rule module depends on getting this right."""

from cpc.result import (EXIT_CLEAN, EXIT_FINDING, EXIT_UNCHECKED, ERROR, FAIL,
                        PASS, UNCHECKED, WARN, Finding, Report, clean, merge)


def _finding(severity=ERROR):
    return Finding("X01", severity, "kind", "note", file="/root/a.md", line=1)


def test_nothing_examined_is_not_a_pass():
    # The whole point of three outcomes. A run that looked at nothing has not
    # cleared anything, and saying PASS there is a false all-clear.
    r = Report("/root")
    assert r.result == UNCHECKED
    assert r.exit_code == EXIT_UNCHECKED


def test_examined_and_clean_is_a_pass():
    r = Report("/root")
    r.subjects = 2
    assert r.result == PASS
    assert r.exit_code == EXIT_CLEAN


def test_a_blind_spot_with_no_findings_is_not_a_pass():
    r = Report("/root")
    r.subjects = 5
    r.cannot_look("sub/dir", "unreadable")
    assert r.result == UNCHECKED


def test_a_warning_alone_passes_until_strict():
    r = Report("/root")
    r.subjects = 1
    r.add(_finding(WARN))
    assert r.result == PASS
    strict = Report("/root", strict=True)
    strict.subjects = 1
    strict.add(_finding(WARN))
    assert strict.result == FAIL
    assert strict.exit_code == EXIT_FINDING


def test_an_error_fails_either_way():
    for strict in (False, True):
        r = Report("/root", strict)
        r.subjects = 1
        r.add(_finding(ERROR))
        assert r.result == FAIL


def test_severity_is_validated_at_construction():
    import pytest
    with pytest.raises(ValueError):
        Finding("X01", "critical", "kind", "note")


def test_an_excerpt_cannot_carry_a_terminal_escape_into_the_summary():
    # An excerpt quotes a file this tool did not write, and the readable summary
    # is printed to a terminal. A raw escape sequence there can move the cursor
    # or hide the rest of a line, so a plugin could shape what a person sees
    # about itself.
    hostile = "clean text\x1b[2K\x1b[1;31mALL CHECKS PASSED\x07"
    f = Finding("X01", ERROR, "kind", "note", file="/root/a.md", line=1,
                excerpt=hostile)
    rendered = f.as_dict("/root")["excerpt"]
    assert not any(c < " " and c != "\t" for c in rendered)
    assert "ALL CHECKS PASSED" in rendered   # the text stays, only the codes go
    assert clean("keep\ttab") == "keep\ttab"


def test_merge_sums_subjects_blind_spots_and_findings():
    a, b = Report("/root"), Report("/root")
    a.subjects, b.subjects = 2, 3
    a.add(_finding())
    b.cannot_look("x", "y")
    combined = merge([a, b], "/root")
    assert combined.subjects == 5
    assert len(combined.findings) == 1
    assert len(combined.blind) == 1
    assert combined.result == FAIL


def test_paths_are_reported_relative_to_the_plugin():
    f = _finding()
    assert f.as_dict("/root")["file"] == "a.md"


def test_a_blind_spot_outranks_a_clean_remainder():
    # The defect this replaced: the blind-spot test was "blind AND no findings",
    # so one warning anywhere turned an unreadable directory holding a
    # credential into a pass with exit 0.
    r = Report("/root")
    r.subjects = 6
    r.add(_finding(WARN))
    r.cannot_look("locked", "permission denied")
    assert r.result == UNCHECKED
    assert r.exit_code == EXIT_UNCHECKED


def test_a_real_error_still_outranks_a_blind_spot():
    # An error is actionable; report it rather than hiding it behind "could not
    # look at something else".
    r = Report("/root")
    r.subjects = 6
    r.add(_finding(ERROR))
    r.cannot_look("locked", "permission denied")
    assert r.result == FAIL


def test_the_same_blind_spot_from_two_rules_is_reported_once():
    a, b = Report("/root"), Report("/root")
    a.subjects = b.subjects = 1
    a.cannot_look("locked", "permission denied")
    b.cannot_look("locked", "permission denied")
    assert len(merge([a, b], "/root").blind) == 1
