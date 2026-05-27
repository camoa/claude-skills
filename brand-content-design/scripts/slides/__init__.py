"""Thin Python runner for Google Slides + Drive operations.

Single responsibility: turn a Slides ``batchUpdate`` payload (supplied by the
caller) into an executed Slides API call, returning the deck URL.

This package deliberately does NOT include:

* LLM authoring of ``batchUpdate`` requests — that is the caller's job
  (see subtask ``slides_llm_authoring``).
* Drive folder conventions, trash-and-recreate, ``.slides.url`` pointer files,
  or command-md integration — those land in ``slides_drive_mirroring``.

Public API:

* :func:`slides.auth.build_services` — env vars → ``(slides_service, drive_service)``.
* :func:`slides.auth.resolve_mode` — env-var routing.
* :class:`slides.runner.SlidesRunner` — execute Slides + Drive calls.
"""

from slides.auth import SCOPES, build_services, resolve_mode
from slides.runner import SlidesRunner

__all__ = ["SCOPES", "SlidesRunner", "build_services", "resolve_mode"]
