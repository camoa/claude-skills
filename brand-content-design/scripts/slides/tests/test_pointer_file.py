"""Unit tests for slides.runner pointer-file helpers."""

from __future__ import annotations

import json

from slides.runner import (
    POINTER_SUFFIX,
    pointer_file_path,
    read_slides_url_file,
    write_slides_url_file,
)


def test_pointer_file_path_strips_date_prefix(tmp_path):
    folder = tmp_path / "2026-05-26-product-launch"
    folder.mkdir()
    assert pointer_file_path(folder).name == "product-launch" + POINTER_SUFFIX


def test_pointer_file_path_keeps_name_when_no_date_prefix(tmp_path):
    folder = tmp_path / "community-talk"
    folder.mkdir()
    assert pointer_file_path(folder).name == "community-talk" + POINTER_SUFFIX


def test_write_and_read_roundtrip(tmp_path):
    folder = tmp_path / "2026-05-27-launch"
    folder.mkdir()

    path = write_slides_url_file(folder, deck_id="deck-abc", folder_id="folder-xyz")

    assert path.name == "launch" + POINTER_SUFFIX
    assert path.exists()

    parsed = read_slides_url_file(folder)
    assert parsed is not None
    assert parsed["deck_id"] == "deck-abc"
    assert parsed["folder_id"] == "folder-xyz"
    assert parsed["deck_url"] == "https://docs.google.com/presentation/d/deck-abc/edit"
    assert parsed["folder_url"] == "https://drive.google.com/drive/folders/folder-xyz"
    assert "written_at" in parsed


def test_write_overwrites_existing(tmp_path):
    folder = tmp_path / "2026-05-27-launch"
    folder.mkdir()
    write_slides_url_file(folder, "old-deck", "old-folder")
    write_slides_url_file(folder, "new-deck", "new-folder")

    parsed = read_slides_url_file(folder)
    assert parsed["deck_id"] == "new-deck"
    assert parsed["folder_id"] == "new-folder"


def test_read_returns_none_when_missing(tmp_path):
    folder = tmp_path / "empty"
    folder.mkdir()
    assert read_slides_url_file(folder) is None


def test_written_payload_is_valid_json(tmp_path):
    folder = tmp_path / "x"
    folder.mkdir()
    path = write_slides_url_file(folder, "d", "f")
    # No exception means parseable
    json.loads(path.read_text(encoding="utf-8"))
