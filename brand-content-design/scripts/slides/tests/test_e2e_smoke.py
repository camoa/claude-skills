"""End-to-end smoke test against the real Google Slides + Drive APIs.

Skipped automatically if credentials env vars are absent. When credentials are
present, this test:

  1. Authenticates via :func:`slides.auth.build_services`.
  2. Creates a blank deck.
  3. Inserts a text box containing a known literal via batchUpdate.
  4. Reads the deck back and asserts the literal text is present.
  5. Trashes the deck so the run leaves no orphaned Drive artifacts.

Exposes the deck id to stderr (redacted) for audit purposes.
"""

from __future__ import annotations

import os
import sys

import pytest

from slides.auth import build_services, resolve_mode
from slides.runner import SlidesRunner


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


SMOKE_LITERAL = "smoke test 2026-05-26"


def _redact(deck_id: str) -> str:
    if len(deck_id) <= 8:
        return "***"
    return f"{deck_id[:4]}...{deck_id[-4:]}"


def test_real_create_update_read_trash():
    mode = resolve_mode()
    print(f"[smoke] auth mode: {mode}", file=sys.stderr)

    slides_svc, drive_svc = build_services()
    runner = SlidesRunner(slides_svc, drive_svc)

    deck_id = runner.create_deck(f"camoa-skills smoke {SMOKE_LITERAL}")
    print(f"[smoke] created deck: {_redact(deck_id)}", file=sys.stderr)

    try:
        # Find the first slide id so we can scope the text box to it.
        presentation = (
            slides_svc.presentations().get(presentationId=deck_id).execute()
        )
        first_slide_id = presentation["slides"][0]["objectId"]

        # Insert a text box on the first slide and write the literal into it.
        text_box_id = "smoke_text_box_1"
        requests = [
            {
                "createShape": {
                    "objectId": text_box_id,
                    "shapeType": "TEXT_BOX",
                    "elementProperties": {
                        "pageObjectId": first_slide_id,
                        "size": {
                            "height": {"magnitude": 50, "unit": "PT"},
                            "width": {"magnitude": 400, "unit": "PT"},
                        },
                        "transform": {
                            "scaleX": 1,
                            "scaleY": 1,
                            "translateX": 100,
                            "translateY": 100,
                            "unit": "PT",
                        },
                    },
                },
            },
            {
                "insertText": {
                    "objectId": text_box_id,
                    "insertionIndex": 0,
                    "text": SMOKE_LITERAL,
                },
            },
        ]
        runner.apply_batch_update(deck_id, requests)

        # Read back and assert.
        deck = slides_svc.presentations().get(presentationId=deck_id).execute()
        found = False
        for slide in deck.get("slides", []):
            for element in slide.get("pageElements", []):
                shape = element.get("shape") or {}
                text_content = shape.get("text") or {}
                for run in text_content.get("textElements", []):
                    text_run = run.get("textRun")
                    if text_run and SMOKE_LITERAL in text_run.get("content", ""):
                        found = True
                        break
        assert found, f"Literal '{SMOKE_LITERAL}' not found in deck {deck_id}"
        print(f"[smoke] verified literal in deck: {_redact(deck_id)}", file=sys.stderr)

    finally:
        # Trash the deck to leave no orphans.
        drive_svc.files().update(
            fileId=deck_id, body={"trashed": True}
        ).execute()
        print(f"[smoke] trashed deck: {_redact(deck_id)}", file=sys.stderr)
