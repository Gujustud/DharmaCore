"""Poll Gmail and upsert purchase drafts into PocketBase."""

from __future__ import annotations

import json
import logging
import re
import time
from datetime import datetime, timezone
from typing import Any, Optional

from adapters import ALL_ADAPTERS
from adapters.base import EmailMessage, ParsedEmail, ParsedLine
from gmail_client import GmailClient, fetch_attachment_bytes
from matchers.materials import match_material_line
from note_utils import merge_note_lines, merge_tracking_field
from pb_client import PocketBaseClient, _ref_quality

log = logging.getLogger("gmail_purchase_ingest")


def build_domain_query(vendors: list[dict[str, Any]], *, newer_than_days: Optional[int]) -> str:
    domains: list[str] = []
    for v in vendors:
        raw = (v.get("from_domains") or "").replace(";", ",")
        for d in raw.split(","):
            d = d.strip()
            if d:
                domains.append(d)
    if not domains:
        return ""
    if len(domains) == 1:
        from_q = f"from:{domains[0]}"
    else:
        inner = " OR ".join(domains)
        from_q = f"from:({inner})"
    if newer_than_days:
        return f"{from_q} newer_than:{int(newer_than_days)}d"
    return from_q


def resolve_adapter(vendor: dict[str, Any]):
    key = (vendor.get("vendor_key") or "").strip()
    return ALL_ADAPTERS.get(key)


def run_once(
    pb: PocketBaseClient,
    gmail: Optional[GmailClient] = None,
    *,
    force: bool = False,
) -> dict[str, Any]:
    settings = pb.get_settings()
    enabled = bool(settings.get("email_ingest_enabled"))
    if not enabled and not force:
        return {"skipped": True, "reason": "email_ingest_enabled is false"}

    poll_minutes = int(settings.get("email_ingest_poll_minutes") or 30)
    if poll_minutes < 1:
        poll_minutes = 1

    vendors = pb.get_enabled_vendors()
    if not vendors:
        status = {
            "ok": False,
            "error": "No enabled email_ingest_vendors",
            "at": _now_iso(),
        }
        pb.update_settings(
            {
                "email_ingest_last_sync_at": status["at"],
                "email_ingest_last_sync_status": "error",
                "email_ingest_last_error": status["error"],
            }
        )
        return status

    # Always constrain Gmail search — never scan the whole mailbox (quota blow-up).
    lookback = int(settings.get("email_ingest_lookback_days") or 7)
    if lookback < 1:
        lookback = 1
    if lookback > 30:
        lookback = 30
    query = build_domain_query(vendors, newer_than_days=lookback)
    if not query:
        return {"skipped": True, "reason": "no domains"}

    if gmail is None:
        gmail = GmailClient()
        gmail.connect()

    materials = pb.list_materials()
    processed = 0
    skipped_known = 0
    errors: list[str] = []

    try:
        # Cap each cycle so we don't chew Gmail quota on big inboxes.
        ids = gmail.list_message_ids(query, max_results=40)
        for mid in ids:
            if pb.find_message(mid):
                skipped_known += 1
                continue
            try:
                msg = gmail.get_message(mid)
                # hydrate attachment bytes
                for att in msg.attachments:
                    aid = att.get("attachment_id")
                    if aid and not att.get("data"):
                        att["data"] = fetch_attachment_bytes(gmail, mid, aid)
                _ingest_message(pb, msg, vendors, materials)
                processed += 1
                # Small pause between full message fetches (quota units)
                time.sleep(0.4)
            except Exception as e:
                log.exception("Failed message %s", mid)
                errors.append(f"{mid}: {e}")
                err_s = str(e)
                try:
                    pb.create(
                        "email_ingest_messages",
                        {
                            "gmail_message_id": mid,
                            "parse_status": "parse_error",
                            "parse_error": err_s[:500],
                            "subject": "",
                            "snippet": "",
                        },
                    )
                except Exception:
                    pass
                # Stop this cycle on rate limit; try again next poll
                if "rateLimitExceeded" in err_s or "Quota exceeded" in err_s:
                    break

        # Collapse pending McMaster drafts that share customer PO / tracking
        try:
            consolidated = pb.consolidate_pending_by_customer_po("mcmaster")
            if consolidated:
                log.info("Consolidated %s pending McMaster draft(s)", consolidated)
            cleaned = pb.sanitize_pending_draft_display("mcmaster")
            if cleaned:
                log.info("Sanitized %s pending draft field(s)/dup lines", cleaned)
        except Exception:
            log.exception("Draft consolidate/sanitize failed")

        pb.update_settings(
            {
                "email_ingest_last_sync_at": _now_iso(),
                "email_ingest_last_sync_status": "ok" if not errors else "partial",
                "email_ingest_last_error": "; ".join(errors)[:1000] if errors else "",
                "email_ingest_backfill_done": True,
            }
        )
    except Exception as e:
        log.exception("Poll failed")
        pb.update_settings(
            {
                "email_ingest_last_sync_at": _now_iso(),
                "email_ingest_last_sync_status": "error",
                "email_ingest_last_error": str(e)[:1000],
            }
        )
        raise

    return {
        "ok": True,
        "processed": processed,
        "skipped_known": skipped_known,
        "errors": errors,
        "poll_minutes": poll_minutes,
        "lookback_days": lookback,
        "query": query,
    }


