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
import sys
from typing import Any, Callable

from slides.auth import build_services
from slides.runner import SlidesRunner


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


COMMANDS: dict[str, Callable[[SlidesRunner, dict], dict[str, Any]]] = {
    "create_deck": _cmd_create_deck,
    "apply_batch_update": _cmd_apply_batch_update,
    "move_to_folder": _cmd_move_to_folder,
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
