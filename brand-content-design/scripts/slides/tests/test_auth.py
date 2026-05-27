"""Unit tests for slides.auth — mocked, no network."""

from __future__ import annotations

from unittest.mock import patch, MagicMock

import pytest

from slides import auth


# ---------------------------------------------------------------- resolve_mode

def test_resolve_mode_service_account_wins_over_oauth():
    env = {
        "BCD_SLIDES_SA_KEY_FILE": "/tmp/key.json",
        "BCD_SLIDES_OAUTH_CLIENT_ID": "id",
        "BCD_SLIDES_OAUTH_CLIENT_SECRET": "sec",
        "BCD_SLIDES_OAUTH_REFRESH_TOKEN": "tok",
    }
    assert auth.resolve_mode(env) == "service-account"


def test_resolve_mode_service_account_only():
    env = {"BCD_SLIDES_SA_KEY_FILE": "/tmp/key.json"}
    assert auth.resolve_mode(env) == "service-account"


def test_resolve_mode_oauth_complete_trio():
    env = {
        "BCD_SLIDES_OAUTH_CLIENT_ID": "id",
        "BCD_SLIDES_OAUTH_CLIENT_SECRET": "sec",
        "BCD_SLIDES_OAUTH_REFRESH_TOKEN": "tok",
    }
    assert auth.resolve_mode(env) == "oauth"


@pytest.mark.parametrize(
    "partial",
    [
        {"BCD_SLIDES_OAUTH_CLIENT_ID": "id"},
        {"BCD_SLIDES_OAUTH_CLIENT_SECRET": "sec"},
        {"BCD_SLIDES_OAUTH_REFRESH_TOKEN": "tok"},
        {"BCD_SLIDES_OAUTH_CLIENT_ID": "id", "BCD_SLIDES_OAUTH_CLIENT_SECRET": "sec"},
    ],
)
def test_resolve_mode_incomplete_oauth_trio_raises(partial):
    with pytest.raises(RuntimeError, match="Incomplete OAuth"):
        auth.resolve_mode(partial)


def test_resolve_mode_nothing_set_raises():
    with pytest.raises(RuntimeError, match="No credentials"):
        auth.resolve_mode({})


# ---------------------------------------------------------------- build_services

def test_build_services_oauth_path_calls_credentials_and_build():
    env = {
        "BCD_SLIDES_OAUTH_CLIENT_ID": "id",
        "BCD_SLIDES_OAUTH_CLIENT_SECRET": "sec",
        "BCD_SLIDES_OAUTH_REFRESH_TOKEN": "tok",
    }
    fake_creds = MagicMock(name="oauth_creds")
    fake_slides = MagicMock(name="slides_service")
    fake_drive = MagicMock(name="drive_service")

    with patch.object(auth, "OAuthCredentials", return_value=fake_creds) as ctor, \
         patch.object(auth, "build", side_effect=[fake_slides, fake_drive]) as build_mock:
        slides_svc, drive_svc = auth.build_services(env)

    assert slides_svc is fake_slides
    assert drive_svc is fake_drive
    # OAuth ctor got the trio + scopes + token_uri
    kwargs = ctor.call_args.kwargs
    assert kwargs["refresh_token"] == "tok"
    assert kwargs["client_id"] == "id"
    assert kwargs["client_secret"] == "sec"
    assert kwargs["token_uri"] == "https://oauth2.googleapis.com/token"
    assert kwargs["scopes"] == auth.SCOPES
    # build() called twice with right service names
    assert build_mock.call_args_list[0].args[0] == "slides"
    assert build_mock.call_args_list[1].args[0] == "drive"
    for call in build_mock.call_args_list:
        assert call.kwargs["credentials"] is fake_creds
        assert call.kwargs["cache_discovery"] is False


def test_build_services_service_account_path():
    env = {"BCD_SLIDES_SA_KEY_FILE": "/tmp/key.json"}
    fake_creds = MagicMock(name="sa_creds")
    fake_slides = MagicMock(name="slides_service")
    fake_drive = MagicMock(name="drive_service")

    with patch.object(
        auth.SACredentials, "from_service_account_file", return_value=fake_creds
    ) as sa_ctor, patch.object(
        auth, "build", side_effect=[fake_slides, fake_drive]
    ):
        slides_svc, drive_svc = auth.build_services(env)

    assert slides_svc is fake_slides
    assert drive_svc is fake_drive
    sa_ctor.assert_called_once_with("/tmp/key.json", scopes=auth.SCOPES)