def _ingest_message(
    pb: PocketBaseClient,
    msg: EmailMessage,
    vendors: list[dict[str, Any]],
    materials: list[dict[str, Any]],
) -> None:
    vendor = _match_vendor(msg, vendors)
    if not vendor:
        pb.create(
            "email_ingest_messages",
            {
                "gmail_message_id": msg.gmail_message_id,
                "gmail_thread_id": msg.gmail_thread_id,
                "from_address": msg.from_address[:200],
                "subject": msg.subject[:500],
                "received_at": msg.received_at,
                "parse_status": "ignored",
                "snippet": (msg.body_text or "")[:300],
                "email_type": "other",
            },
        )
        return

    adapter = resolve_adapter(vendor)
    if adapter is None:
        pb.create(
            "email_ingest_messages",
            {
                "gmail_message_id": msg.gmail_message_id,
                "gmail_thread_id": msg.gmail_thread_id,
                "vendor_key": vendor.get("vendor_key"),
                "email_ingest_vendor": vendor.get("id"),
                "from_address": msg.from_address[:200],
                "subject": msg.subject[:500],
                "received_at": msg.received_at,
                "parse_status": "parse_error",
                "parse_error": f"No adapter for vendor_key={vendor.get('vendor_key')}",
                "snippet": (msg.body_text or "")[:300],
            },
        )
        return

    domains = [d.strip() for d in (vendor.get("from_domains") or "").split(",") if d.strip()]
    parsed = adapter.parse(msg)
    email_type = parsed.email_type or adapter.classify(msg)
    corr = adapter.correlate_key(parsed, msg)

    draft_id = None
    if corr:
        draft_id = _upsert_draft(pb, vendor, parsed, corr, email_type, materials, msg)

    pb.create(
        "email_ingest_messages",
        {
            "gmail_message_id": msg.gmail_message_id,
            "gmail_thread_id": msg.gmail_thread_id,
            "vendor_key": vendor.get("vendor_key"),
            "email_ingest_vendor": vendor.get("id"),
            "from_address": msg.from_address[:200],
            "subject": msg.subject[:500],
            "received_at": msg.received_at,
            "email_type": email_type,
            "parse_status": "parsed" if parsed.ok else "parse_error",
            "parse_error": (parsed.error or "")[:500],
            "snippet": (msg.body_text or "")[:300],
            "purchase_draft": draft_id,
        },
    )


def _match_vendor(msg: EmailMessage, vendors: list[dict[str, Any]]) -> Optional[dict[str, Any]]:
    for v in vendors:
        adapter = resolve_adapter(v)
        domains = [d.strip() for d in (v.get("from_domains") or "").split(",") if d.strip()]
        if adapter and adapter.detect(msg, domains):
            return v
        # Domain-only fallback when adapter missing
        from adapters.base import from_domain_matches

        if from_domain_matches(msg.from_address, domains):
            return v
    return None


