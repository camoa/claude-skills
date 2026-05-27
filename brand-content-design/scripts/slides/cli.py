"""Stdin/stdout JSON adapter around :class:`slides.runner.SlidesRunner`.

Each command reads a JSON object from stdin and writes a JSON object to
stdout. Logs go to stderr. Exit code is ``0`` on success, ``1`` on any error.

Usage::

    python -m slides.cli create_deck       <<< '{"title": "My deck"}'
    python -m slides.cli apply_batch_update <<< '{"deck_id": "...", "requests": [...]}'
    python -m slides.cli move_to_folder    <<< '{"deck_id": "...", "folder_id": "..."}'

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


def _mirror_into_folder(
    runner: SlidesRunner,
    mirror: DriveFolderMirror,
    *,
    brand: str,
    kind: str,
    render_slug: str,
    local_dir: str,
    deck_id: str,
    pdf_path: Optional[str],
    outline_path: Optional[str],
) -> dict[str, Any]:
    """Shared body of mirror_presentation / mirror_template_sample.

    Creates the Drive render folder, reparents the deck into it, optionally
    uploads PDF and outline.md, and writes the local ``.slides.url`` pointer
    file. PDF/outline are skipped when their paths are absent or empty —
    that is how the templates flow opts out of mirroring source files per
    the epic alignment.
    """
    folder_id = mirror.ensure_render_folder(brand, kind, render_slug)
    runner.move_to_folder(deck_id, folder_id)

    pdf_file_id: Optional[str] = None
    outline_file_id: Optional[str] = None
    drive_service = runner._drive  # already authenticated
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
    mirror = _make_mirror(runner._drive)
    return _mirror_into_folder(
        runner,
        mirror,
        brand=payload["brand"],
        kind="presentations",
        render_slug=payload["render_slug"],
        local_dir=payload["local_dir"],
        deck_id=payload["deck_id"],
        pdf_path=payload.get("pdf_path"),
        outline_path=payload.get("outline_path"),
    )


def _cmd_mirror_template_sample(runner: SlidesRunner, payload: dict) -> dict[str, Any]:
    """Templates flow: ONLY mirrors the Slides deck — no PDF, no outline.

    Per the epic alignment, templates' source files (template.md,
    canvas-philosophy.md, sample.pdf, sample.pptx) stay local; only the
    sample.slides deck is in Drive.
    """
    mirror = _make_mirror(runner._drive)
    return _mirror_into_folder(
        runner,
        mirror,
        brand=payload["brand"],
        kind="templates",
        render_slug=payload["render_slug"],
        local_dir=payload["local_dir"],
        deck_id=payload["deck_id"],
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
        deck_id=payload["deck_id"],
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
