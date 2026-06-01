"""Stdin/stdout JSON adapter around :class:`slides.runner.SlidesRunner`.

Each command reads a JSON object from stdin and writes a JSON object to
stdout. Logs go to stderr. Exit code is ``0`` on success, ``1`` on any error.

Usage::

    python -m slides.cli create_deck       <<< '{"title": "My deck"}'
    python -m slides.cli apply_batch_update <<< '{"deck_id": "...", "requests": [...]}'
    python -m slides.cli move_to_folder    <<< '{"deck_id": "...", "folder_id": "..."}'

PPTX-import path (canonical, 2026-05-26+) — mirror commands also accept a
``pptx_path`` instead of a ``deck_id``. When ``pptx_path`` is provided the
CLI uploads the PPTX to Drive with ``mimeType:
application/vnd.google-apps.presentation``, which triggers Drive's OOXML
importer to convert it to a native Slides deck while preserving page size
(1440x810 pt) and SHAPE_AUTOFIT — both of which the direct-create Slides
API path cannot achieve (pageSize ignored on ``presentations.create``;
``autofitType`` rejects anything other than NONE). See
``references/slides-batchupdate-authoring.md`` for the deprecated
direct-create authoring path retained as fallback.

Designed for the eventual command-md integration in subtask
``slides_drive_mirroring`` — a Claude Code command can shell out and pipe
JSON in / out without importing Python.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Callable, Optional

from googleapiclient.http import MediaFileUpload

from slides.auth import build_services
from slides.runner import (
    DriveFolderMirror,
    SlidesRunner,
    read_slides_url_file,
    write_slides_url_file,
)


def _make_mirror(drive_service) -> DriveFolderMirror:
    """Build a :class:`DriveFolderMirror` honoring the env-var root override."""
    return DriveFolderMirror(
        drive_service,
        root_id=os.environ.get("BRAND_CONTENT_DRIVE_ROOT_ID") or None,
    )


PPTX_MIMETYPE = (
    "application/vnd.openxmlformats-officedocument.presentationml.presentation"
)
GOOGLE_SLIDES_MIMETYPE = "application/vnd.google-apps.presentation"


def _upload_file(
    drive_service,
    folder_id: str,
    local_path: str,
    mimetype: str,
) -> str:
    """Upload a single file into the given Drive folder. Returns file id."""
    media = MediaFileUpload(local_path, mimetype=mimetype, resumable=False)
    created = (
        drive_service.files()
        .create(
            body={"name": Path(local_path).name, "parents": [folder_id]},
            media_body=media,
            fields="id",
        )
        .execute()
    )
    return created["id"]


def _upload_pptx_as_slides(
    drive_service,
    folder_id: str,
    pptx_path: str,
    title: str,
) -> str:
    """Upload a PPTX into the given Drive folder, converted to native Slides.

    Drive's OOXML importer preserves the PPTX page size (e.g. 1440x810 pt
    from python-pptx) and SHAPE_AUTOFIT — limitations the direct-create
    Slides API path cannot work around. Returns the new deck (file) id.
    """
    media = MediaFileUpload(pptx_path, mimetype=PPTX_MIMETYPE, resumable=False)
    created = (
        drive_service.files()
        .create(
            body={
                "name": title,
                "mimeType": GOOGLE_SLIDES_MIMETYPE,
                "parents": [folder_id],
            },
            media_body=media,
            fields="id, webViewLink",
        )
        .execute()
    )
    return created["id"]


def _mirror_into_folder(
    runner: SlidesRunner,
    mirror: DriveFolderMirror,
    *,
    brand: str,
    kind: str,
    render_slug: str,
    local_dir: str,
    deck_id: Optional[str] = None,
    pptx_path: Optional[str] = None,
    deck_title: Optional[str] = None,
    pdf_path: Optional[str],
    outline_path: Optional[str],
) -> dict[str, Any]:
    """Shared body of mirror_presentation / mirror_template_sample.

    Resolves the deck via one of two paths:

    * **PPTX-import (preferred, canonical 2026-05-26+)** — when
      ``pptx_path`` is provided, upload the PPTX directly into the render
      folder with ``mimeType: application/vnd.google-apps.presentation``
      so Drive's OOXML importer converts it in place. Preserves PPTX page
      size and SHAPE_AUTOFIT, which the direct-create Slides API path
      cannot.

    * **Direct-create (deprecated fallback)** — when ``deck_id`` is
      provided (caller already created and authored via
      ``create_deck`` + ``apply_batch_update``), reparent it into the
      render folder via ``move_to_folder``. Retained for narrow cases
      (placeholder substitution into existing templates, theme
      integration). See ``references/slides-batchupdate-authoring.md``.

    When both are provided, ``pptx_path`` wins.

    Optionally uploads PDF and outline.md and writes the local
    ``.slides.url`` pointer file. PDF/outline are skipped when their
    paths are absent or empty — that is how the templates flow opts out
    of mirroring source files per the epic alignment.
    """
    if not pptx_path and not deck_id:
        raise ValueError(
            "Either 'pptx_path' (preferred) or 'deck_id' (deprecated) must "
            "be provided."
        )

    folder_id = mirror.ensure_render_folder(brand, kind, render_slug)
    drive_service = runner._drive  # already authenticated

    if pptx_path:
        # Canonical PPTX-import path — upload directly into the folder so
        # there is no second reparent call.
        title = deck_title or Path(pptx_path).stem
        deck_id = _upload_pptx_as_slides(
            drive_service, folder_id, pptx_path, title
        )
    else:
        # Deprecated direct-create path — deck already exists at another
        # parent, reparent it into our folder.
        runner.move_to_folder(deck_id, folder_id)

    pdf_file_id: Optional[str] = None
    outline_file_id: Optional[str] = None
    if pdf_path:
        pdf_file_id = _upload_file(
            drive_service, folder_id, pdf_path, "application/pdf"
        )
    if outline_path:
        outline_file_id = _upload_file(
            drive_service, folder_id, outline_path, "text/markdown"
        )

    write_slides_url_file(Path(local_dir), deck_id, folder_id)

    return {
        "folder_id": folder_id,
        "folder_url": DriveFolderMirror.folder_url(folder_id),
        "deck_id": deck_id,
        "deck_url": SlidesRunner.deck_url(deck_id),
        "pdf_file_id": pdf_file_id,
        "outline_file_id": outline_file_id,
        "path_used": "pptx_import" if pptx_path else "direct_create",
    }


def _cmd_create_deck(runner: SlidesRunner, payload: dict) -> dict[str, Any]:
    title = payload["title"]
    deck_id = runner.create_deck(title)
    return {"deck_id": deck_id, "deck_url": SlidesRunner.deck_url(deck_id)}


def _cmd_apply_batch_update(runner: SlidesRunner, payload: dict) -> dict[str, Any]:
    deck_id = payload["deck_id"]
    requests = payload["requests"]
    return runner.apply_batch_update(deck_id, requests)


def _cmd_move_to_folder(runner: SlidesRunner, payload: dict) -> dict[str, Any]:
    deck_id = payload["deck_id"]
    folder_id = payload["folder_id"]
    runner.move_to_folder(deck_id, folder_id)
    return {"deck_id": deck_id, "folder_id": folder_id}


def _cmd_ensure_render_folder(runner: SlidesRunner, payload: dict) -> dict[str, Any]:
    mirror = _make_mirror(runner._drive)
    folder_id = mirror.ensure_render_folder(
        payload["brand"], payload["kind"], payload["render_slug"]
    )
    return {
        "folder_id": folder_id,
        "folder_url": DriveFolderMirror.folder_url(folder_id),
    }


def _cmd_mirror_presentation(runner: SlidesRunner, payload: dict) -> dict[str, Any]:
    """Mirror a presentation render into Drive.

    Accepts either ``pptx_path`` (preferred — canonical PPTX-import path)
    or ``deck_id`` (deprecated direct-create fallback). When both are
    present, ``pptx_path`` wins.
    """
    mirror = _make_mirror(runner._drive)
    return _mirror_into_folder(
        runner,
        mirror,
        brand=payload["brand"],
        kind="presentations",
        render_slug=payload["render_slug"],
        local_dir=payload["local_dir"],
        deck_id=payload.get("deck_id"),
        pptx_path=payload.get("pptx_path"),
        deck_title=payload.get("deck_title"),
        pdf_path=payload.get("pdf_path"),
        outline_path=payload.get("outline_path"),
    )


def _cmd_mirror_template_sample(runner: SlidesRunner, payload: dict) -> dict[str, Any]:
    """Templates flow: ONLY mirrors the Slides deck — no PDF, no outline.

    Per the epic alignment, templates' source files (template.md,
    canvas-philosophy.md, sample.pdf, sample.pptx) stay local; only the
    sample.slides deck is in Drive.

    Accepts either ``pptx_path`` (preferred — canonical PPTX-import path)
    or ``deck_id`` (deprecated direct-create fallback). When both are
    present, ``pptx_path`` wins.
    """
    mirror = _make_mirror(runner._drive)
    return _mirror_into_folder(
        runner,
        mirror,
        brand=payload["brand"],
        kind="templates",
        render_slug=payload["render_slug"],
        local_dir=payload["local_dir"],
        deck_id=payload.get("deck_id"),
        pptx_path=payload.get("pptx_path"),
        deck_title=payload.get("deck_title"),
        pdf_path=None,
        outline_path=None,
    )


def _cmd_trash_existing_render(runner: SlidesRunner, payload: dict) -> dict[str, Any]:
    mirror = _make_mirror(runner._drive)
    existing = mirror.find_render_folder(
        payload["brand"], payload["kind"], payload["render_slug"]
    )
    if existing is None:
        return {"trashed_folder_id": None}
    mirror.trash_render_folder(existing)
    return {"trashed_folder_id": existing}


def _next_versioned_slug(
    mirror: DriveFolderMirror, brand: str, kind: str, base_slug: str
) -> str:
    """Find first ``{base_slug}-v{N}`` (N>=2) that doesn't exist yet."""
    n = 2
    while True:
        candidate = f"{base_slug}-v{n}"
        if mirror.find_render_folder(brand, kind, candidate) is None:
            return candidate
        n += 1


