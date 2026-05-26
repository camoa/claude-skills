"""Thin Slides + Drive operations runner.

Single responsibility: execute Slides API calls that the caller hands in. The
caller (in this plugin's commands) is responsible for authoring the
``batchUpdate`` request list and for any Drive folder convention.
"""

from __future__ import annotations

from typing import Any


class SlidesRunner:
    """Execute Slides + Drive operations against authenticated services.

    Parameters
    ----------
    slides_service:
        An authenticated ``googleapiclient`` ``slides v1`` resource.
    drive_service:
        An authenticated ``googleapiclient`` ``drive v3`` resource.
    """

    def __init__(self, slides_service, drive_service):
        self._slides = slides_service
        self._drive = drive_service

    # ----------------------------------------------------------------- Slides

    def create_deck(self, title: str) -> str:
        """Create a blank Slides deck and return its presentation id."""
        response = (
            self._slides.presentations()
            .create(body={"title": title})
            .execute()
        )
        return response["presentationId"]

    def apply_batch_update(
        self, deck_id: str, requests: list[dict]
    ) -> dict[str, Any]:
        """Execute a ``presentations.batchUpdate`` and return the raw response.

        ``requests`` is a list of Slides API request objects. This runner does
        not author or validate them — the caller owns that.
        """
        return (
            self._slides.presentations()
            .batchUpdate(presentationId=deck_id, body={"requests": requests})
            .execute()
        )

    # ------------------------------------------------------------------ Drive

    def move_to_folder(self, deck_id: str, folder_id: str) -> None:
        """Move a deck into a Drive folder.

        Removes the existing parents (typically the user's root) and adds the
        target folder as the new parent. No-op vs. the destination folder is
        not checked — caller is responsible for that.
        """
        file_metadata = (
            self._drive.files()
            .get(fileId=deck_id, fields="parents")
            .execute()
        )
        previous_parents = ",".join(file_metadata.get("parents", []))
        (
            self._drive.files()
            .update(
                fileId=deck_id,
                addParents=folder_id,
                removeParents=previous_parents,
                fields="id, parents",
            )
            .execute()
        )

    # ------------------------------------------------------------------- Pure

    @staticmethod
    def deck_url(deck_id: str) -> str:
        """Return the canonical edit URL for a Slides deck id."""
        return f"https://docs.google.com/presentation/d/{deck_id}/edit"
