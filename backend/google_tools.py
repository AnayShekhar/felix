"""Google API tool implementations (replaces the old AppleScript Mac tools).

Every function takes (args, user_id) and returns the standard Lumis result
contract. Authentication uses per-user OAuth credentials from google_oauth; if
the user has no Google API credentials, tools return a clean error contract
(status "error", data.error == "google_not_connected") so the agent can tell the
user to connect Google rather than crashing.

Requires: google-api-python-client, google-auth (see requirements.txt).
"""
import base64
import logging
from email.mime.text import MIMEText
from typing import Optional

import google_oauth
import memory
from google_oauth import GoogleNotConnected

logger = logging.getLogger("lumis.google_tools")


# --------------------------------------------------------------------------- #
# Service builder
# --------------------------------------------------------------------------- #
def _service(user_id: str, api: str, version: str):
    """Build an authenticated googleapiclient service for the user."""
    creds = google_oauth.get_credentials(user_id)  # raises GoogleNotConnected
    try:
        from googleapiclient.discovery import build
    except ImportError as exc:  # pragma: no cover
        raise GoogleNotConnected(
            "google-api-python-client is not installed on the server."
        ) from exc
    return build(api, version, credentials=creds, cache_discovery=False)


def _not_connected_result(tool: str, exc: Exception) -> dict:
    return {
        "tool": tool,
        "status": "error",
        "message": str(exc),
        "title": "Connect Google",
        "speak": "You'll need to connect Google first.",
        "data": {"error": "google_not_connected", "service": "google"},
    }


# --------------------------------------------------------------------------- #
# Docs
# --------------------------------------------------------------------------- #
def docs_create_document(args: dict, user_id: str) -> dict:
    title = str(args.get("title") or "Untitled").strip()
    content = str(args.get("content") or "")
    svc = _service(user_id, "docs", "v1")
    doc = svc.documents().create(body={"title": title}).execute()
    doc_id = doc["documentId"]
    if content:
        svc.documents().batchUpdate(
            documentId=doc_id,
            body={"requests": [{"insertText": {"location": {"index": 1}, "text": content}}]},
        ).execute()
    url = f"https://docs.google.com/document/d/{doc_id}"
    return {"tool": "docs.create_document", "status": "success",
            "title": f"Created '{title}'", "message": f"Created Google Doc '{title}'.",
            "url": url, "speak": "Done — created that doc.",
            "data": {"document_id": doc_id, "url": url}}


def docs_append_text(args: dict, user_id: str) -> dict:
    doc_id = str(args.get("document_id") or "").strip()
    text = str(args.get("content") or args.get("text") or "")
    if not doc_id:
        return {"tool": "docs.append_text", "status": "error",
                "message": "docs.append_text requires a 'document_id'.", "data": {}}
    svc = _service(user_id, "docs", "v1")
    doc = svc.documents().get(documentId=doc_id).execute()
    end = doc.get("body", {}).get("content", [{}])[-1].get("endIndex", 1)
    svc.documents().batchUpdate(
        documentId=doc_id,
        body={"requests": [{"insertText": {"location": {"index": max(1, end - 1)}, "text": "\n" + text}}]},
    ).execute()
    url = f"https://docs.google.com/document/d/{doc_id}"
    return {"tool": "docs.append_text", "status": "success",
            "title": "Appended text", "message": "Appended to the doc.",
            "url": url, "speak": "Added that to the doc.",
            "data": {"document_id": doc_id, "url": url}}


