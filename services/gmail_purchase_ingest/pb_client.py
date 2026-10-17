"""PocketBase admin/API client for email purchase ingest."""

from __future__ import annotations

import json
import os
from typing import Any, Optional

import httpx


class PocketBaseClient:
    def __init__(
        self,
        base_url: Optional[str] = None,
        email: Optional[str] = None,
        password: Optional[str] = None,
        token: Optional[str] = None,
    ) -> None:
        self.base_url = (base_url or os.getenv("PB_URL", "http://127.0.0.1:8091")).rstrip("/")
        self.email = email or os.getenv("PB_ADMIN_EMAIL", "")
        self.password = password or os.getenv("PB_ADMIN_PASSWORD", "")
        self.token = token or os.getenv("PB_TOKEN", "")
        self._client = httpx.Client(timeout=60.0)

    def close(self) -> None:
        self._client.close()

    def ensure_auth(self) -> None:
        if self.token:
            return
        if not self.email or not self.password:
            raise RuntimeError("PB_TOKEN or PB_ADMIN_EMAIL/PB_ADMIN_PASSWORD required")
        # Try superuser auth first (PB 0.23+), then collection auth.
        for path in (
            "/api/collections/_superusers/auth-with-password",
            "/api/admins/auth-with-password",
            "/api/collections/users/auth-with-password",
        ):
            try:
                r = self._client.post(
                    f"{self.base_url}{path}",
                    json={"identity": self.email, "password": self.password},
                )
                if r.status_code < 300:
                    data = r.json()
                    self.token = data.get("token") or ""
                    if self.token:
                        return
            except Exception:
                continue
        raise RuntimeError("PocketBase authentication failed")

    def _headers(self) -> dict[str, str]:
        self.ensure_auth()
        return {"Authorization": self.token}

    def list(
        self,
        collection: str,
        *,
        filter: str = "",
        sort: str = "",
        expand: str = "",
        per_page: int = 200,
    ) -> list[dict[str, Any]]:
        params: dict[str, Any] = {"perPage": per_page, "page": 1}
        if filter:
            params["filter"] = filter
        if sort:
            params["sort"] = sort
        if expand:
            params["expand"] = expand
        out: list[dict[str, Any]] = []
        while True:
            r = self._client.get(
                f"{self.base_url}/api/collections/{collection}/records",
                headers=self._headers(),
                params=params,
            )
            r.raise_for_status()
            data = r.json()
            items = data.get("items") or []
            out.extend(items)
            total_pages = int(data.get("totalPages") or 1)
            if params["page"] >= total_pages:
                break
            params["page"] += 1
        return out

    def get_first(self, collection: str, filter: str = "") -> Optional[dict[str, Any]]:
        items = self.list(collection, filter=filter, per_page=1)
        return items[0] if items else None

    def create(self, collection: str, body: dict[str, Any]) -> dict[str, Any]:
        r = self._client.post(
            f"{self.base_url}/api/collections/{collection}/records",
            headers=self._headers(),
            json=body,
        )
        r.raise_for_status()
        return r.json()

    def update(self, collection: str, record_id: str, body: dict[str, Any]) -> dict[str, Any]:
        r = self._client.patch(
            f"{self.base_url}/api/collections/{collection}/records/{record_id}",
            headers=self._headers(),
            json=body,
        )
        r.raise_for_status()
        return r.json()

    def upload_files(
        self,
        collection: str,
        record_id: str,
        field: str,
        files: list[tuple[str, bytes, str]],
    ) -> dict[str, Any]:
        """files: list of (filename, data, content_type)."""
        multipart = []
        for filename, data, content_type in files:
            multipart.append((field, (filename, data, content_type)))
        r = self._client.patch(
            f"{self.base_url}/api/collections/{collection}/records/{record_id}",
            headers=self._headers(),
            files=multipart,
        )
        r.raise_for_status()
        return r.json()

    # --- settings helpers ---

    def get_settings(self) -> dict[str, Any]:
        items = self.list("settings", per_page=1)
        if not items:
            raise RuntimeError("No settings record found")
        return items[0]

    def update_settings(self, body: dict[str, Any]) -> dict[str, Any]:
        settings = self.get_settings()
        return self.update("settings", settings["id"], body)

    def get_enabled_vendors(self) -> list[dict[str, Any]]:
        return self.list(
            "email_ingest_vendors",
            filter="enabled = true",
            expand="supplier",
        )

    def find_message(self, gmail_message_id: str) -> Optional[dict[str, Any]]:
        safe = gmail_message_id.replace('"', "")
        return self.get_first(
            "email_ingest_messages",
            filter=f'gmail_message_id = "{safe}"',
        )

    def find_pending_draft(self, vendor_key: str, order_reference: str) -> Optional[dict[str, Any]]:
        vk = vendor_key.replace('"', "")
        ref = order_reference.replace('"', "")
        return self.get_first(
            "purchase_drafts",
            filter=f'vendor_key = "{vk}" && order_reference = "{ref}" && status = "pending"',
        )

    def list_materials(self) -> list[dict[str, Any]]:
        return self.list("materials", sort="grade,form,size_label")

    def create_material_proposal(self, proposed: dict[str, str], source: str) -> dict[str, Any]:
        body = {
            "grade": proposed.get("grade") or "Unknown",
            "form": proposed.get("form") or "other",
            "size_label": proposed.get("size_label") or "unknown",
            "unit": proposed.get("unit") or "ea",
            "source_description": source[:500] if source else "",
            "status": "pending",
        }
        return self.create("material_proposals", body)

    def dumps_json(self, obj: Any) -> str:
        return json.dumps(obj, ensure_ascii=False)
