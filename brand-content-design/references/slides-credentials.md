# Google Slides + Drive credentials

Setup reference for the Google Slides output of `/template-presentation` and
`/presentation`. Read this once when you wire credentials; the Python runner
that ships in a follow-up subtask consumes the same env vars.

Credentials come **only** from environment variables — never committed, never
hard-coded. The plugin's `.gitignore` already excludes `*-key.json`,
`service-account*.json`, and `.env*`; keep it that way.

## Which mode should I use?

Two auth paths are supported. The **service account wins** when both are set.

| Situation | Use | Why |
|---|---|---|
| Personal Google account (`@gmail.com`) | **OAuth refresh-token** | Decks land in *your own* Drive UI. A service account has its own Drive with no browsable UI, and the clean fix (a Shared Drive) requires Workspace. |
| Google Workspace account | **Service account + Shared Drive** | No consent screen, no refresh token to rotate; pair it with a Shared Drive so files are visible to humans. |
| Unattended CI | **Service account** | Same as Workspace — no interactive consent. |

Heads-up: some Google Cloud projects have the
`iam.disableServiceAccountKeyCreation` org policy on, which greys out JSON-key
creation — yet another reason OAuth is the smoother path for an individual.

## OAuth refresh-token setup (recommended for personal accounts)

One-time, in [console.cloud.google.com](https://console.cloud.google.com):

1. Create or pick a project. Under **APIs & Services → Library** enable
   **both** the **Google Slides API** and the **Google Drive API**.
2. **APIs & Services → OAuth consent screen** — configure the consent screen
   and add yourself as a test user.
3. **APIs & Services → Credentials → Create credentials → OAuth client ID →
   Desktop app**. Note the client id and client secret.
4. Mint a refresh token in the
   [OAuth 2.0 Playground](https://developers.google.com/oauthplayground):
   1. Click ⚙ (top right) → check **Use your own OAuth credentials** → paste
      your client id + secret.
   2. In the left-hand scope list, enter both scopes manually:
      - `https://www.googleapis.com/auth/presentations`
      - `https://www.googleapis.com/auth/drive.file`
   3. Click **Authorize APIs** → sign in with your Google account → grant
      consent.
   4. Click **Exchange authorization code for tokens** — copy the
      **refresh token**.
5. Export the trio:

   ```sh
   export BCD_SLIDES_OAUTH_CLIENT_ID=...
   export BCD_SLIDES_OAUTH_CLIENT_SECRET=...
   export BCD_SLIDES_OAUTH_REFRESH_TOKEN=...
   ```

## Service-account setup (recommended for Workspace / CI)

1. Enable **Google Slides API** + **Google Drive API** as above.
2. **IAM & Admin → Service Accounts → Create**. Give it a name; no special
   roles are required for Drive/Slides API access against shared files.
3. On the new service account → **Keys → Add key → Create new key → JSON**.
   Save the downloaded file somewhere outside the repo.
4. Export the key path:

   ```sh
   export BCD_SLIDES_SA_KEY_FILE=/abs/path/to/service-account-key.json
   ```

5. **Give the service account access to the files it will touch.** Pick one:
   - Share the template presentation (and any pre-created output folder) with
     the service account's email as **Editor**.
   - OR use a **Shared Drive** (Workspace only) the service account is a
     member of.
   - OR configure domain-wide delegation (Workspace admin).

### Drive visibility gotcha (read this)

**Files the service account creates land in the service account's own Drive,
which has no UI.** Without intervention, you will create decks you cannot find
through `drive.google.com`.

Fix one of three ways:

- **Best:** create everything inside a folder you own and shared with the
  service account as **Editor**. Pass that folder id as the Drive parent
  when creating files.
- **Workspace only:** use a **Shared Drive** the service account is a member of.
- **Last resort:** transfer ownership of each created file back to a human
  account via the Drive API (`drive.permissions.transferOwnership`) — fragile
  and only works inside the same domain.

## Env-var contract

| Env var | Used by | Required when |
|---|---|---|
| `BCD_SLIDES_SA_KEY_FILE` | service-account path | service-account mode |
| `BCD_SLIDES_OAUTH_CLIENT_ID` | OAuth path | OAuth mode (all three required together) |
| `BCD_SLIDES_OAUTH_CLIENT_SECRET` | OAuth path | OAuth mode |
| `BCD_SLIDES_OAUTH_REFRESH_TOKEN` | OAuth path | OAuth mode |

Rules:
- Service account **wins** when both are set.
- An incomplete OAuth trio is a hard error — the runner refuses to start
  rather than silently falling back.
- Default scopes (narrowest workable):
  - `https://www.googleapis.com/auth/presentations`
  - `https://www.googleapis.com/auth/drive.file`

## Python wire-up snippets

The Python runner is implemented in a follow-up subtask
(`slides_python_runner`). Keep these snippets as the canonical wire-up the
runner mirrors.

### Service-account path

```python
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build

SCOPES = [
    "https://www.googleapis.com/auth/presentations",
    "https://www.googleapis.com/auth/drive.file",
]

creds = Credentials.from_service_account_file(
    os.environ["BCD_SLIDES_SA_KEY_FILE"],
    scopes=SCOPES,
)

slides = build("slides", "v1", credentials=creds, cache_discovery=False)
drive = build("drive", "v3", credentials=creds, cache_discovery=False)
```

### OAuth refresh-token path

```python
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

SCOPES = [
    "https://www.googleapis.com/auth/presentations",
    "https://www.googleapis.com/auth/drive.file",
]

creds = Credentials(
    token=None,  # forces refresh on first call
    refresh_token=os.environ["BCD_SLIDES_OAUTH_REFRESH_TOKEN"],
    token_uri="https://oauth2.googleapis.com/token",
    client_id=os.environ["BCD_SLIDES_OAUTH_CLIENT_ID"],
    client_secret=os.environ["BCD_SLIDES_OAUTH_CLIENT_SECRET"],
    scopes=SCOPES,
)

slides = build("slides", "v1", credentials=creds, cache_discovery=False)
drive = build("drive", "v3", credentials=creds, cache_discovery=False)
```

The OAuth refresh token already encodes its granted scopes; passing `scopes=`
on construction is for the client's own bookkeeping, not a re-grant.

### Mode-selection helper

```python
import os

def resolve_mode(env=os.environ):
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
```

## Troubleshooting

- **"File not found" or "Insufficient permissions" against a real file id** —
  the `drive.file` scope only covers files the app itself created or opened
  through a Google Picker. A hand-built seed template you authored in the
  Drive UI won't be visible under `drive.file`. Either:
  - share that template with the service-account email (or your OAuth user),
    explicitly, OR
  - request the broader `https://www.googleapis.com/auth/drive` scope (and
    re-mint the refresh token).
- **JSON-key creation is greyed out in Google Cloud Console** — the project
  has the `iam.disableServiceAccountKeyCreation` org policy. Use OAuth
  refresh-token mode instead, or get the policy lifted by an org admin.
- **The deck was created but I can't find it in `drive.google.com`** — you're
  on the service-account path and didn't parent the file into a folder a
  human can see. See "Drive visibility gotcha" above.
- **`invalid_grant` on refresh** — the refresh token was revoked (password
  reset, prolonged inactivity past Google's 6-month idle limit for unverified
  apps, or you re-minted credentials). Re-run the OAuth Playground steps.