# --------------------------------------------------------------------------- #
# Sheets
# --------------------------------------------------------------------------- #
def sheets_create_spreadsheet(args: dict, user_id: str) -> dict:
    title = str(args.get("title") or "Untitled").strip()
    headers = args.get("headers") or []
    rows = args.get("rows") or []
    svc = _service(user_id, "sheets", "v4")
    ss = svc.spreadsheets().create(body={"properties": {"title": title}}).execute()
    ss_id = ss["spreadsheetId"]
    values = ([headers] if headers else []) + [list(r) for r in rows]
    if values:
        svc.spreadsheets().values().append(
            spreadsheetId=ss_id, range="A1", valueInputOption="USER_ENTERED",
            body={"values": values},
        ).execute()
    url = f"https://docs.google.com/spreadsheets/d/{ss_id}"
    return {"tool": "sheets.create_spreadsheet", "status": "success",
            "title": f"Created '{title}'", "message": f"Created spreadsheet '{title}'.",
            "url": url, "speak": "Created that spreadsheet.",
            "data": {"spreadsheet_id": ss_id, "url": url}}


def sheets_add_row(args: dict, user_id: str) -> dict:
    # Resolve which spreadsheet: explicit id, else the remembered expense sheet.
    ss_id = str(args.get("spreadsheet_id") or "").strip()
    is_expense = bool(args.get("expense"))
    if not ss_id and is_expense:
        ss_id = (memory.get_all() or {}).get("expense_sheet_id", "")
    values = args.get("values") or args.get("row") or []
    if isinstance(values, dict):
        values = list(values.values())

    svc = _service(user_id, "sheets", "v4")
    # Auto-create the expense sheet on first use, then remember it.
    if not ss_id and is_expense:
        created = svc.spreadsheets().create(
            body={"properties": {"title": "Lumis Expenses"}}).execute()
        ss_id = created["spreadsheetId"]
        svc.spreadsheets().values().append(
            spreadsheetId=ss_id, range="A1", valueInputOption="USER_ENTERED",
            body={"values": [["Date", "Merchant", "Category", "Amount", "Notes"]]},
        ).execute()
        try:
            memory.set_pref("expense_sheet_id", ss_id)
        except Exception:  # noqa: BLE001
            pass
    if not ss_id:
        return {"tool": "sheets.add_row", "status": "error",
                "message": "sheets.add_row requires a 'spreadsheet_id'.", "data": {}}

    svc.spreadsheets().values().append(
        spreadsheetId=ss_id, range="A1", valueInputOption="USER_ENTERED",
        body={"values": [list(values)]},
    ).execute()
    url = f"https://docs.google.com/spreadsheets/d/{ss_id}"
    return {"tool": "sheets.add_row", "status": "success", "title": "Row added",
            "message": "Added that row.", "url": url,
            "speak": "Added that to your spreadsheet.",
            "data": {"spreadsheet_id": ss_id, "url": url}}


def sheets_read_sheet(args: dict, user_id: str) -> dict:
    ss_id = str(args.get("spreadsheet_id") or "").strip()
    rng = str(args.get("range") or "A1:Z100")
    if not ss_id:
        return {"tool": "sheets.read_sheet", "status": "error",
                "message": "sheets.read_sheet requires a 'spreadsheet_id'.", "data": {}}
    svc = _service(user_id, "sheets", "v4")
    resp = svc.spreadsheets().values().get(spreadsheetId=ss_id, range=rng).execute()
    rows = resp.get("values", [])
    summary = "\n".join(" | ".join(str(c) for c in r) for r in rows[:30])
    url = f"https://docs.google.com/spreadsheets/d/{ss_id}"
    return {"tool": "sheets.read_sheet", "status": "success",
            "title": "Spreadsheet", "message": f"Read {len(rows)} row(s).",
            "summary": summary, "url": url,
            "data": {"spreadsheet_id": ss_id, "rows": rows, "url": url}}


