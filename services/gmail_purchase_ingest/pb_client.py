"""PocketBase admin/API client for email purchase ingest."""

from __future__ import annotations

import json
import os
import re
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

    def delete(self, collection: str, record_id: str) -> None:
        r = self._client.delete(
            f"{self.base_url}/api/collections/{collection}/records/{record_id}",
            headers=self._headers(),
        )
        r.raise_for_status()

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

    def find_pending_draft_for_merge(
        self,
        vendor_key: str,
        order_reference: str,
        purchase_date: Optional[str] = None,
        customer_po: Optional[str] = None,
        tracking: Optional[str] = None,
    ) -> Optional[dict[str, Any]]:
        """Exact ref match, or merge via customer PO / tracking / MC-DAY same-day.

        McMaster cert/receipt emails may key as MC-DAY-… or (historically) an
        invoice number. Customer PO (1013ASOLANKI) and Purolator PIN are stable
        across confirmation + cert + receipt.
        """
        exact = self.find_pending_draft(vendor_key, order_reference)
        if exact:
            return exact

        vk = vendor_key.replace('"', "")
        ref = (order_reference or "").strip()
        candidates = self.list(
            "purchase_drafts",
            filter=f'vendor_key = "{vk}" && status = "pending"',
            sort="-purchase_date",
            per_page=50,
        )
        if not candidates:
            return None

        po = (customer_po or "").strip().upper()
        if po:
            po_hits = [
                d
                for d in candidates
                if po in str(d.get("notes") or "").upper()
                or po == str(d.get("order_reference") or "").upper()
            ]
            if po_hits:
                return prefer_merge_draft(po_hits, incoming_ref=ref)

        pin = _tracking_pin(tracking)
        if pin:
            track_hits = [
                d for d in candidates if pin in str(d.get("tracking") or "").upper()
            ]
            if track_hits:
                return prefer_merge_draft(track_hits, incoming_ref=ref)

        day = _merge_day_key(ref, purchase_date)
        if not day:
            return None
        return pick_same_day_merge_draft(candidates, day=day, incoming_ref=ref)

    def consolidate_pending_by_customer_po(self, vendor_key: str = "mcmaster") -> int:
        """Merge pending drafts that share a customer PO / tracking PIN. Returns merges."""
        vk = vendor_key.replace('"', "")
        drafts = self.list(
            "purchase_drafts",
            filter=f'vendor_key = "{vk}" && status = "pending"',
            per_page=100,
        )
        if len(drafts) < 2:
            return 0

        groups: dict[str, list[dict[str, Any]]] = {}
        for d in drafts:
            keys: list[str] = []
            notes = str(d.get("notes") or "")
            for m in re.finditer(r"\b([0-9]{3,4}A[A-Z0-9]{4,})\b", notes, re.I):
                keys.append(f"po:{m.group(1).upper()}")
            pin = _tracking_pin(str(d.get("tracking") or ""))
            if pin:
                keys.append(f"pin:{pin}")
            if not keys:
                continue
            # Use first stable key; attach draft to that group
            k = keys[0]
            groups.setdefault(k, []).append(d)

        merged = 0
        for _k, group in groups.items():
            # Deduplicate by id
            by_id = {d["id"]: d for d in group}
            group = list(by_id.values())
            if len(group) < 2:
                continue
            keeper = prefer_merge_draft(group, incoming_ref="")
            if not keeper:
                continue
            for d in group:
                if d["id"] == keeper["id"]:
                    continue
                self._absorb_draft(keeper, d)
                merged += 1
        return merged

    def _absorb_draft(self, keeper: dict[str, Any], orphan: dict[str, Any]) -> None:
        """Fold orphan pending draft into keeper, then delete orphan."""
        kid, oid = keeper["id"], orphan["id"]
        body: dict[str, Any] = {}
        k_ref = str(keeper.get("order_reference") or "")
        o_ref = str(orphan.get("order_reference") or "")
        # Prefer non-invoice-looking shorter McMaster order # when one looks better
        if o_ref.isdigit() and (not k_ref.isdigit() or _ref_quality(o_ref) > _ref_quality(k_ref)):
            body["order_reference"] = o_ref
        if orphan.get("total") and not keeper.get("total"):
            body["total"] = orphan["total"]
        if orphan.get("invoice") and not keeper.get("invoice"):
            body["invoice"] = orphan["invoice"]
        from note_utils import merge_note_lines, merge_tracking_field

        o_track = str(orphan.get("tracking") or "")
        k_track = str(keeper.get("tracking") or "")
        merged_track = merge_tracking_field(k_track, o_track)
        if merged_track and merged_track != k_track:
            body["tracking"] = merged_track
        o_notes = str(orphan.get("notes") or "")
        k_notes = str(keeper.get("notes") or "")
        merged_notes = merge_note_lines(k_notes, o_notes)
        if merged_notes != k_notes:
            body["notes"] = merged_notes
        if body:
            updated = self.update("purchase_drafts", kid, body)
            keeper.update(updated)

        keeper_lines = self.list(
            "purchase_draft_lines", filter=f'draft = "{kid}"', per_page=200
        )
        keeper_parts = {
            str(l.get("part_number") or "").upper(): l for l in keeper_lines if l.get("part_number")
        }
        for line in self.list("purchase_draft_lines", filter=f'draft = "{oid}"', per_page=200):
            pn = str(line.get("part_number") or "").upper()
            if pn and pn in keeper_parts:
                # Duplicate part — keep the richer description on keeper, drop orphan line
                keep = keeper_parts[pn]
                orphan_desc = str(line.get("description") or "")
                keep_desc = str(keep.get("description") or "")
                if len(orphan_desc) > len(keep_desc) + 5:
                    try:
                        self.update(
                            "purchase_draft_lines",
                            keep["id"],
                            {"description": orphan_desc[:500]},
                        )
                    except Exception:
                        pass
                self.delete("purchase_draft_lines", line["id"])
                continue
            try:
                self.update("purchase_draft_lines", line["id"], {"draft": kid})
                if pn:
                    keeper_parts[pn] = line
            except Exception:
                self.delete("purchase_draft_lines", line["id"])
        for m in self.list("email_ingest_messages", filter=f'purchase_draft = "{oid}"', per_page=200):
            try:
                self.update("email_ingest_messages", m["id"], {"purchase_draft": kid})
            except Exception:
                pass
        self.delete("purchase_drafts", oid)

    def sanitize_pending_draft_display(self, vendor_key: str = "mcmaster") -> int:
        """Clean duplicate notes/tracking on pending drafts. Returns count updated."""
        from note_utils import merge_note_lines, merge_tracking_field, prefer_tracking

        vk = vendor_key.replace('"', "")
        drafts = self.list(
            "purchase_drafts",
            filter=f'vendor_key = "{vk}" && status = "pending"',
            per_page=100,
        )
        n = 0
        for d in drafts:
            notes = merge_note_lines(str(d.get("notes") or ""))
            track = str(d.get("tracking") or "").strip()
            # Collapse "PIN URL" same-shipment pairs
            parts = track.split()
            if len(parts) >= 2:
                merged = parts[0]
                for p in parts[1:]:
                    merged = prefer_tracking(merged, p)
                track = merged
            track = merge_tracking_field(track, "")
            body: dict[str, Any] = {}
            if notes != (d.get("notes") or ""):
                body["notes"] = notes
            if track != (d.get("tracking") or ""):
                body["tracking"] = track
            # Drop duplicate line items by part number (keep richest description)
            lines = self.list(
                "purchase_draft_lines",
                filter=f'draft = "{d["id"]}"',
                per_page=200,
            )
            seen: dict[str, dict[str, Any]] = {}
            for line in lines:
                pn = str(line.get("part_number") or "").upper()
                if not pn:
                    continue
                if pn not in seen:
                    seen[pn] = line
                    continue
                keep = seen[pn]
                if len(str(line.get("description") or "")) > len(
                    str(keep.get("description") or "")
                ):
                    self.delete("purchase_draft_lines", keep["id"])
                    seen[pn] = line
                else:
                    self.delete("purchase_draft_lines", line["id"])
                n += 1
            if body:
                self.update("purchase_drafts", d["id"], body)
                n += 1
        return n

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


