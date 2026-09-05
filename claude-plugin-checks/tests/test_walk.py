"""The one tree walk. Every rule module used to have its own copy of this."""

import os
import stat

import pytest

from cpc import walk
from cpc.result import Report


def test_an_unreadable_directory_is_reported_not_silently_skipped(tmp_path):
    # The review found this defect present in all three of the old scripts,
    # because each one walked the tree itself. One walk, one fix.
    good = tmp_path / "readable"
    good.mkdir()
    (good / "a.md").write_text("x")
    locked = tmp_path / "locked"
    locked.mkdir()
    (locked / "hidden.md").write_text("secret")
    os.chmod(locked, 0o000)
    try:
        report = Report(str(tmp_path))
        found = walk.files(str(tmp_path), report)
        assert any(f.endswith("a.md") for f in found)
        assert report.blind, "an unreadable directory must be reported"
    finally:
        os.chmod(locked, stat.S_IRWXU)


def test_noise_directories_are_pruned(tmp_path):
    for noisy in (".git", "node_modules", "__pycache__", ".worktrees"):
        d = tmp_path / noisy
        d.mkdir()
        (d / "junk.md").write_text("x")
    (tmp_path / "real.md").write_text("x")
    report = Report(str(tmp_path))
    found = walk.files(str(tmp_path), report)
    assert [os.path.basename(f) for f in found] == ["real.md"]


def test_suffix_filtering(tmp_path):
    (tmp_path / "a.md").write_text("x")
    (tmp_path / "b.json").write_text("{}")
    report = Report(str(tmp_path))
    assert [os.path.basename(f)
            for f in walk.files(str(tmp_path), report, suffixes=(".md",))] == ["a.md"]


def test_results_are_sorted_so_output_is_stable(tmp_path):
    for name in ("c.md", "a.md", "b.md"):
        (tmp_path / name).write_text("x")
    report = Report(str(tmp_path))
    found = walk.files(str(tmp_path), report)
    assert found == sorted(found)


def test_a_binary_file_is_recognised(tmp_path):
    (tmp_path / "img.png").write_bytes(b"\x89PNG\x00\x00rest")
    (tmp_path / "doc.md").write_text("plain text")
    assert walk.is_probably_binary(str(tmp_path / "img.png"))
    assert not walk.is_probably_binary(str(tmp_path / "doc.md"))


def test_a_few_bad_bytes_do_not_hide_the_rest_of_a_text_file(tmp_path):
    # One stray byte used to make read_text give up, and one early NUL used to
    # make is_probably_binary skip the file whole, so a credential further down
    # went unseen and the run was clean.
    p = tmp_path / "notes.md"
    p.write_bytes(b"note\x00\nsecond line survives\n")
    report = Report(str(tmp_path))
    assert not walk.is_probably_binary(str(p))
    text = walk.read_text(str(p), report)
    assert text is not None and "second line survives" in text
    assert report.blind == []


def test_a_real_binary_is_still_recognised(tmp_path):
    p = tmp_path / "img.png"
    p.write_bytes(b"\x89PNG\r\n\x1a\n" + bytes(range(256)) * 8)
    assert walk.is_probably_binary(str(p))


def test_a_symlinked_directory_is_walked(tmp_path):
    # os.walk does not follow directory symlinks by default, so a vendored or
    # shared folder reached by symlink contributed no files, no counter and no
    # blind spot. A tree with a credential behind one reported clean.
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "leak.md").write_text("secret")
    plugin = tmp_path / "plugin"
    plugin.mkdir()
    (plugin / "own.md").write_text("x")
    os.symlink(outside, plugin / "vendored")
    report = Report(str(plugin))
    found = [os.path.basename(f) for f in walk.files(str(plugin), report)]
    assert "leak.md" in found


def test_a_symlink_loop_terminates(tmp_path):
    a = tmp_path / "a"
    a.mkdir()
    (a / "f.md").write_text("x")
    os.symlink(tmp_path, a / "back")       # points at its own ancestor
    report = Report(str(tmp_path))
    found = walk.files(str(tmp_path), report)
    assert len(found) == len(set(found))
    assert any(f.endswith("f.md") for f in found)


def test_utf8_text_is_not_binary_however_its_bytes_look(tmp_path):
    p = tmp_path / "art.md"
    p.write_text("\n".join("│" + "─" * 60 + "│" for _ in range(60)), encoding="utf-8")
    assert not walk.is_probably_binary(str(p))


def test_a_read_landing_mid_character_is_not_evidence_of_binary(tmp_path):
    # The sample is a fixed number of bytes, so it can stop halfway through a
    # multi-byte character. That is not a fact about the file.
    p = tmp_path / "long.md"
    p.write_text("é" * 5000, encoding="utf-8")
    assert not walk.is_probably_binary(str(p))


def test_two_siblings_symlinked_to_one_target_do_not_hide_a_real_directory(tmp_path):
    shared = tmp_path / "shared"
    shared.mkdir()
    (shared / "s.md").write_text("x")
    plugin = tmp_path / "plugin"
    plugin.mkdir()
    real = plugin / "real"
    real.mkdir()
    (real / "r.md").write_text("x")
    os.symlink(shared, plugin / "a")
    os.symlink(shared, plugin / "b")
    report = Report(str(plugin))
    names = [os.path.basename(f) for f in walk.files(str(plugin), report)]
    assert "r.md" in names, "a real directory must not be pruned as already seen"
    assert names.count("s.md") == 1, "the shared target is walked once"


def test_text_that_decodes_into_mostly_control_characters_is_binary(tmp_path):
    # A file can decode cleanly and still be nothing a text rule should read.
    # Without a case here the ratio test was unreachable: everything that got
    # that far was ordinary prose, so deleting the comparison changed nothing.
    p = tmp_path / "weird.dat"
    p.write_text("\x01\x02\x03\x04\x05\x06" * 500 + "readable tail", encoding="utf-8")
    assert walk.is_probably_binary(str(p))


def test_a_file_that_is_mostly_prose_with_some_control_bytes_is_text(tmp_path):
    p = tmp_path / "notes.md"
    p.write_text("ordinary prose line\n" * 200 + "\x01\x02", encoding="utf-8")
    assert not walk.is_probably_binary(str(p))
