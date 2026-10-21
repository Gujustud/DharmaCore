"""Gmail API client for purchase ingest."""

from __future__ import annotations

import base64
import os
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any, Optional

from adapters.base import EmailMessage, strip_html_to_text

SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]


class GmailClient:
    def __init__(
        self,
        credentials_path: Optional[str] = None,
        token_path: Optional[str] = None,
    ) -> None:
        self.credentials_path = credentials_path or os.getenv(
            "GMAIL_CREDENTIALS_PATH",
            "/etc/dharmacore/gmail_credentials.json",
        )
        self.token_path = token_path or os.getenv(
            "GMAIL_TOKEN_PATH",
            "/etc/dharmacore/gmail_token.json",
        )
        self._service = None

    def connect(self) -> None:
        from google.auth.transport.requests import Request
        from google.oauth2.credentials import Credentials
        from google_auth_oauthlib.flow import InstalledAppFlow
        from googleapiclient.discovery import build

        creds = None
        token_file = Path(self.token_path)
        if token_file.exists():
            creds = Credentials.from_authorized_user_file(str(token_file), SCOPES)
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                if not Path(self.credentials_path).exists():
                    raise FileNotFoundError(
                        f"Gmail OAuth client secrets not found: {self.credentials_path}"
                    )
                flow = InstalledAppFlow.from_client_secrets_file(
                    self.credentials_path, SCOPES
                )
                # Headless CT: do not open a local browser. Print the URL and
                # listen on a fixed port so the laptop can SSH-tunnel to it.
                oauth_port = int(os.getenv("GMAIL_OAUTH_PORT", "8099"))
                print(
                    f"\nOpen the authorization URL in a browser on your laptop.\n"
                    f"If this machine has no GUI, from your PC run:\n"
                    f"  ssh -L {oauth_port}:127.0.0.1:{oauth_port} root@192.168.20.101\n"
                    f"Then open the URL below (redirect uses localhost:{oauth_port}).\n",
                    flush=True,
                )
                creds = flow.run_local_server(
                    port=oauth_port,
                    open_browser=False,
                    bind_addr="127.0.0.1",
                )
            token_file.parent.mkdir(parents=True, exist_ok=True)
            token_file.write_text(creds.to_json())
        self._service = build("gmail", "v1", credentials=creds, cache_discovery=False)

    @property
    def service(self):
        if self._service is None:
            self.connect()
        return self._service

    def list_message_ids(self, query: str, max_results: int = 100) -> list[str]:
        ids: list[str] = []
        req = (
            self.service.users()
            .messages()
            .list(userId="me", q=query, maxResults=min(max_results, 100))
        )
        while req is not None and len(ids) < max_results:
            resp = req.execute()
            for m in resp.get("messages") or []:
                ids.append(m["id"])
                if len(ids) >= max_results:
                    break
            req = (
                self.service.users()
                .messages()
                .list_next(previous_request=req, previous_response=resp)
            )
        return ids

    def get_message(self, message_id: str) -> EmailMessage:
        raw = (
            self.service.users()
            .messages()
            .get(userId="me", id=message_id, format="full")
            .execute()
        )
        headers = {
            h["name"].lower(): h["value"]
            for h in (raw.get("payload") or {}).get("headers") or []
        }
        subject = headers.get("subject", "")
        from_address = headers.get("from", "")
        date_hdr = headers.get("date", "")
        received_at = None
        if date_hdr:
            try:
                received_at = parsedate_to_datetime(date_hdr).isoformat()
            except Exception:
                received_at = None

        body_text, body_html, attachments = _walk_parts(raw.get("payload") or {})
        if not body_text and body_html:
            body_text = strip_html_to_text(body_html)

        return EmailMessage(
            gmail_message_id=message_id,
            gmail_thread_id=raw.get("threadId") or "",
            from_address=from_address,
            subject=subject,
            received_at=received_at,
            body_text=body_text,
            body_html=body_html,
            attachments=attachments,
        )


def _walk_parts(payload: dict[str, Any]) -> tuple[str, str, list[dict[str, Any]]]:
    text_parts: list[str] = []
    html_parts: list[str] = []
    attachments: list[dict[str, Any]] = []

    def handle(part: dict[str, Any]) -> None:
        mime = (part.get("mimeType") or "").lower()
        filename = part.get("filename") or ""
        body = part.get("body") or {}
        data = body.get("data")
        if filename and body.get("attachmentId"):
            # Caller may fetch attachment bytes separately; store id for now
            attachments.append(
                {
                    "filename": filename,
                    "mime_type": mime,
                    "attachment_id": body.get("attachmentId"),
                    "data": b"",
                }
            )
        elif data and filename:
            attachments.append(
                {
                    "filename": filename,
                    "mime_type": mime,
                    "data": base64.urlsafe_b64decode(data.encode("utf-8")),
                }
            )
        elif data and mime == "text/plain":
            text_parts.append(
                base64.urlsafe_b64decode(data.encode("utf-8")).decode("utf-8", errors="replace")
            )
        elif data and mime == "text/html":
            html_parts.append(
                base64.urlsafe_b64decode(data.encode("utf-8")).decode("utf-8", errors="replace")
            )
        for child in part.get("parts") or []:
            handle(child)

    handle(payload)
    return "\n".join(text_parts), "\n".join(html_parts), attachments


def fetch_attachment_bytes(gmail: GmailClient, message_id: str, attachment_id: str) -> bytes:
    att = (
        gmail.service.users()
        .messages()
        .attachments()
        .get(userId="me", messageId=message_id, id=attachment_id)
        .execute()
    )
    data = att.get("data") or ""
    return base64.urlsafe_b64decode(data.encode("utf-8"))