def _upsert_draft(
    pb: PocketBaseClient,
    vendor: dict[str, Any],
    parsed: ParsedEmail,
    order_ref: str,
    email_type: str,
    materials: list[dict[str, Any]],
    msg: EmailMessage,
) -> Optional[str]:
    customer_po = (getattr(parsed, "customer_po", None) or "").strip()
    if not customer_po and parsed.notes:
        m = re.search(r"\b([0-9]{3,4}A[A-Z0-9]{4,})\b", parsed.notes, re.I)
        if m:
            customer_po = m.group(1).upper()

    existing = pb.find_pending_draft_for_merge(
        vendor.get("vendor_key") or "",
        order_ref,
        purchase_date=parsed.purchase_date,
        customer_po=customer_po or None,
        tracking=parsed.tracking or None,
    )
    supplier_id = _supplier_id(vendor)
    currency = (
        parsed.currency
        or vendor.get("default_currency")
        or "USD"
    )

    # Don't overwrite a real McMaster # with an MC-DAY-… / invoice-sized fallback
    merged_ref = order_ref
    if existing:
        existing_ref = str(existing.get("order_reference") or "")
        if existing_ref.isdigit() and (
            order_ref.startswith("MC-DAY-") or not order_ref.isdigit()
        ):
            merged_ref = existing_ref
        elif order_ref.startswith("MC-DAY-") and existing_ref:
            merged_ref = existing_ref
        elif (
            order_ref.isdigit()
            and existing_ref.isdigit()
            and _ref_quality(order_ref) > _ref_quality(existing_ref)
        ):
            merged_ref = order_ref
        elif (
            order_ref.isdigit()
            and existing_ref.isdigit()
            and _ref_quality(existing_ref) >= _ref_quality(order_ref)
        ):
            merged_ref = existing_ref
    # If this email carries an invoice # equal to order_ref, keep existing order #
    if (
        existing
        and parsed.invoice
        and order_ref
        and order_ref == parsed.invoice
        and str(existing.get("order_reference") or "")
    ):
        merged_ref = str(existing.get("order_reference"))

    body: dict[str, Any] = {
        "vendor_key": vendor.get("vendor_key"),
        "email_ingest_vendor": vendor.get("id"),
        "order_reference": merged_ref,
        "status": "pending",
        "currency": currency if currency in ("CAD", "USD") else "USD",
    }
    if supplier_id:
        body["supplier"] = supplier_id
    if parsed.purchase_date:
        body["purchase_date"] = parsed.purchase_date
    elif not existing:
        body["purchase_date"] = _now_iso()[:10]
    if parsed.invoice:
        body["invoice"] = parsed.invoice
    if parsed.total is not None:
        body["total"] = parsed.total
    if parsed.notes or parsed.parse_notes:
        note = parsed.notes or parsed.parse_notes
        body["notes"] = merge_note_lines(
            (existing or {}).get("notes") or "",
            note,
        )

    # Confirmation / cert+tracking / receipt all may carry tracking
    if parsed.tracking and email_type in (
        "shipping",
        "certificate",
        "invoice",
        "order_confirmation",
    ):
        body["tracking"] = merge_tracking_field(
            (existing or {}).get("tracking"),
            parsed.tracking,
        )
    elif parsed.tracking and not existing:
        body["tracking"] = parsed.tracking

    if existing:
        draft = pb.update("purchase_drafts", existing["id"], body)
        draft_id = draft["id"]
        if email_type in ("order_confirmation",) and parsed.lines:
            existing_lines = pb.list(
                "purchase_draft_lines",
                filter=f'draft = "{draft_id}"',
                per_page=100,
            )
            if not existing_lines:
                _create_lines(pb, draft_id, parsed.lines, materials)
            else:
                _enrich_lines_from_confirmation(pb, existing_lines, parsed.lines, materials)
    else:
        if not body.get("purchase_date"):
            body["purchase_date"] = _now_iso()[:10]
        draft = pb.create("purchase_drafts", body)
        draft_id = draft["id"]
        if parsed.lines:
            _create_lines(pb, draft_id, parsed.lines, materials)

    # Attach PDFs (mill certs prefer material lines when present)
    _attach_files(pb, draft_id, parsed, msg, email_type=email_type)
    return draft_id


def _enrich_lines_from_confirmation(
    pb: PocketBaseClient,
    existing_lines: list[dict[str, Any]],
    parsed_lines: list[ParsedLine],
    materials: list[dict[str, Any]],
) -> None:
    """Backfill unit_cost / richer description / form size when confirmation arrives late."""
    by_part = {
        str(l.get("part_number") or "").upper(): l
        for l in existing_lines
        if l.get("part_number")
    }
    for pl in parsed_lines:
        pn = (pl.part_number or "").upper()
        if not pn:
            continue
        existing = by_part.get(pn)
        if not existing:
            continue
        patch: dict[str, Any] = {}
        try:
            cur_cost = float(existing.get("unit_cost") or 0)
        except (TypeError, ValueError):
            cur_cost = 0.0
        if pl.unit_cost is not None and cur_cost <= 0:
            patch["unit_cost"] = pl.unit_cost
        cur_desc = str(existing.get("description") or "")
        if pl.description and len(pl.description) > len(cur_desc) + 5:
            patch["description"] = pl.description[:500]
        # Refresh material proposal hints when we now have better form/size
        if pl.form or pl.size_label or pl.grade:
            match = match_material_line(
                materials=materials,
                grade=pl.grade,
                form=pl.form,
                size_label=pl.size_label,
                description=pl.description,
                line_type=pl.line_type or "material",
            )
            if match.status != "n_a":
                patch["match_status"] = match.status
            if match.proposed:
                patch["proposed_material_json"] = json.dumps(match.proposed)
            if match.matched_material_id and not existing.get("matched_material"):
                patch["matched_material"] = match.matched_material_id
        if patch:
            try:
                pb.update("purchase_draft_lines", existing["id"], patch)
            except Exception:
                log.exception("Failed to enrich draft line %s", existing.get("id"))