def _cmd_replace_render(runner: SlidesRunner, payload: dict) -> dict[str, Any]:
    """Trash-and-mirror (default) or keep-alongside as a versioned sibling.

    Strategy ``trash``: trash the existing render folder for this slug (if
    any), then mirror normally. Strategy ``keep_alongside``: skip trashing;
    write to a ``{slug}-v2`` (or v3, …) folder instead. Both end with a
    fresh local ``.slides.url`` pointer file.

    Like the underlying mirror commands, this accepts either ``pptx_path``
    (preferred — canonical PPTX-import path) or ``deck_id`` (deprecated
    direct-create fallback). When both are present, ``pptx_path`` wins.
    """
    mirror = _make_mirror(runner._drive)
    strategy = payload.get("strategy", "trash")
    if strategy not in ("trash", "keep_alongside"):
        raise ValueError(
            f"strategy must be 'trash' or 'keep_alongside', got {strategy!r}"
        )

    brand = payload["brand"]
    kind = payload.get("kind", "presentations")
    base_slug = payload["render_slug"]
    original_slug_if_versioned: Optional[str] = None

    if strategy == "trash":
        existing = mirror.find_render_folder(brand, kind, base_slug)
        if existing is not None:
            mirror.trash_render_folder(existing)
        target_slug = base_slug
    else:  # keep_alongside
        existing = mirror.find_render_folder(brand, kind, base_slug)
        if existing is None:
            target_slug = base_slug  # nothing alongside; just use base
        else:
            original_slug_if_versioned = base_slug
            target_slug = _next_versioned_slug(mirror, brand, kind, base_slug)

    result = _mirror_into_folder(
        runner,
        mirror,
        brand=brand,
        kind=kind,
        render_slug=target_slug,
        local_dir=payload["local_dir"],
        deck_id=payload.get("deck_id"),
        pptx_path=payload.get("pptx_path"),
        deck_title=payload.get("deck_title"),
        pdf_path=payload.get("pdf_path"),
        outline_path=payload.get("outline_path"),
    )
    result["strategy_used"] = strategy
    result["render_slug"] = target_slug
    result["original_slug_if_versioned"] = original_slug_if_versioned
    return result


