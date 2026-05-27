"""Unit tests for slides.runner.DriveFolderMirror — fully mocked, no network."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from slides.runner import (
    BRAND_CONTENT_ROOT_NAME,
    PRESENTATIONS_SUBFOLDER,
    TEMPLATES_SUBFOLDER,
    DriveFolderMirror,
)


def _drive_with_list_results(*list_results):
    """Build a mocked drive service that returns each canned ``files.list``
    result in order, and records ``files.create`` calls.

    Each list_result is a list of file dicts (empty = miss → triggers create).
    """
    drive = MagicMock(name="drive")
    list_chain = drive.files.return_value.list
    list_chain.return_value.execute.side_effect = [
        {"files": files} for files in list_results
    ]

    create_chain = drive.files.return_value.create
    counter = {"n": 0}

    def _create_side_effect(**kwargs):
        counter["n"] += 1
        m = MagicMock()
        m.execute.return_value = {"id": f"new-folder-{counter['n']}"}
        return m

    create_chain.side_effect = _create_side_effect
    return drive


def test_find_or_create_returns_existing_when_present():
    drive = _drive_with_list_results([{"id": "existing-id", "name": "x"}])
    mirror = DriveFolderMirror(drive, root_id="root")

    folder_id = mirror._find_or_create_folder("x", "parent-id")

    assert folder_id == "existing-id"
    drive.files.return_value.create.assert_not_called()


def test_find_or_create_creates_when_absent():
    drive = _drive_with_list_results([])
    mirror = DriveFolderMirror(drive, root_id="root")

    folder_id = mirror._find_or_create_folder("x", "parent-id")

    assert folder_id == "new-folder-1"
    drive.files.return_value.create.assert_called_once()
    create_kwargs = drive.files.return_value.create.call_args.kwargs
    assert create_kwargs["body"]["name"] == "x"
    assert create_kwargs["body"]["parents"] == ["parent-id"]
    assert create_kwargs["body"]["mimeType"] == DriveFolderMirror.FOLDER_MIME


def test_find_or_create_query_uses_trashed_false_and_folder_mime():
    drive = _drive_with_list_results([{"id": "x"}])
    mirror = DriveFolderMirror(drive, root_id="my-root")
    mirror._find_or_create_folder("mybrand", "parent-id")

    q = drive.files.return_value.list.call_args.kwargs["q"]
    assert "trashed = false" in q
    assert DriveFolderMirror.FOLDER_MIME in q
    assert "'parent-id' in parents" in q
    assert "name = 'mybrand'" in q


def test_ensure_brand_folder_walks_root_then_brand_content_then_brand():
    # list 1: brand-content exists; list 2: brand absent → create
    drive = _drive_with_list_results([{"id": "bc-id"}], [])
    mirror = DriveFolderMirror(drive, root_id="my-root")

    brand_id = mirror.ensure_brand_folder("acme")

    assert brand_id == "new-folder-1"
    # First list queried 'brand-content' under 'my-root'
    first_q = drive.files.return_value.list.call_args_list[0].kwargs["q"]
    assert f"name = '{BRAND_CONTENT_ROOT_NAME}'" in first_q
    assert "'my-root' in parents" in first_q


def test_ensure_presentations_folder_chains_through_brand():
    # bc, brand, presentations — all absent → create each
    drive = _drive_with_list_results([], [], [])
    mirror = DriveFolderMirror(drive, root_id="root")

    pres_id = mirror.ensure_presentations_folder("acme")

    assert pres_id == "new-folder-3"
    third_create_kwargs = drive.files.return_value.create.call_args_list[2].kwargs
    assert third_create_kwargs["body"]["name"] == PRESENTATIONS_SUBFOLDER


def test_ensure_templates_folder_uses_templates_subfolder():
    drive = _drive_with_list_results([], [], [])
    mirror = DriveFolderMirror(drive, root_id="root")

    mirror.ensure_templates_folder("acme")

    third_create_kwargs = drive.files.return_value.create.call_args_list[2].kwargs
    assert third_create_kwargs["body"]["name"] == TEMPLATES_SUBFOLDER


def test_ensure_render_folder_creates_full_chain():
    # bc, brand, presentations, render — all absent
    drive = _drive_with_list_results([], [], [], [])
    mirror = DriveFolderMirror(drive, root_id="root")

    render_id = mirror.ensure_render_folder("acme", "presentations", "2026-05-26-launch")

    assert render_id == "new-folder-4"
    fourth_create_kwargs = drive.files.return_value.create.call_args_list[3].kwargs
    assert fourth_create_kwargs["body"]["name"] == "2026-05-26-launch"


def test_ensure_render_folder_rejects_invalid_kind():
    drive = MagicMock()
    mirror = DriveFolderMirror(drive)
    with pytest.raises(ValueError, match="kind must be"):
        mirror.ensure_render_folder("acme", "infographics", "slug")


def test_find_render_folder_returns_id_when_all_levels_present():
    drive = _drive_with_list_results(
        [{"id": "bc"}],
        [{"id": "brand"}],
        [{"id": "pres"}],
        [{"id": "render-id"}],
    )
    mirror = DriveFolderMirror(drive, root_id="root")

    result = mirror.find_render_folder("acme", "presentations", "2026-05-26-launch")

    assert result == "render-id"
    drive.files.return_value.create.assert_not_called()


def test_find_render_folder_returns_none_when_brand_missing():
    # bc present, brand missing
    drive = _drive_with_list_results([{"id": "bc"}], [])
    mirror = DriveFolderMirror(drive, root_id="root")

    result = mirror.find_render_folder("acme", "presentations", "slug")

    assert result is None
    drive.files.return_value.create.assert_not_called()


def test_find_render_folder_returns_none_when_render_missing():
    drive = _drive_with_list_results(
        [{"id": "bc"}], [{"id": "brand"}], [{"id": "pres"}], []
    )
    mirror = DriveFolderMirror(drive, root_id="root")

    assert mirror.find_render_folder("acme", "presentations", "slug") is None


def test_find_render_folder_rejects_invalid_kind():
    drive = MagicMock()
    mirror = DriveFolderMirror(drive)
    with pytest.raises(ValueError, match="kind must be"):
        mirror.find_render_folder("acme", "carousels", "slug")


def test_trash_render_folder_calls_update_with_trashed_true():
    drive = MagicMock()
    drive.files.return_value.update.return_value.execute.return_value = {}
    mirror = DriveFolderMirror(drive)

    mirror.trash_render_folder("folder-123")

    drive.files.return_value.update.assert_called_once_with(
        fileId="folder-123", body={"trashed": True}
    )


def test_trash_render_folder_swallows_404():
    drive = MagicMock()

    class FakeHttpError(Exception):
        def __init__(self):
            self.resp = type("R", (), {"status": 404})()
            super().__init__("not found")

    drive.files.return_value.update.return_value.execute.side_effect = FakeHttpError()
    mirror = DriveFolderMirror(drive)

    # Should not raise
    mirror.trash_render_folder("missing-folder")


def test_trash_render_folder_reraises_non_404():
    drive = MagicMock()

    class FakeHttpError(Exception):
        def __init__(self):
            self.resp = type("R", (), {"status": 500})()
            super().__init__("boom")

    drive.files.return_value.update.return_value.execute.side_effect = FakeHttpError()
    mirror = DriveFolderMirror(drive)

    with pytest.raises(FakeHttpError):
        mirror.trash_render_folder("folder-id")


def test_folder_url_is_pure_and_well_formed():
    assert (
        DriveFolderMirror.folder_url("abc123")
        == "https://drive.google.com/drive/folders/abc123"
    )


def test_root_id_defaults_to_my_drive_root_when_none():
    drive = _drive_with_list_results([{"id": "bc"}], [{"id": "brand"}])
    mirror = DriveFolderMirror(drive, root_id=None)
    mirror.ensure_brand_folder("acme")

    first_q = drive.files.return_value.list.call_args_list[0].kwargs["q"]
    assert "'root' in parents" in first_q