def _merge_day_key(order_reference: str, purchase_date: Optional[str] = None) -> Optional[str]:
    """YYYY-MM-DD used to correlate MC-DAY fallbacks with real order drafts."""
    ref = (order_reference or "").strip()
    if ref.startswith("MC-DAY-") and len(ref) >= 17:
        day = ref[7:17]
        if len(day) == 10 and day[4] == "-" and day[7] == "-":
            return day
    pd = (purchase_date or "").strip()[:10]
    if len(pd) == 10 and pd[4] == "-" and pd[7] == "-":
        return pd
    return None


def _tracking_pin(tracking: Optional[str]) -> str:
    raw = (tracking or "").strip().upper()
    if not raw:
        return ""
    m = re.search(r"\b([A-Z]{2,4}\d{8,14})\b", raw)
    if m:
        return m.group(1)
    m = re.search(r"pin=([A-Z0-9]+)", raw, re.I)
    return (m.group(1).upper() if m else "")


def _ref_quality(ref: str) -> int:
    """Higher is better. McMaster order #s are typically 7 digits; invoices often 8."""
    r = (ref or "").strip()
    if not r or r.startswith("MC-DAY-"):
        return 0
    if r.isdigit() and 6 <= len(r) <= 7:
        return 3
    if r.isdigit() and len(r) >= 8:
        return 1  # likely invoice / account
    if r.isdigit():
        return 2
    return 1


def prefer_merge_draft(
    candidates: list[dict[str, Any]], *, incoming_ref: str
) -> Optional[dict[str, Any]]:
    if not candidates:
        return None
    scored: list[tuple[int, dict[str, Any]]] = []
    for d in candidates:
        oref = str(d.get("order_reference") or "")
        score = _ref_quality(oref) * 10
        try:
            total = float(d.get("total") or 0)
        except (TypeError, ValueError):
            total = 0.0
        if total > 0:
            score += 5
        if d.get("tracking"):
            score += 2
        if incoming_ref and oref == incoming_ref:
            score += 3
        scored.append((score, d))
    scored.sort(key=lambda x: x[0], reverse=True)
    return scored[0][1]


def pick_same_day_merge_draft(
    candidates: list[dict[str, Any]],
    *,
    day: str,
    incoming_ref: str,
) -> Optional[dict[str, Any]]:
    """Choose a pending draft to merge onto for the given order-day key."""
    same_day: list[dict[str, Any]] = []
    for d in candidates:
        pd = str(d.get("purchase_date") or "")[:10]
        oref = str(d.get("order_reference") or "")
        if (
            pd == day
            or oref == incoming_ref
            or oref == f"MC-DAY-{day}"
            or oref.startswith(f"MC-DAY-{day}")
        ):
            same_day.append(d)
    if not same_day:
        return None
    return prefer_merge_draft(same_day, incoming_ref=incoming_ref)