def sheets_edit_cell(args: dict, user_id: str) -> dict:
    ss_id = str(args.get("spreadsheet_id") or "").strip()
    cell = str(args.get("cell") or args.get("range") or "").strip()
    value = args.get("value")
    if not ss_id or not cell:
        return {"tool": "sheets.edit_cell", "status": "error",
                "message": "sheets.edit_cell requires 'spreadsheet_id' and 'cell'.", "data": {}}
    svc = _service(user_id, "sheets", "v4")
    svc.spreadsheets().values().update(
        spreadsheetId=ss_id, range=cell, valueInputOption="USER_ENTERED",
        body={"values": [[value]]},
    ).execute()
    url = f"https://docs.google.com/spreadsheets/d/{ss_id}"
    return {"tool": "sheets.edit_cell", "status": "success", "title": "Cell updated",
            "message": f"Set {cell} = {value}.", "speak": "Updated that cell.",
            "url": url, "data": {"spreadsheet_id": ss_id, "cell": cell, "url": url}}


# --------------------------------------------------------------------------- #
# Gmail
# --------------------------------------------------------------------------- #
def _gmail_raw(to: str, subject: str, body: str) -> str:
    msg = MIMEText(body)
    msg["to"] = to
    msg["subject"] = subject
    return base64.urlsafe_b64encode(msg.as_bytes()).decode()


def gmail_draft_email(args: dict, user_id: str) -> dict:
    to = str(args.get("to") or "").strip()
    subject = str(args.get("subject") or "").strip()
    body = str(args.get("body") or "")
    svc = _service(user_id, "gmail", "v1")
    draft = svc.users().drafts().create(
        userId="me", body={"message": {"raw": _gmail_raw(to, subject, body)}}).execute()
    url = "https://mail.google.com/mail/u/0/#drafts"
    return {"tool": "gmail.draft_email", "status": "success", "title": "Draft saved",
            "message": f"Saved a draft to {to}.", "speak": "I saved that draft.",
            "url": url, "data": {"draft_id": draft.get("id"), "to": to, "url": url}}


def gmail_update_draft(args: dict, user_id: str) -> dict:
    """Update an EXISTING draft (fill in a recipient, change subject/body).
    Fields not passed are kept from the current draft."""
    draft_id = str(args.get("draft_id") or "").strip()
    if not draft_id:
        return {"tool": "gmail.update_draft", "status": "error",
                "message": "draft_id is required — take it from RECENT ACTIVITY "
                           "or draft a new email instead.", "data": {}}
    svc = _service(user_id, "gmail", "v1")
    current = svc.users().drafts().get(userId="me", id=draft_id, format="full").execute()
    headers = {h["name"].lower(): h["value"]
               for h in current.get("message", {}).get("payload", {}).get("headers", [])}
    import base64 as _b64
    body_data = ""
    payload = current.get("message", {}).get("payload", {})
    part = payload if payload.get("body", {}).get("data") else next(
        (p for p in payload.get("parts", []) or [] if p.get("body", {}).get("data")), {})
    if part.get("body", {}).get("data"):
        body_data = _b64.urlsafe_b64decode(part["body"]["data"]).decode(errors="replace")

    to = str(args.get("to") or headers.get("to") or "").strip()
    subject = str(args.get("subject") or headers.get("subject") or "").strip()
    body = str(args.get("body") if args.get("body") is not None else body_data)
    updated = svc.users().drafts().update(
        userId="me", id=draft_id,
        body={"message": {"raw": _gmail_raw(to, subject, body)}}).execute()
    url = "https://mail.google.com/mail/u/0/#drafts"
    return {"tool": "gmail.update_draft", "status": "success", "title": "Draft updated",
            "message": f"Updated the draft (to: {to or 'still no recipient'}).",
            "speak": "I updated that draft.",
            "url": url, "data": {"draft_id": updated.get("id", draft_id),
                                 "to": to, "subject": subject, "url": url}}