COMMANDS: dict[str, Callable[[SlidesRunner, dict], dict[str, Any]]] = {
    "create_deck": _cmd_create_deck,
    "apply_batch_update": _cmd_apply_batch_update,
    "move_to_folder": _cmd_move_to_folder,
    "ensure_render_folder": _cmd_ensure_render_folder,
    "mirror_presentation": _cmd_mirror_presentation,
    "mirror_template_sample": _cmd_mirror_template_sample,
    "trash_existing_render": _cmd_trash_existing_render,
    "replace_render": _cmd_replace_render,
}


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) != 1 or argv[0] not in COMMANDS:
        print(
            f"usage: slides.cli <{ '|'.join(COMMANDS) }>",
            file=sys.stderr,
        )
        return 1

    command = argv[0]
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        json.dump(
            {"error": {"type": "JSONDecodeError", "message": str(exc), "status": None}},
            sys.stdout,
        )
        sys.stdout.write("\n")
        return 1

    try:
        slides_service, drive_service = build_services()
        runner = SlidesRunner(slides_service, drive_service)
        result = COMMANDS[command](runner, payload)
    except Exception as exc:  # noqa: BLE001 — surface everything as JSON
        # googleapiclient.errors.HttpError carries .resp.status
        status = getattr(getattr(exc, "resp", None), "status", None)
        json.dump(
            {
                "error": {
                    "type": exc.__class__.__name__,
                    "message": str(exc),
                    "status": status,
                }
            },
            sys.stdout,
        )
        sys.stdout.write("\n")
        return 1

    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
