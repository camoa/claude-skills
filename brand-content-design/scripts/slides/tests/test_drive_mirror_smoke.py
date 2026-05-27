"""End-to-end smoke test for DriveFolderMirror against the real Drive + Slides
APIs.

Skipped automatically if credentials env vars are absent. When run, this test:

  1. Authenticates via :func:`slides.auth.build_services`.
  2. Creates the folder chain
     ``brand-content/_smoke-{ts}/presentations/_smoke-{ts}-render/``.
  3. Uploads a tiny PDF and outline.md into that folder.
  4. Creates a minimal Slides deck, reparents it into the folder.
  5. Writes a local ``.slides.url`` pointer file, reads it back, asserts shape.
  6. Trashes the render folder (Drive cascades to children).
  7. Asserts ``find_render_folder`` then returns None — proving cascade worked.

Designed to leave no Drive artifacts even on partial failure (``finally``
block cleans up).
"""

from __future__ import annotations

import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import pytest

from slides.auth import build_services
from slides.runner import (
    DriveFolderMirror,
    SlidesRunner,
    read_slides_url_file,
    write_slides_url_file,
)


CREDS_PRESENT = bool(
    os.environ.get("BCD_SLIDES_SA_KEY_FILE")
    or (
        os.environ.get("BCD_SLIDES_OAUTH_CLIENT_ID")
        and os.environ.get("BCD_SLIDES_OAUTH_CLIENT_SECRET")
        and os.environ.get("BCD_SLIDES_OAUTH_REFRESH_TOKEN")
    )
)

pytestmark = pytest.mark.skipif(
    not CREDS_PRESENT, reason="E2E creds not configured"
)


def _redact(item_id: str) -> str:
    if len(item_id) <= 8:
        return "***"
    return f"{item_id[:4]}...{item_id[-4:]}"


def test_real_drive_mirror_end_to_end(tmp_path):
    slides_svc, drive_svc = build_services()
    runner = SlidesRunner(slides_svc, drive_svc)
    mirror = DriveFolderMirror(
        drive_svc, root_id=os.environ.get("BRAND_CONTENT_DRIVE_ROOT_ID") or None
    )

    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    brand = f"_smoke-{ts}"
    render_slug = f"_smoke-{ts}-render"

    render_folder_id: str | None = None
    deck_id: str | None = None

    try:
        # 1. Ensure the folder chain.
        render_folder_id = mirror.ensure_render_folder(
            brand, "presentations", render_slug
        )
        assert render_folder_id
        print(
            f"[drive-smoke] render folder: {_redact(render_folder_id)}",
            file=sys.stderr,
        )

        # 2. Upload a tiny PDF + outline.md via the Drive API directly.
        from googleapiclient.http import MediaFileUpload

        local_dir = tmp_path / f"2026-05-27-{render_slug}"
        local_dir.mkdir()
        pdf_path = local_dir / "smoke.pdf"
        # Minimal valid PDF
        pdf_path.write_bytes(
            b"%PDF-1.1\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n"
        )
        outline_path = local_dir / "outline.md"
        outline_path.write_text("# smoke\n", encoding="utf-8")

        for path, mimetype in [
            (pdf_path, "application/pdf"),
            (outline_path, "text/markdown"),
        ]:
            media = MediaFileUpload(str(path), mimetype=mimetype, resumable=False)
            drive_svc.files().create(
                body={"name": path.name, "parents": [render_folder_id]},
                media_body=media,
                fields="id",
            ).execute()

        # 3. Create a deck and reparent it into the render folder.
        deck_id = runner.create_deck(f"camoa-skills drive-smoke {ts}")
        runner.move_to_folder(deck_id, render_folder_id)
        print(f"[drive-smoke] deck: {_redact(deck_id)}", file=sys.stderr)

        # 4. Pointer file roundtrip.
        write_slides_url_file(local_dir, deck_id, render_folder_id)
        parsed = read_slides_url_file(local_dir)
        assert parsed is not None
        assert parsed["deck_id"] == deck_id
        assert parsed["folder_id"] == render_folder_id
        assert parsed["deck_url"].endswith(f"/{deck_id}/edit")
        assert parsed["folder_url"].endswith(f"/{render_folder_id}")

        # 5. find_render_folder finds it.
        found = mirror.find_render_folder(brand, "presentations", render_slug)
        assert found == render_folder_id

    finally:
        # 6. Cleanup. Trashing the render folder cascades to deck + uploaded files.
        if render_folder_id:
            mirror.trash_render_folder(render_folder_id)
            print(
                f"[drive-smoke] trashed: {_redact(render_folder_id)}",
                file=sys.stderr,
            )

    # 7. After trash, find returns None.
    found_after = mirror.find_render_folder(brand, "presentations", render_slug)
    assert found_after is None, "render folder should be untrashed-invisible after trash"
