"""Unit tests for the PPTX-import path through ``slides.cli``.

These tests mock Drive + Slides services and the ``MediaFileUpload``
constructor so they run without network and without a real PPTX file.

They cover:

* ``mirror_presentation`` with ``pptx_path`` — uploads the PPTX into the
  render folder with ``mimeType: application/vnd.google-apps.presentation``
  and the right content mimetype, sets the deck title, returns
  ``path_used == 'pptx_import'``.
* ``mirror_template_sample`` with ``pptx_path`` — same Drive call shape
  under ``kind=templates``; PDF / outline are *not* uploaded.
* ``pptx_path`` wins when both ``pptx_path`` and ``deck_id`` are
  supplied (back-compat additive contract).
* Legacy ``deck_id`` path still works when ``pptx_path`` is absent.
* Missing both raises ``ValueError``.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from slides import cli
from slides.runner import SlidesRunner


# --- helpers ---------------------------------------------------------------


def _make_runner_with_drive_responses():
    """Build a SlidesRunner whose Drive service stubs out every call used by
    the mirror code path.

    Drive calls made by mirror_into_folder when ``pptx_path`` is given:

    * ``files().create()`` (folder ensure x N) — DriveFolderMirror
    * ``files().list()`` (find-or-create x N) — DriveFolderMirror
    * ``files().create()`` (PPTX upload with convert-to-Slides)
    * ``files().create()`` (PDF, outline — presentation flow only)
    """
    slides = MagicMock(name="slides")
    drive = MagicMock(name="drive")

    # `files().list().execute()` — DriveFolderMirror.find_render_folder uses
    # this to look for existing folders. Return empty so it always creates.
    drive.files.return_value.list.return_value.execute.return_value = {"files": []}

    # `files().create().execute()` — used for both folder-create AND the
    # PPTX-upload + PDF-upload + outline-upload. We use a counter-based
    # side_effect so each call gets a deterministic id we can assert on.
    create_call = {"n": 0}

    def _create_execute_side_effect(*args, **kwargs):
        create_call["n"] += 1
        return {"id": f"id-{create_call['n']}", "webViewLink": "https://x"}

    drive.files.return_value.create.return_value.execute.side_effect = (
        _create_execute_side_effect
    )

    # `files().update().execute()` — move_to_folder (deprecated path only).
    drive.files.return_value.update.return_value.execute.return_value = {
        "id": "deck-legacy",
        "parents": ["folderX"],
    }
    # `files().get().execute()` — move_to_folder reads current parents.
    drive.files.return_value.get.return_value.execute.return_value = {
        "parents": ["root"],
    }

    runner = SlidesRunner(slides, drive)
    return runner, slides, drive, create_call


def _patch_media_upload():
    """Patch the ``MediaFileUpload`` constructor in ``slides.cli`` so it does
    not try to open or stat a real file."""
    return patch.object(cli, "MediaFileUpload", autospec=True)


# --- tests -----------------------------------------------------------------


def test_mirror_presentation_pptx_path_uploads_with_slides_mimetype(tmp_path):
    runner, _slides, drive, _ = _make_runner_with_drive_responses()
    local_dir = tmp_path / "2026-05-26-launch"
    local_dir.mkdir()
    pptx = local_dir / "launch.pptx"
    pptx.write_bytes(b"fake")

    with _patch_media_upload() as media_ctor:
        result = cli._cmd_mirror_presentation(
            runner,
            {
                "brand": "acme",
                "render_slug": "2026-05-26-launch",
                "local_dir": str(local_dir),
                "pptx_path": str(pptx),
                "deck_title": "Acme Launch",
            },
        )

    assert result["path_used"] == "pptx_import"
    # MediaFileUpload was called at least once — find the PPTX upload call.
    pptx_calls = [
        c
        for c in media_ctor.call_args_list
        if c.kwargs.get("mimetype") == cli.PPTX_MIMETYPE
        or (c.args and c.args[0] == str(pptx))
    ]
    assert pptx_calls, "Expected one MediaFileUpload(...) call for the PPTX"
    # Look at the underlying files().create body for at least one call that
    # carries our Slides mimeType — that's the convert-on-upload signal.
    create_bodies = [
        c.kwargs.get("body")
        for c in drive.files.return_value.create.call_args_list
        if c.kwargs.get("body")
    ]
    slides_creates = [
        b for b in create_bodies
        if b.get("mimeType") == cli.GOOGLE_SLIDES_MIMETYPE
    ]
    assert slides_creates, "Expected a files.create with Google Slides mimeType"
    assert any(b["name"] == "Acme Launch" for b in slides_creates)
    # Pointer file written locally — name strips the YYYY-MM-DD- prefix.
    assert (local_dir / "launch.slides.url").exists()


def test_mirror_template_sample_pptx_path_uploads_only_the_deck(tmp_path):
    runner, _slides, drive, _ = _make_runner_with_drive_responses()
    pptx = tmp_path / "sample.pptx"
    pptx.write_bytes(b"fake")

    with _patch_media_upload() as media_ctor:
        result = cli._cmd_mirror_template_sample(
            runner,
            {
                "brand": "acme",
                "render_slug": "sales-pitch",
                "local_dir": str(tmp_path),
                "pptx_path": str(pptx),
            },
        )

    assert result["path_used"] == "pptx_import"
    # Templates flow does NOT upload PDF or outline → only the PPTX is media-
    # uploaded. (Folder-creates do not go through MediaFileUpload.)
    assert media_ctor.call_count == 1
    # No PDF or outline ids set.
    assert result["pdf_file_id"] is None
    assert result["outline_file_id"] is None


def test_pptx_path_wins_over_deck_id_when_both_supplied(tmp_path):
    runner, _slides, drive, _ = _make_runner_with_drive_responses()
    pptx = tmp_path / "sample.pptx"
    pptx.write_bytes(b"fake")

    with _patch_media_upload():
        result = cli._cmd_mirror_template_sample(
            runner,
            {
                "brand": "acme",
                "render_slug": "sales-pitch",
                "local_dir": str(tmp_path),
                "pptx_path": str(pptx),
                "deck_id": "ignored-legacy-id",
            },
        )

    assert result["path_used"] == "pptx_import"
    # move_to_folder (legacy path) MUST NOT have been called.
    drive.files.return_value.update.assert_not_called()


def test_legacy_deck_id_path_still_works(tmp_path):
    runner, _slides, drive, _ = _make_runner_with_drive_responses()

    with _patch_media_upload():
        result = cli._cmd_mirror_template_sample(
            runner,
            {
                "brand": "acme",
                "render_slug": "sales-pitch",
                "local_dir": str(tmp_path),
                "deck_id": "deck-legacy",
            },
        )

    assert result["path_used"] == "direct_create"
    # move_to_folder WAS called.
    drive.files.return_value.update.assert_called_once()


def test_missing_both_raises(tmp_path):
    runner, _slides, _drive, _ = _make_runner_with_drive_responses()

    with pytest.raises(ValueError, match="pptx_path"):
        cli._cmd_mirror_presentation(
            runner,
            {
                "brand": "acme",
                "render_slug": "x",
                "local_dir": str(tmp_path),
            },
        )
