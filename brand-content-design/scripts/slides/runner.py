"""Thin Slides + Drive operations runner.

Single responsibility: execute Slides API calls that the caller hands in. The
caller (in this plugin's commands) is responsible for authoring the
``batchUpdate`` request list.

Drive folder convention (added in ``slides_drive_mirroring`` subtask):

    {root}/brand-content/{brand}/presentations/{date}-{slug}/
    {root}/brand-content/{brand}/templates/{slug}/

where ``{root}`` is the Drive folder id given in
``BRAND_CONTENT_DRIVE_ROOT_ID`` if set, else the user's "My Drive" root.
The :class:`DriveFolderMirror` helper creates and discovers folders along
this chain idempotently — every level uses a list-then-create pattern so a
re-run on the same brand never duplicates the intermediates.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal, Optional


#: The single tool-owned root folder under whatever ``root_id`` the caller
#: passes (My Drive root by default). All brand projects live underneath.
BRAND_CONTENT_ROOT_NAME = "brand-content"

#: Subfolder names. Constants so the command-md side and tests can import
#: them rather than hard-code strings.
PRESENTATIONS_SUBFOLDER = "presentations"
TEMPLATES_SUBFOLDER = "templates"

#: Filename suffix for the local pointer file written next to PDF/PPTX.
POINTER_SUFFIX = ".slides.url"

#: Match a leading ISO-style date prefix on a local folder name so the
#: pointer-file base can be derived. ``2026-05-26-product-launch`` →
#: ``product-launch``. Folders without a date prefix are used verbatim.
_DATE_PREFIX_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-")


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


# --------------------------------------------------------------------------- #
# Drive folder mirror                                                         #
# --------------------------------------------------------------------------- #


class DriveFolderMirror:
    """Idempotent create/find/trash for the brand-content Drive convention.

    All operations are scoped to the ``drive.file`` OAuth scope: this helper
    only sees and modifies folders/files it created. That is fine because
    every folder along the brand-content chain is created by this helper
    (or under a root the caller explicitly handed us via
    ``BRAND_CONTENT_DRIVE_ROOT_ID``).

    Parameters
    ----------
    drive_service:
        Authenticated ``googleapiclient`` ``drive v3`` resource.
    root_id:
        Drive folder id that ``brand-content/`` lives under. Pass the value
        of ``BRAND_CONTENT_DRIVE_ROOT_ID`` from environment, or ``None`` /
        ``"root"`` to use the user's My Drive root.
    """

    FOLDER_MIME = "application/vnd.google-apps.folder"

    def __init__(self, drive_service, root_id: Optional[str] = None):
        self._drive = drive_service
        self._root_id = root_id or "root"

    # ----- private --------------------------------------------------------- #

    def _find_or_create_folder(self, name: str, parent_id: str) -> str:
        """Return the folder id of ``name`` under ``parent_id``, creating it
        if absent.

        IDEMPOTENT by design: ``files.list`` is the only safe way to avoid
        accumulating duplicate intermediate folders across runs, since the
        Drive API has no native ``upsert``. Single-quote escaping handles
        slugs that happen to contain apostrophes.
        """
        escaped = name.replace("'", r"\'")
        query = (
            f"name = '{escaped}' "
            f"and '{parent_id}' in parents "
            f"and mimeType = '{self.FOLDER_MIME}' "
            f"and trashed = false"
        )
        response = (
            self._drive.files()
            .list(q=query, fields="files(id, name)", pageSize=1)
            .execute()
        )
        files = response.get("files", [])
        if files:
            return files[0]["id"]
        created = (
            self._drive.files()
            .create(
                body={
                    "name": name,
                    "mimeType": self.FOLDER_MIME,
                    "parents": [parent_id],
                },
                fields="id",
            )
            .execute()
        )
        return created["id"]

    # ----- public: brand chain -------------------------------------------- #

    def ensure_brand_folder(self, brand_name: str) -> str:
        """Create or find ``{root}/brand-content/{brand_name}/``. Returns id.

        Walks the chain in two steps (root → brand-content → brand) so each
        intermediate is found-or-created independently. Re-running for the
        same brand never duplicates.
        """
        brand_content_id = self._find_or_create_folder(
            BRAND_CONTENT_ROOT_NAME, self._root_id
        )
        return self._find_or_create_folder(brand_name, brand_content_id)

    def ensure_presentations_folder(self, brand_name: str) -> str:
        """Create or find ``brand-content/{brand}/presentations/``."""
        brand_id = self.ensure_brand_folder(brand_name)
        return self._find_or_create_folder(PRESENTATIONS_SUBFOLDER, brand_id)

    def ensure_templates_folder(self, brand_name: str) -> str:
        """Create or find ``brand-content/{brand}/templates/``."""
        brand_id = self.ensure_brand_folder(brand_name)
        return self._find_or_create_folder(TEMPLATES_SUBFOLDER, brand_id)

    def ensure_render_folder(
        self,
        brand_name: str,
        kind: Literal["presentations", "templates"],
        render_slug: str,
    ) -> str:
        """Create or find ``brand-content/{brand}/{kind}/{render_slug}/``."""
        if kind == "presentations":
            parent = self.ensure_presentations_folder(brand_name)
        elif kind == "templates":
            parent = self.ensure_templates_folder(brand_name)
        else:
            raise ValueError(
                f"kind must be 'presentations' or 'templates', got {kind!r}"
            )
        return self._find_or_create_folder(render_slug, parent)

    def find_render_folder(
        self,
        brand_name: str,
        kind: str,
        render_slug: str,
    ) -> Optional[str]:
        """Return the render folder id if it exists (non-trashed), else None.

        Unlike ``ensure_render_folder`` this never creates intermediates —
        if the brand or kind subfolder is missing, we short-circuit to None.
        """
        if kind not in ("presentations", "templates"):
            raise ValueError(
                f"kind must be 'presentations' or 'templates', got {kind!r}"
            )

        def _lookup(name: str, parent_id: str) -> Optional[str]:
            escaped = name.replace("'", r"\'")
            query = (
                f"name = '{escaped}' "
                f"and '{parent_id}' in parents "
                f"and mimeType = '{self.FOLDER_MIME}' "
                f"and trashed = false"
            )
            res = (
                self._drive.files()
                .list(q=query, fields="files(id)", pageSize=1)
                .execute()
            )
            files = res.get("files", [])
            return files[0]["id"] if files else None

        brand_content_id = _lookup(BRAND_CONTENT_ROOT_NAME, self._root_id)
        if not brand_content_id:
            return None
        brand_id = _lookup(brand_name, brand_content_id)
        if not brand_id:
            return None
        kind_subfolder = (
            PRESENTATIONS_SUBFOLDER
            if kind == "presentations"
            else TEMPLATES_SUBFOLDER
        )
        kind_id = _lookup(kind_subfolder, brand_id)
        if not kind_id:
            return None
        return _lookup(render_slug, kind_id)

    def trash_render_folder(self, folder_id: str) -> None:
        """Soft-delete a render folder. Drive cascades to its contents.

        Idempotent: a 404 (folder already gone) is swallowed. Drive retains
        trashed items for 30 days, so this is reversible from the Drive UI.
        """
        try:
            (
                self._drive.files()
                .update(fileId=folder_id, body={"trashed": True})
                .execute()
            )
        except Exception as exc:  # noqa: BLE001 — match cli.py error handling
            status = getattr(getattr(exc, "resp", None), "status", None)
            if status == 404:
                return
            raise

    # ----- public: pure ---------------------------------------------------- #

    @staticmethod
    def folder_url(folder_id: str) -> str:
        """Canonical Drive folder URL."""
        return f"https://drive.google.com/drive/folders/{folder_id}"


# --------------------------------------------------------------------------- #
# Pointer-file helpers (`{name}.slides.url`)                                  #
# --------------------------------------------------------------------------- #


def _derive_pointer_basename(local_dir: Path) -> str:
    """Strip a leading ``YYYY-MM-DD-`` prefix from the folder name if present.

    ``2026-05-26-product-launch/`` → ``product-launch``. Folders without a
    date prefix (e.g. template folders like ``community-talk/``) are used
    verbatim.
    """
    name = local_dir.name
    return _DATE_PREFIX_RE.sub("", name) or name


def pointer_file_path(local_dir: Path) -> Path:
    """Path of the ``.slides.url`` pointer file for ``local_dir``."""
    return local_dir / f"{_derive_pointer_basename(local_dir)}{POINTER_SUFFIX}"


def write_slides_url_file(
    local_dir: Path,
    deck_id: str,
    folder_id: str,
) -> Path:
    """Write a JSON pointer file with deck + folder ids/urls.

    Returns the path written. Contents shape::

        {
            "deck_id": "...",
            "folder_id": "...",
            "deck_url": "...",
            "folder_url": "...",
            "written_at": "2026-05-27T12:34:56+00:00"
        }
    """
    payload = {
        "deck_id": deck_id,
        "folder_id": folder_id,
        "deck_url": SlidesRunner.deck_url(deck_id),
        "folder_url": DriveFolderMirror.folder_url(folder_id),
        "written_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    path = pointer_file_path(local_dir)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def read_slides_url_file(local_dir: Path) -> Optional[dict]:
    """Return parsed pointer-file contents or None if absent."""
    path = pointer_file_path(local_dir)
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))
