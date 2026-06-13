"""Google OAuth + service builder for Slides.

Auth model: a one-time interactive consent (run `python authorize.py`) writes
`token.json`. The server then loads/refreshes that token non-interactively so
request handlers never block on a browser consent flow.

(Spreadsheets are handled locally via Apple Numbers, so only the Slides scope
is requested here.)
"""
import logging
import os

logger = logging.getLogger("felix.google")

CREDENTIALS_FILE = os.getenv("GOOGLE_CREDENTIALS_FILE", "credentials.json")
TOKEN_FILE = os.getenv("GOOGLE_TOKEN_FILE", "token.json")

SCOPES = [
    "https://www.googleapis.com/auth/presentations",
]


def authorize_interactive():
    """Run the one-time OAuth consent flow and persist token.json."""
    from google_auth_oauthlib.flow import InstalledAppFlow

    if not os.path.exists(CREDENTIALS_FILE):
        raise FileNotFoundError(
            f"Missing {CREDENTIALS_FILE}. Download an OAuth client (Desktop app) "
            "from Google Cloud Console and save it as backend/credentials.json."
        )
    flow = InstalledAppFlow.from_client_secrets_file(CREDENTIALS_FILE, SCOPES)
    creds = flow.run_local_server(port=0)
    with open(TOKEN_FILE, "w") as f:
        f.write(creds.to_json())
    logger.info("Saved Google token to %s", TOKEN_FILE)
    return creds


def get_credentials():
    """Load cached credentials, refreshing if expired. Never blocks on consent."""
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request

    if not os.path.exists(TOKEN_FILE):
        raise RuntimeError(
            "Google not authorized yet. Run `python authorize.py` in the backend "
            "directory once to grant access (needs credentials.json present)."
        )

    creds = Credentials.from_authorized_user_file(TOKEN_FILE, SCOPES)
    if not creds.valid:
        if creds.expired and creds.refresh_token:
            creds.refresh(Request())
            with open(TOKEN_FILE, "w") as f:
                f.write(creds.to_json())
        else:
            raise RuntimeError(
                "Google token is invalid/expired without a refresh token. "
                "Re-run `python authorize.py`."
            )
    return creds


def slides_service():
    from googleapiclient.discovery import build

    return build("slides", "v1", credentials=get_credentials(), cache_discovery=False)
