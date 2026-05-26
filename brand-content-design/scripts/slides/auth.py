"""Authenticate to Google Slides + Drive from environment variables.

Two modes per ``brand-content-design/references/slides-credentials.md``:

* **Service account** — ``BCD_SLIDES_SA_KEY_FILE`` set.
* **OAuth refresh-token** — all three of
  ``BCD_SLIDES_OAUTH_CLIENT_ID``, ``BCD_SLIDES_OAUTH_CLIENT_SECRET``,
  ``BCD_SLIDES_OAUTH_REFRESH_TOKEN`` set.

Service account wins when both are configured. An incomplete OAuth trio is a
hard error — the runner refuses to start rather than silently falling back.
"""

from __future__ import annotations

import os
from typing import Literal, Tuple

from google.oauth2.credentials import Credentials as OAuthCredentials
from google.oauth2.service_account import Credentials as SACredentials
from googleapiclient.discovery import build


#: Default OAuth scopes — narrowest workable set per the credentials reference.
SCOPES: list[str] = [
    "https://www.googleapis.com/auth/presentations",
    "https://www.googleapis.com/auth/drive.file",
]


# Re-exported so unit tests can monkey-patch via ``patch.object(auth, ...)``.
__all__ = [
    "SCOPES",
    "OAuthCredentials",
    "SACredentials",
    "build",
    "build_services",
    "resolve_mode",
]


def resolve_mode(env: dict | None = None) -> Literal["service-account", "oauth"]:
    """Pick the auth mode from environment variables.

    Service account wins when both are set. Raises :class:`RuntimeError` for
    an incomplete OAuth trio or when nothing is configured.
    """
    if env is None:
        env = os.environ

    if env.get("BCD_SLIDES_SA_KEY_FILE"):
        return "service-account"

    trio = [
        env.get("BCD_SLIDES_OAUTH_CLIENT_ID"),
        env.get("BCD_SLIDES_OAUTH_CLIENT_SECRET"),
        env.get("BCD_SLIDES_OAUTH_REFRESH_TOKEN"),
    ]
    if any(trio):
        if not all(trio):
            raise RuntimeError(
                "Incomplete OAuth configuration: set all of "
                "BCD_SLIDES_OAUTH_CLIENT_ID, BCD_SLIDES_OAUTH_CLIENT_SECRET, "
                "and BCD_SLIDES_OAUTH_REFRESH_TOKEN."
            )
        return "oauth"

    raise RuntimeError(
        "No credentials found. Set BCD_SLIDES_SA_KEY_FILE for a service "
        "account, or the BCD_SLIDES_OAUTH_CLIENT_ID/"
        "BCD_SLIDES_OAUTH_CLIENT_SECRET/BCD_SLIDES_OAUTH_REFRESH_TOKEN trio "
        "for OAuth."
    )


def _build_credentials(env: dict):
    """Build google-auth credentials per the resolved mode."""
    mode = resolve_mode(env)
    if mode == "service-account":
        return SACredentials.from_service_account_file(
            env["BCD_SLIDES_SA_KEY_FILE"], scopes=SCOPES
        )
    # OAuth refresh-token: token=None forces refresh on first API call.
    return OAuthCredentials(
        token=None,
        refresh_token=env["BCD_SLIDES_OAUTH_REFRESH_TOKEN"],
        token_uri="https://oauth2.googleapis.com/token",
        client_id=env["BCD_SLIDES_OAUTH_CLIENT_ID"],
        client_secret=env["BCD_SLIDES_OAUTH_CLIENT_SECRET"],
        scopes=SCOPES,
    )


def build_services(env: dict | None = None) -> Tuple[object, object]:
    """Return ``(slides_service, drive_service)``.

    Both are ``googleapiclient.discovery.Resource`` instances built with
    ``cache_discovery=False`` to avoid ``oauth2client`` cache warnings.
    """
    if env is None:
        env = os.environ
    creds = _build_credentials(env)
    slides_service = build("slides", "v1", credentials=creds, cache_discovery=False)
    drive_service = build("drive", "v3", credentials=creds, cache_discovery=False)
    return slides_service, drive_service
