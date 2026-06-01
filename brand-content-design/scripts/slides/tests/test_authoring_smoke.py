"""End-to-end validation proof for ``references/slides-batchupdate-authoring.md``.

This test walks the authoring guide's end-to-end worked example
(a 1-slide title deck — solid background + kicker + headline) against the
real Google Slides + Drive APIs:

  1. Authenticate via :func:`slides.auth.build_services`.
  2. Create a blank deck.
  3. Apply the hand-authored ``batchUpdate`` from the guide's worked
     example (proves the guide is followable).
  4. Read the deck back; assert the headline + kicker text are present and
     the slide has the expected element count.
  5. Trash the deck so the run leaves no orphaned Drive artifacts.

Print the deck id (redacted) to stderr for audit.

Skipped automatically if credentials env vars are absent.
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


HEADLINE_TEXT = "Where ideas meet form"
KICKER_TEXT = "A SUBTITLE"


def _redact(deck_id: str) -> str:
    if len(deck_id) <= 8:
        return "***"
    return f"{deck_id[:4]}...{deck_id[-4:]}"


def _worked_example_requests(slide_object_id: str) -> list[dict]:
    """Return the exact batchUpdate from the authoring guide's worked example.

    Mirrors ``references/slides-batchupdate-authoring.md`` § End-to-end
    worked example. Re-uses the existing first BLANK slide instead of
    creating a new one (Slides creates a default blank slide when a deck
    is created with no layout, so we author into it rather than appending).
    """
    return [
        # Background — solid light gray rectangle covering the slide.
        {
            "createShape": {
                "objectId": "slide_bg_1",
                "shapeType": "RECTANGLE",
                "elementProperties": {
                    "pageObjectId": slide_object_id,
                    "size": {
                        "width": {"magnitude": 720, "unit": "PT"},
                        "height": {"magnitude": 405, "unit": "PT"},
                    },
                    "transform": {
                        "scaleX": 1,
                        "scaleY": 1,
                        "translateX": 0,
                        "translateY": 0,
                        "unit": "PT",
                    },
                }
            }
        },
        {
            "updateShapeProperties": {
                "objectId": "slide_bg_1",
                "shapeProperties": {
                    "shapeBackgroundFill": {
                        "solidFill": {
                            "color": {
                                "rgbColor": {
                                    "red": 0.949,
                                    "green": 0.949,
                                    "blue": 0.949,
                                }
                            }
                        }
                    },
                    "outline": {
                        "propertyState": "NOT_RENDERED",
                    },
                },
                "fields": "shapeBackgroundFill.solidFill.color,outline.propertyState",
            }
        },
        # Kicker — small, centered, dark gray near top.
        {
            "createShape": {
                "objectId": "kicker_1",
                "shapeType": "TEXT_BOX",
                "elementProperties": {
                    "pageObjectId": slide_object_id,
                    "size": {
                        "width": {"magnitude": 600, "unit": "PT"},
                        "height": {"magnitude": 30, "unit": "PT"},
                    },
                    "transform": {
                        "scaleX": 1,
                        "scaleY": 1,
                        "translateX": 60,
                        "translateY": 117,
                        "unit": "PT",
                    },
                }
            }
        },
        {
            "insertText": {
                "objectId": "kicker_1",
                "insertionIndex": 0,
                "text": KICKER_TEXT,
            }
        },
        {
            "updateTextStyle": {
                "objectId": "kicker_1",
                "style": {
                    "fontFamily": "Inter",
                    "fontSize": {"magnitude": 24, "unit": "PT"},
                    "foregroundColor": {
                        "opaqueColor": {
                            "rgbColor": {"red": 0.4, "green": 0.4, "blue": 0.4}
                        }
                    },
                },
                "textRange": {"type": "ALL"},
                "fields": "fontFamily,fontSize,foregroundColor",
            }
        },
        {
            "updateParagraphStyle": {
                "objectId": "kicker_1",
                "style": {"alignment": "CENTER"},
                "textRange": {"type": "ALL"},
                "fields": "alignment",
            }
        },
        # Headline — large, bold, near-black, centered.
        {
            "createShape": {
                "objectId": "headline_1",
                "shapeType": "TEXT_BOX",
                "elementProperties": {
                    "pageObjectId": slide_object_id,
                    "size": {
                        "width": {"magnitude": 600, "unit": "PT"},
                        "height": {"magnitude": 90, "unit": "PT"},
                    },
                    "transform": {
                        "scaleX": 1,
                        "scaleY": 1,
                        "translateX": 60,
                        "translateY": 163,
                        "unit": "PT",
                    },
                }
            }
        },
        {
            "insertText": {
                "objectId": "headline_1",
                "insertionIndex": 0,
                "text": HEADLINE_TEXT,
            }
        },
        {
            "updateTextStyle": {
                "objectId": "headline_1",
                "style": {
                    "fontFamily": "Inter",
                    "fontSize": {"magnitude": 72, "unit": "PT"},
                    "bold": True,
                    "foregroundColor": {
                        "opaqueColor": {
                            "rgbColor": {
                                "red": 0.102,
                                "green": 0.102,
                                "blue": 0.102,
                            }
                        }
                    },
                },
                "textRange": {"type": "ALL"},
                "fields": "fontFamily,fontSize,bold,foregroundColor",
            }
        },
        {
            "updateParagraphStyle": {
                "objectId": "headline_1",
                "style": {"alignment": "CENTER"},
                "textRange": {"type": "ALL"},
                "fields": "alignment",
            }
        },
    ]


def _collect_text_runs(deck: dict) -> list[str]:
    """Return every text-run content string across every slide / element."""
    texts: list[str] = []
    for slide in deck.get("slides", []):
        for element in slide.get("pageElements", []):
            shape = element.get("shape") or {}
            text_content = shape.get("text") or {}
            for run in text_content.get("textElements", []):
                text_run = run.get("textRun")
                if text_run:
                    texts.append(text_run.get("content", ""))
    return texts


def test_authoring_guide_worked_example_renders():
    """The guide's worked example renders to a real deck with expected content."""
    mode = resolve_mode()
    print(f"[authoring-smoke] auth mode: {mode}", file=sys.stderr)

    slides_svc, drive_svc = build_services()
    runner = SlidesRunner(slides_svc, drive_svc)

    deck_id = runner.create_deck("camoa-skills slides-authoring-smoke")
    deck_url = SlidesRunner.deck_url(deck_id)
    print(
        f"[authoring-smoke] created deck: {_redact(deck_id)} url={deck_url}",
        file=sys.stderr,
    )

    try:
        # Discover the first BLANK slide's objectId (a fresh deck has one).
        presentation = (
            slides_svc.presentations().get(presentationId=deck_id).execute()
        )
        first_slide_id = presentation["slides"][0]["objectId"]

        # Apply the hand-authored batchUpdate from the guide's worked example.
        requests = _worked_example_requests(first_slide_id)
        runner.apply_batch_update(deck_id, requests)

        # Read back and verify.
        deck = (
            slides_svc.presentations().get(presentationId=deck_id).execute()
        )

        # Exactly one slide (the default blank we authored into).
        assert len(deck.get("slides", [])) == 1, (
            f"expected 1 slide, got {len(deck.get('slides', []))}"
        )

        # Headline and kicker text are present verbatim.
        texts = _collect_text_runs(deck)
        joined = " | ".join(t.strip() for t in texts)
        assert any(HEADLINE_TEXT in t for t in texts), (
            f"headline '{HEADLINE_TEXT}' not found in text runs: {joined!r}"
        )
        assert any(KICKER_TEXT in t for t in texts), (
            f"kicker '{KICKER_TEXT}' not found in text runs: {joined!r}"
        )

        # Element count: at least background + headline + kicker = 3.
        element_count = sum(
            len(s.get("pageElements", [])) for s in deck["slides"]
        )
        assert element_count >= 3, (
            f"expected >=3 page elements, got {element_count}"
        )

        print(
            f"[authoring-smoke] verified deck: {_redact(deck_id)} "
            f"elements={element_count}",
            file=sys.stderr,
        )

    finally:
        # Trash the deck to leave no orphans.
        drive_svc.files().update(
            fileId=deck_id, body={"trashed": True}
        ).execute()
        print(
            f"[authoring-smoke] trashed deck: {_redact(deck_id)}",
            file=sys.stderr,
        )
