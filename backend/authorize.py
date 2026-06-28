"""One-time Google OAuth consent for Lumis.

Run once before starting the server:

    cd backend && source venv/bin/activate && python authorize.py

It opens a browser, you grant access, and a token.json is written. The server
then uses that token automatically.
"""
from google_svc import authorize_interactive

if __name__ == "__main__":
    authorize_interactive()
    print("\n✅ Google authorized. token.json written. You can start the server now.")