def gmail_send_draft(args: dict, user_id: str) -> dict:
    """Send an EXISTING draft by id. IRREVERSIBLE. Refuses drafts without a
    real recipient — never send to a placeholder."""
    draft_id = str(args.get("draft_id") or "").strip()
    if not draft_id:
        return {"tool": "gmail.send_draft", "status": "error",
                "message": "draft_id is required — take it from RECENT ACTIVITY.",
                "data": {}}
    svc = _service(user_id, "gmail", "v1")
    current = svc.users().drafts().get(userId="me", id=draft_id, format="metadata").execute()
    headers = {h["name"].lower(): h["value"]
               for h in current.get("message", {}).get("payload", {}).get("headers", [])}
    to = str(headers.get("to") or "").strip()
    if "@" not in to:
        return {"tool": "gmail.send_draft", "status": "error",
                "message": "That draft has no real recipient yet. Add one with "
                           "gmail.update_draft (resolve the address via "
                           "people.search_contacts or ask the user) before sending.",
                "data": {"draft_id": draft_id}}
    sent = svc.users().drafts().send(userId="me", body={"id": draft_id}).execute()
    url = "https://mail.google.com/mail/u/0/#sent"
    return {"tool": "gmail.send_draft", "status": "success", "title": "Email sent",
            "message": f"Sent the draft to {to}.", "speak": f"Sent that to {to}.",
            "url": url, "data": {"message_id": sent.get("id"), "to": to, "url": url}}


def gmail_send_email(args: dict, user_id: str) -> dict:
    to = str(args.get("to") or "").strip()
    subject = str(args.get("subject") or "").strip()
    body = str(args.get("body") or "")
    svc = _service(user_id, "gmail", "v1")
    sent = svc.users().messages().send(
        userId="me", body={"raw": _gmail_raw(to, subject, body)}).execute()
    url = "https://mail.google.com/mail/u/0/#sent"
    return {"tool": "gmail.send_email", "status": "success", "title": "Email sent",
            "message": f"Sent email to {to}.", "speak": f"Sent that email to {to}.",
            "url": url, "data": {"message_id": sent.get("id"), "to": to, "url": url}}


def gmail_read_inbox(args: dict, user_id: str) -> dict:
    count = int(args.get("count") or 5)
    svc = _service(user_id, "gmail", "v1")
    listing = svc.users().messages().list(
        userId="me", maxResults=count, labelIds=["INBOX"]).execute()
    items = []
    for m in listing.get("messages", [])[:count]:
        full = svc.users().messages().get(
            userId="me", id=m["id"], format="metadata",
            metadataHeaders=["From", "Subject"]).execute()
        headers = {h["name"]: h["value"] for h in full.get("payload", {}).get("headers", [])}
        items.append({"from": headers.get("From", ""), "subject": headers.get("Subject", ""),
                      "snippet": full.get("snippet", "")})
    summary = "\n".join(f"• {i['subject']} — {i['from']}" for i in items)
    url = "https://mail.google.com/mail/u/0/#inbox"
    return {"tool": "gmail.read_inbox", "status": "success", "title": "Inbox",
            "message": f"Read {len(items)} email(s).", "summary": summary,
            "url": url, "data": {"emails": items, "url": url}}


# --------------------------------------------------------------------------- #
# Calendar
# --------------------------------------------------------------------------- #
def calendar_create_event(args: dict, user_id: str) -> dict:
    title = str(args.get("title") or "Event").strip()
    start = str(args.get("start_datetime") or "").strip()
    duration = int(args.get("duration_minutes") or 60)
    if not start:
        return {"tool": "calendar.create_event", "status": "error",
                "message": "calendar.create_event requires 'start_datetime'.", "data": {}}
    from datetime import datetime, timedelta
    start_dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
    end_dt = start_dt + timedelta(minutes=duration)
    svc = _service(user_id, "calendar", "v3")
    event = svc.events().insert(calendarId="primary", body={
        "summary": title,
        "description": args.get("notes", ""),
        "start": {"dateTime": start_dt.isoformat()},
        "end": {"dateTime": end_dt.isoformat()},
    }).execute()
    return {"tool": "calendar.create_event", "status": "success", "title": title,
            "message": f"Created '{title}'.", "url": event.get("htmlLink"),
            "speak": f"Added {title} to your calendar.",
            "data": {"event_id": event.get("id"), "title": title, "url": event.get("htmlLink")}}


