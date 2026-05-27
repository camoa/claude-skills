# `slides/` — thin Google Slides + Drive runner

A narrow Python package that authenticates to Google and executes Slides API
operations on behalf of the `brand-content-design` plugin. Single
responsibility: turn a Slides `batchUpdate` payload (supplied by the caller)
into an executed API call.

**Out of scope** (lives in sibling subtasks):

- Authoring the `batchUpdate` request list (LLM-driven — subtask
  `slides_llm_authoring`).
- Drive folder conventions, trash-and-recreate, `.slides.url` pointer files,
  command-md wiring (subtask `slides_drive_mirroring`).

## Install

```sh
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
```

## Credentials

See `brand-content-design/references/slides-credentials.md` for the full env-var
contract. In short: set either `BCD_SLIDES_SA_KEY_FILE` (service account) or
the OAuth trio (`BCD_SLIDES_OAUTH_CLIENT_ID` / `..._CLIENT_SECRET` /
`..._REFRESH_TOKEN`). Service account wins when both are set.

## Python API

```python
from slides import build_services, SlidesRunner

slides_service, drive_service = build_services()
runner = SlidesRunner(slides_service, drive_service)

deck_id = runner.create_deck("My deck")
runner.apply_batch_update(deck_id, requests=[ ... ])   # caller authors requests
runner.move_to_folder(deck_id, folder_id="<drive-folder-id>")

print(SlidesRunner.deck_url(deck_id))
```

## CLI

The CLI is a thin stdin → stdout JSON adapter — useful for command-md
integrations that shell out without importing Python.

```sh
# Create a deck
echo '{"title": "My deck"}' \
  | python -m slides.cli create_deck
# → {"deck_id": "...", "deck_url": "https://docs.google.com/presentation/d/.../edit"}

# Apply a batchUpdate
echo '{"deck_id": "...", "requests": [ ... ]}' \
  | python -m slides.cli apply_batch_update
# → {"replies": [...]}    (Slides API response, passed through)

# Move into a Drive folder
echo '{"deck_id": "...", "folder_id": "..."}' \
  | python -m slides.cli move_to_folder
# → {"deck_id": "...", "folder_id": "..."}
```

On error:

```json
{"error": {"type": "HttpError", "message": "...", "status": 403}}
```

with exit code `1`. Logs go to stderr.

## Tests

```sh
# Unit (mocked) tests — no network:
pytest brand-content-design/scripts/slides/tests/test_auth.py \
       brand-content-design/scripts/slides/tests/test_runner.py

# Real-API smoke (skips if no credentials in env):
pytest brand-content-design/scripts/slides/tests/test_e2e_smoke.py -s
```
