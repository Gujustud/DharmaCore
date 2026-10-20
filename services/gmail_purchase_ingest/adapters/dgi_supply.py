"""DGI Supply Canada — order confirmation + invoice PDF parser."""

from __future__ import annotations

import io
import logging
import re
from typing import Optional

from .base import (
    EmailMessage,
    ParsedEmail,
    ParsedLine,
    from_domain_matches,
    strip_html_to_text,
)

log = logging.getLogger(__name__)

# Live mail is @dgisupply.ca (Cliff / AR); .com kept for older seeds.
DEFAULT_DOMAINS = ["dgisupply.ca", "dgisupply.com"]

_ORDER_NUMBER_RE = re.compile(
    r"Order\s+Number\s*[:#]?\s*([0-9]{5,10})",
    re.I,
)
_INVOICE_NUMBER_RE = re.compile(
    r"Invoice\s+(?:Number|No\.?|#)\s*[:#]?\s*([0-9]{5,12})",
    re.I,
)
_PO_NUMBER_RE = re.compile(
    r"PO\s+Number\s*[:#]?\s*([A-Z0-9][A-Z0-9 _./-]{1,40})",
    re.I,
)
_ORDER_DATE_RE = re.compile(
    r"Order\s+Date\s*[:#]?\s*(\d{1,2}/\d{1,2}/\d{2,4})",
    re.I,
)
_INVOICE_DATE_RE = re.compile(
    r"Invoice\s+Date\s*[:#]?\s*(\d{1,2}/\d{1,2}/\d{2,4})",
    re.I,
)
# Item ID like HVT989816C4 or HVT68320 near unit/extended prices
_ITEM_LINE_RE = re.compile(
    r"(?P<part>HVT[A-Z0-9]{3,20}|[A-Z]{2,5}[0-9]{4,12}[A-Z0-9-]{0,8})"
    r"\s+(?P<desc>.+?)\s+"
    r"(?P<qty>\d+(?:\.\d+)?)\s*(?:EA|ea)?\s+"
    r"(?P<unit>[0-9,]+\.\d{2,4})\s+"
    r"(?P<ext>[0-9,]+\.\d{2})",
    re.I | re.S,
)
# Looser: Item ID on its own then description + prices nearby
_ITEM_ID_RE = re.compile(r"\b(?P<part>HVT[A-Z0-9]{3,20})\b", re.I)
_MONEY_RE = re.compile(r"([0-9,]+\.\d{2,4})")
_SUBTOTAL_RE = re.compile(
    r"SUB[-\s]?TOTAL\s*[:$]?\s*\$?\s*([0-9,]+\.\d{2})",
    re.I,
)
_FREIGHT_RE = re.compile(
    r"(?:Total\s+Freight(?:\s+Out)?|Freight)\s*[:$]?\s*\$?\s*([0-9,]+\.\d{2})",
    re.I,
)
# Allow digits in the middle (e.g. "GST 5% REG# R885…: 16.84")
_TAX_RE = re.compile(
    r"(?:Canada\s+)?(?:GST(?:\s*/\s*HST)?|HST|\bTAX\b).{0,80}?"
    r"([0-9,]+\.\d{2})",
    re.I | re.S,
)
_AMOUNT_DUE_RE = re.compile(
    r"(?:AMOUNT\s+due|grand\s+total)\s*[:$]?\s*\$?\s*([0-9,]+\.\d{2})",
    re.I,
)
_TRACKING_RE = re.compile(
    r"(?:tracking\s*(?:#|number|no\.?)?)\s*[:#]?\s*([A-Z0-9]{10,22})\b",
    re.I,
)


def _normalize(text: str) -> str:
    if not text:
        return ""
    out = text.replace("\u00a0", " ")
    for ch in ("\u2010", "\u2011", "\u2012", "\u2013", "\u2014", "\u2015", "\u2212"):
        out = out.replace(ch, "-")
    return out


def _money(raw: Optional[str]) -> Optional[float]:
    if not raw:
        return None
    try:
        return float(raw.replace(",", ""))
    except ValueError:
        return None


def _norm_date(raw: Optional[str]) -> Optional[str]:
    if not raw:
        return None
    m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{2,4})$", raw.strip())
    if not m:
        return None
    y = int(m.group(3))
    if y < 100:
        y += 2000
    return f"{y:04d}-{int(m.group(1)):02d}-{int(m.group(2)):02d}"