def calendar_read_today(args: dict, user_id: str) -> dict:
    from datetime import datetime, timezone, timedelta
    now = datetime.now(timezone.utc)
    end = now + timedelta(days=1)
    svc = _service(user_id, "calendar", "v3")
    resp = svc.events().list(
        calendarId="primary", timeMin=now.isoformat(), timeMax=end.isoformat(),
        singleEvents=True, orderBy="startTime").execute()
    events = resp.get("items", [])
    lines = [f"• {e.get('summary', '(no title)')} — {e.get('start', {}).get('dateTime', '')}"
             for e in events]
    url = "https://calendar.google.com/calendar/u/0/r/day"
    return {"tool": "calendar.read_today", "status": "success", "title": "Today",
            "message": f"{len(events)} event(s) today.", "summary": "\n".join(lines),
            "url": url, "data": {"events": events, "url": url}}


# --------------------------------------------------------------------------- #
# Tasks (replaces Apple Reminders)
# --------------------------------------------------------------------------- #
def tasks_create_task(args: dict, user_id: str) -> dict:
    title = str(args.get("title") or "").strip()
    if not title:
        return {"tool": "tasks.create_task", "status": "error",
                "message": "tasks.create_task requires a 'title'.", "data": {}}
    body = {"title": title}
    if args.get("due_date"):
        from datetime import datetime
        try:
            body["due"] = datetime.fromisoformat(
                str(args["due_date"]).replace("Z", "+00:00")).isoformat()
        except ValueError:
            pass
    if args.get("notes"):
        body["notes"] = str(args["notes"])
    svc = _service(user_id, "tasks", "v1")
    task = svc.tasks().insert(tasklist="@default", body=body).execute()
    url = "https://tasks.google.com/embed/"
    return {"tool": "tasks.create_task", "status": "success", "title": "Task added",
            "message": f"Added task '{title}'.", "speak": f"Added {title} to your tasks.",
            "url": url, "data": {"task_id": task.get("id"), "title": title, "url": url}}


def tasks_complete_task(args: dict, user_id: str) -> dict:
    title = str(args.get("title") or "").strip()
    svc = _service(user_id, "tasks", "v1")
    listing = svc.tasks().list(tasklist="@default", showCompleted=False).execute()
    match = next((t for t in listing.get("items", [])
                  if title.lower() in (t.get("title", "").lower())), None)
    if not match:
        return {"tool": "tasks.complete_task", "status": "error",
                "message": f"No task matching '{title}'.", "data": {}}
    svc.tasks().patch(tasklist="@default", task=match["id"],
                      body={"status": "completed"}).execute()
    url = "https://tasks.google.com/embed/"
    return {"tool": "tasks.complete_task", "status": "success", "title": "Task completed",
            "message": f"Completed '{match.get('title')}'.", "speak": "Marked that done.",
            "url": url, "data": {"task_id": match["id"], "url": url}}


# --------------------------------------------------------------------------- #
# People (contacts)
# --------------------------------------------------------------------------- #
def people_search_contacts(args: dict, user_id: str) -> dict:
    query = str(args.get("query") or "").strip()
    if not query:
        return {"tool": "people.search_contacts", "status": "error",
                "message": "people.search_contacts requires a 'query'.", "data": {}}
    svc = _service(user_id, "people", "v1")
    resp = svc.people().searchContacts(
        query=query, readMask="names,emailAddresses,phoneNumbers").execute()
    matches = []
    for r in resp.get("results", []):
        p = r.get("person", {})
        matches.append({
            "name": (p.get("names") or [{}])[0].get("displayName", ""),
            "email": (p.get("emailAddresses") or [{}])[0].get("value", ""),
            "phone": (p.get("phoneNumbers") or [{}])[0].get("value", ""),
        })
    summary = "\n".join(f"{m['name']} — {m['email']}" for m in matches)
    url = "https://contacts.google.com/"
    return {"tool": "people.search_contacts", "status": "success", "title": "Contacts",
            "message": f"Found {len(matches)} contact(s).", "summary": summary,
            "url": url, "data": {"contacts": matches, "url": url}}


