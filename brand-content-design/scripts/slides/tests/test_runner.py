"""Unit tests for slides.runner — mocked services, no network."""

from __future__ import annotations

from unittest.mock import MagicMock

from slides.runner import SlidesRunner


def _make_runner():
    slides = MagicMock(name="slides")
    drive = MagicMock(name="drive")
    return SlidesRunner(slides, drive), slides, drive


def test_create_deck_returns_presentation_id():
    runner, slides, _ = _make_runner()
    slides.presentations.return_value.create.return_value.execute.return_value = {
        "presentationId": "abc123",
        "title": "Test",
    }

    deck_id = runner.create_deck("Test")

    assert deck_id == "abc123"
    slides.presentations.return_value.create.assert_called_once_with(
        body={"title": "Test"}
    )


def test_apply_batch_update_passes_requests_through():
    runner, slides, _ = _make_runner()
    requests = [{"createShape": {"objectId": "x"}}, {"insertText": {}}]
    slides.presentations.return_value.batchUpdate.return_value.execute.return_value = {
        "replies": [{}, {}]
    }

    result = runner.apply_batch_update("deck1", requests)

    assert result == {"replies": [{}, {}]}
    slides.presentations.return_value.batchUpdate.assert_called_once_with(
        presentationId="deck1",
        body={"requests": requests},
    )


def test_move_to_folder_calls_drive_update_with_add_remove_parents():
    runner, _, drive = _make_runner()
    drive.files.return_value.get.return_value.execute.return_value = {"parents": ["rootP"]}
    drive.files.return_value.update.return_value.execute.return_value = {
        "id": "deck1",
        "parents": ["folderX"],
    }

    runner.move_to_folder("deck1", "folderX")

    drive.files.return_value.update.assert_called_once_with(
        fileId="deck1",
        addParents="folderX",
        removeParents="rootP",
        fields="id, parents",
    )


def test_deck_url_is_pure_and_well_formed():
    assert SlidesRunner.deck_url("abc123") == (
        "https://docs.google.com/presentation/d/abc123/edit"
    )