class DgiSupplyAdapter:
    vendor_key = "dgi_supply"
    display_name = "DGI Supply"
    default_domains = list(DEFAULT_DOMAINS)

    def detect(self, message: EmailMessage, domains: list[str]) -> bool:
        use = domains or self.default_domains
        if from_domain_matches(message.from_address, use):
            return True
        blob = f"{message.subject}\n{message.from_address}".lower()
        return "dgi" in blob and "supply" in blob

    def classify(self, message: EmailMessage) -> str:
        subject = (message.subject or "").lower()
        from_a = (message.from_address or "").lower()
        names = " ".join(a.get("filename", "") for a in message.attachments).lower()

        if "ar_canada" in from_a or "invoice" in subject or "invoice" in names:
            return "invoice"
        if any(k in subject for k in ("confirm", "order acknowledgement", "acknowledgment")):
            return "order_confirmation"
        if "order" in subject and "invoice" not in subject:
            return "order_confirmation"
        if any(k in names for k in ("confirm", "acknowledg")):
            return "order_confirmation"
        # Cliff's outbound order PDFs are usually confirmations
        if "cho@" in from_a or from_a.startswith("cho@"):
            return "order_confirmation"
        return "other"

    def correlate_key(self, parsed: ParsedEmail, message: EmailMessage) -> str:
        if parsed.order_reference:
            return parsed.order_reference.strip().upper()
        return (message.gmail_thread_id or message.gmail_message_id or "").strip()

    def parse(self, message: EmailMessage) -> ParsedEmail:
        email_type = self.classify(message)
        body = _normalize(message.body_text or strip_html_to_text(message.body_html))
        pdf_text = _normalize(self._attachment_pdf_text(message))
        blob = f"{body}\n{pdf_text}"

        order_ref = ""
        m = _ORDER_NUMBER_RE.search(blob)
        if m:
            order_ref = m.group(1).strip()

        invoice = ""
        im = _INVOICE_NUMBER_RE.search(blob)
        if im:
            invoice = im.group(1).strip()

        customer_po = ""
        pm = _PO_NUMBER_RE.search(blob)
        if pm:
            customer_po = pm.group(1).strip()
            # Truncate if PDF smashed next label on
            customer_po = re.split(r"\s{2,}|Carrier|Customer", customer_po, 1)[0].strip()

        dm = _INVOICE_DATE_RE.search(blob) or _ORDER_DATE_RE.search(blob)
        purchase_date = _norm_date(dm.group(1) if dm else None)

        am = _AMOUNT_DUE_RE.search(blob)
        total = _money(am.group(1) if am else None)

        lines: list[ParsedLine] = []
        if email_type in ("order_confirmation", "invoice", "other"):
            lines = self._parse_lines(pdf_text or body)

        # Freight / tax from invoice (and confirmation tax when present)
        freight = None
        fm = _FREIGHT_RE.search(blob)
        if fm:
            freight = _money(fm.group(1))
        tax_amt = None
        # Prefer explicit Canada GST line over bare TAX when both exist
        for tm in _TAX_RE.finditer(blob):
            label = tm.group(0).lower()
            amt = _money(tm.group(1))
            if amt is None:
                continue
            if "gst" in label or "tax" in label:
                tax_amt = amt
                if "gst" in label:
                    break

        if freight and freight > 0 and not any(l.line_type == "shipping" for l in lines):
            lines.append(
                ParsedLine(
                    line_type="shipping",
                    description="Shipping",
                    quantity=1.0,
                    unit_cost=freight,
                )
            )
        if tax_amt and tax_amt > 0 and not any(l.line_type == "tax" for l in lines):
            lines.append(
                ParsedLine(
                    line_type="tax",
                    description="GST",  # purchase UI checkbox expects exact "GST"
                    quantity=1.0,
                    unit_cost=tax_amt,
                )
            )

        tracking = ""
        tm = _TRACKING_RE.search(blob)
        if tm:
            tracking = tm.group(1).upper()

        notes_parts: list[str] = []
        if customer_po:
            notes_parts.append(f"Customer PO: {customer_po}")

        attachment_roles: dict[str, str] = {}
        for att in message.attachments:
            fn = att.get("filename") or ""
            fn_l = fn.lower()
            if "invoice" in fn_l or email_type == "invoice":
                attachment_roles[fn] = "invoice"
            elif fn_l.endswith(".pdf"):
                attachment_roles[fn] = (
                    "confirmation" if email_type == "order_confirmation" else "invoice"
                )

        ok = True
        error = ""
        if not order_ref and email_type == "order_confirmation" and not lines:
            ok = False
            error = "Could not extract DGI order number or line items"

        return ParsedEmail(
            email_type=email_type,
            order_reference=order_ref,
            invoice=invoice,
            tracking=tracking,
            currency="CAD",
            purchase_date=purchase_date,
            total=total,
            notes="\n".join(notes_parts),
            customer_po=customer_po,
            lines=lines,
            attachment_roles=attachment_roles,
            parse_notes="\n".join(notes_parts),
            ok=ok,
            error=error,
        )

    def _attachment_pdf_text(self, message: EmailMessage) -> str:
        chunks: list[str] = []
        for att in message.attachments or []:
            data = att.get("data") or b""
            fn = (att.get("filename") or "").lower()
            mime = (att.get("mime_type") or "").lower()
            if not data:
                continue
            is_pdf = fn.endswith(".pdf") or "pdf" in mime or data[:4] == b"%PDF"
            if not is_pdf:
                continue
            text = self._pdf_bytes_to_text(data)
            if text:
                chunks.append(text)
        return "\n".join(chunks)

    @staticmethod
    def _pdf_bytes_to_text(data: bytes) -> str:
        try:
            from pypdf import PdfReader
        except ImportError:
            log.warning("pypdf not installed; cannot read DGI PDF text")
            return ""
        try:
            reader = PdfReader(io.BytesIO(data))
            parts: list[str] = []
            for page in reader.pages[:8]:
                try:
                    parts.append(page.extract_text() or "")
                except Exception:
                    continue
            return "\n".join(parts)
        except Exception as e:
            log.debug("DGI PDF text extract failed: %s", e)
            return ""

    def _parse_lines(self, text: str) -> list[ParsedLine]:
        blob = text or ""
        lines: list[ParsedLine] = []
        seen: set[str] = set()

        for m in _ITEM_LINE_RE.finditer(blob):
            part = m.group("part").upper()
            if part in seen:
                continue
            if not self._looks_like_item_id(part):
                continue
            seen.add(part)
            desc = re.sub(r"\s+", " ", (m.group("desc") or "")).strip()
            desc = self._clean_desc(desc, part)
            qty = float(m.group("qty") or 1)
            unit = _money(m.group("unit"))
            lines.append(
                ParsedLine(
                    line_type="item",
                    description=desc[:500] or part,
                    part_number=part,
                    quantity=qty,
                    unit_cost=unit,
                )
            )
        if lines:
            return lines

        # Fallback: HVT… ids + nearest prices
        for m in _ITEM_ID_RE.finditer(blob):
            part = m.group("part").upper()
            if part in seen:
                continue
            seen.add(part)
            window = blob[m.end() : m.end() + 400]
            moneys = _MONEY_RE.findall(window)
            unit = None
            if len(moneys) >= 2:
                # unit price then extended
                unit = _money(moneys[-2]) or _money(moneys[0])
            elif moneys:
                unit = _money(moneys[0])
            desc = re.sub(r"\s+", " ", window[:180]).strip()
            desc = self._clean_desc(desc, part)
            qty_m = re.search(r"\b(\d+(?:\.\d+)?)\s*(?:EA|ea)\b", window)
            qty = float(qty_m.group(1)) if qty_m else 1.0
            lines.append(
                ParsedLine(
                    line_type="item",
                    description=desc[:500] or part,
                    part_number=part,
                    quantity=qty,
                    unit_cost=unit,
                )
            )
        return lines

    @staticmethod
    def _looks_like_item_id(part: str) -> bool:
        p = (part or "").upper()
        if p.startswith("HVT") and len(p) >= 6:
            return True
        # Generic DGI-style codes: letters + digits
        return bool(re.fullmatch(r"[A-Z]{2,5}[0-9]{4,12}[A-Z0-9-]{0,8}", p))

    @staticmethod
    def _clean_desc(desc: str, part: str) -> str:
        raw = re.sub(r"\s+", " ", (desc or "")).strip()
        # Drop expected-delivery crumbs
        raw = re.sub(
            r"Expected\s+Delivery\s+Date.*$",
            "",
            raw,
            flags=re.I,
        ).strip()
        raw = re.sub(r"\b\d{1,2}/\d{1,2}/\d{2,4}\b", "", raw).strip()
        # Drop leading qty noise
        raw = re.sub(r"^[\d.]+\s+(?:EA\s+)?", "", raw, flags=re.I).strip()
        if part and part.upper() not in raw.upper():
            raw = f"{raw} {part}".strip()
        return raw[:500]


ADAPTER = DgiSupplyAdapter()