# --------------------------------------------------------------------------- #
# Drive (replaces Finder)
# --------------------------------------------------------------------------- #
def drive_search_files(args: dict, user_id: str) -> dict:
    query = str(args.get("query") or "").strip()
    svc = _service(user_id, "drive", "v3")
    q = f"name contains '{query}' and trashed = false" if query else "trashed = false"
    resp = svc.files().list(q=q, pageSize=10,
                            fields="files(id,name,webViewLink,mimeType)").execute()
    files = resp.get("files", [])
    summary = "\n".join(f"• {f['name']}" for f in files)
    # Link straight to the top match when there is one, else the Drive search.
    url = (files[0].get("webViewLink") if files else None) or (
        f"https://drive.google.com/drive/search?q={query}" if query
        else "https://drive.google.com/drive/my-drive")
    return {"tool": "drive.search_files", "status": "success", "title": "Drive",
            "message": f"Found {len(files)} file(s).", "summary": summary,
            "url": url, "data": {"files": files, "url": url}}


def drive_move_file(args: dict, user_id: str) -> dict:
    file_id = str(args.get("file_id") or "").strip()
    folder_id = str(args.get("folder_id") or "").strip()
    if not file_id or not folder_id:
        return {"tool": "drive.move_file", "status": "error",
                "message": "drive.move_file requires 'file_id' and 'folder_id'.", "data": {}}
    svc = _service(user_id, "drive", "v3")
    prev = svc.files().get(fileId=file_id, fields="parents").execute()
    svc.files().update(fileId=file_id, addParents=folder_id,
                       removeParents=",".join(prev.get("parents", [])),
                       fields="id,parents").execute()
    url = f"https://drive.google.com/drive/folders/{folder_id}"
    return {"tool": "drive.move_file", "status": "success", "title": "File moved",
            "message": "Moved that file.", "speak": "Moved it.",
            "url": url, "data": {"file_id": file_id, "folder_id": folder_id, "url": url}}


# --------------------------------------------------------------------------- #
# Dispatch
# --------------------------------------------------------------------------- #
_GOOGLE_TOOLS = {
    "docs.create_document": docs_create_document,
    "docs.append_text": docs_append_text,
    "sheets.create_spreadsheet": sheets_create_spreadsheet,
    "sheets.add_row": sheets_add_row,
    "sheets.read_sheet": sheets_read_sheet,
    "sheets.edit_cell": sheets_edit_cell,
    "gmail.draft_email": gmail_draft_email,
    "gmail.update_draft": gmail_update_draft,
    "gmail.send_draft": gmail_send_draft,
    "gmail.send_email": gmail_send_email,
    "gmail.read_inbox": gmail_read_inbox,
    "calendar.create_event": calendar_create_event,
    "calendar.read_today": calendar_read_today,
    "tasks.create_task": tasks_create_task,
    "tasks.complete_task": tasks_complete_task,
    "people.search_contacts": people_search_contacts,
    "drive.search_files": drive_search_files,
    "drive.move_file": drive_move_file,
}


def execute_google_tool(tool: str, args: dict, user_id: str) -> dict:
    """Run a Google-API tool synchronously. Never raises — always a contract."""
    fn = _GOOGLE_TOOLS.get(tool)
    if fn is None:
        return {"tool": tool, "status": "error",
                "message": f"Unknown Google tool: {tool}", "data": {}}
    try:
        return fn(args or {}, user_id)
    except GoogleNotConnected as exc:
        return _not_connected_result(tool, exc)
    except Exception as exc:  # noqa: BLE001
        logger.exception("Google tool %s failed", tool)
        return {"tool": tool, "status": "error",
                "message": f"{tool} failed: {exc}", "speak": "That didn't work.",
                "data": {"error": str(exc)}}