def _create_lines(
    pb: PocketBaseClient,
    draft_id: str,
    lines: list[ParsedLine],
    materials: list[dict[str, Any]],
) -> None:
    for i, line in enumerate(lines):
        match = match_material_line(
            materials=materials,
            grade=line.grade,
            form=line.form,
            size_label=line.size_label,
            description=line.description,
            line_type=line.line_type,
        )
        proposal_id = None
        proposed = dict(match.proposed) if match.proposed else None
        if proposed and line.part_number:
            proposed["notes"] = f"McMaster {line.part_number.upper()}"
        if match.status == "propose_new" and proposed:
            prop = pb.create_material_proposal(proposed, line.description)
            proposal_id = prop["id"]

        body: dict[str, Any] = {
            "draft": draft_id,
            "line_type": line.line_type if line.line_type in (
                "item", "material", "misc", "tax", "shipping"
            ) else "misc",
            "description": line.description[:500],
            "part_number": line.part_number[:100],
            "quantity": line.quantity,
            "sort_order": i * 10,
            "match_status": match.status if match.status != "n_a" else "n_a",
        }
        if line.unit_cost is not None:
            body["unit_cost"] = line.unit_cost
        if line.heat_lot:
            body["heat_lot"] = line.heat_lot
        if match.matched_material_id:
            body["matched_material"] = match.matched_material_id
        if proposal_id:
            body["material_proposal"] = proposal_id
        if proposed:
            body["proposed_material_json"] = json.dumps(proposed)
        if match.candidate_ids:
            body["candidate_material_ids"] = ",".join(match.candidate_ids)
        pb.create("purchase_draft_lines", body)


def _attach_files(
    pb: PocketBaseClient,
    draft_id: str,
    parsed: ParsedEmail,
    msg: EmailMessage,
    email_type: str = "",
) -> None:
    mill_certs = []
    other_files = []
    for att in msg.attachments:
        data = att.get("data") or b""
        filename = att.get("filename") or "attachment.pdf"
        if not data:
            continue
        role = parsed.attachment_roles.get(filename) or parsed.attachment_roles.get(
            filename.lower(), ""
        )
        mime = att.get("mime_type") or "application/pdf"
        item = (filename, data, mime)
        if role == "mill_cert" or (
            email_type == "certificate" and filename.lower().endswith(".pdf")
        ):
            mill_certs.append(item)
        elif role in ("invoice", "confirmation") or filename.lower().endswith(".pdf"):
            other_files.append(item)

    # Prefer attaching mill certs onto material draft lines
    if mill_certs:
        attached_to_line = False
        try:
            lines = pb.list(
                "purchase_draft_lines",
                filter=f'draft = "{draft_id}" && line_type = "material"',
                sort="sort_order",
                per_page=20,
            )
            if lines:
                # Put cert on first material line (typical single-cert steel order)
                pb.upload_files(
                    "purchase_draft_lines",
                    lines[0]["id"],
                    "mill_certs",
                    mill_certs[:8],
                )
                attached_to_line = True
        except Exception:
            log.exception("Failed to upload mill certs to draft line")
        if not attached_to_line:
            other_files = mill_certs + other_files

    if other_files:
        try:
            pb.upload_files(
                "purchase_drafts", draft_id, "attachments", other_files[:12]
            )
        except Exception:
            log.exception("Failed to upload draft attachments")


def _supplier_id(vendor: dict[str, Any]) -> Optional[str]:
    s = vendor.get("supplier")
    if isinstance(s, str) and s:
        return s
    expand = vendor.get("expand") or {}
    sup = expand.get("supplier")
    if isinstance(sup, dict):
        return sup.get("id")
    return None


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def run_loop(pb: PocketBaseClient, gmail: GmailClient) -> None:
    while True:
        try:
            result = run_once(pb, gmail)
            log.info("Poll result: %s", result)
            minutes = int(result.get("poll_minutes") or 30)
        except Exception:
            log.exception("Poll cycle error")
            try:
                settings = pb.get_settings()
                minutes = int(settings.get("email_ingest_poll_minutes") or 30)
            except Exception:
                minutes = 30
        minutes = max(1, minutes)
        time.sleep(minutes * 60)
