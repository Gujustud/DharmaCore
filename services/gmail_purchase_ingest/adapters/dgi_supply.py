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

# PDF extract often puts "Order" / "Number" / digits on separate lines.
_ORDER_NUMBER_RE = re.compile(
    r"Order\s*[\n\r\t ]*Number\s*[:#]?\s*([0-9]{5,10})"
    r"|Order\s*#\s*([0-9]{5,10})"
    r"|Order\s*No\.?\s*[:#]?\s*([0-9]{5,10})",
    re.I,
)
_INVOICE_NUMBER_RE = re.compile(
    r"Invoice\s*[\n\r\t ]*(?:Number|No\.?|#)\s*[:#]?\s*([0-9]{5,12})",
    re.I,
)
# Stop before Net/Carrier/terms — PO is usually a short token like AMISH.
_PO_NUMBER_RE = re.compile(
    r"PO\s*[\n\r\t ]*Number\s*[:#]?\s*([A-Z0-9][A-Z0-9._/-]{0,24})",
    re.I,
)
_PO_STOP = re.compile(
    r"^(Net|Carrier|Customer|Terms|CHO|SHIPPED|Direct|Order|Invoice)\b",
    re.I,
)
_ORDER_DATE_RE = re.compile(
    r"Order\s*[\n\r\t ]*Date\s*[:#]?\s*(\d{1,2}/\d{1,2}/\d{2,4})",
    re.I,
)
_INVOICE_DATE_RE = re.compile(
    r"Invoice\s*[\n\r\t ]*Date\s*[:#]?\s*(\d{1,2}/\d{1,2}/\d{2,4})",
    re.I,
)
# Harvey / DGI item ids. Trailing glued qty digit handled in normalize.
_HVT_RE = re.compile(r"\b(HVT[0-9]{4,10}[A-Z]?[0-9]{0,4})\b", re.I)
# Unit price often has 4 decimals (112.1800); may be glued: 112.1800EAEA
_UNIT4_RE = re.compile(r"(?<![\d.])(\d{1,5}\.\d{4})(?!\d)")
_EXT2_RE = re.compile(r"(?<![\d.])(\d{1,7}\.\d{2})(?!\d)")
_FOOTER_RE = re.compile(
    r"\b(?:SUB-?TOTAL|TOTAL\s+FREIGHT|AMOUNT\s+DUE|GRAND\s+TOTAL|"
    r"Canada\s+GST|\bTAX\b|Expected\s+Delivery|Total\s+Lines)\b",
    re.I,
)
_DESC_START_RE = re.compile(
    # Size crumbs (.250 BALL, 3/16 D) — not calendar dates like 10/15/2026
    r"(\.\d{2,4}\s+[A-Z]|\d{1,2}/(?:[248]|16|32|64)\s+[A-Z]|"
    r"BALL|ENDMILL|KEYSEAT|CUTTER|DRILL|REAMER|INSERT|MILL|TAP\b|COLLET)",
    re.I,
)
_FREIGHT_RE = re.compile(
    r"(?:Total\s+Freight(?:\s+Out)?|Freight(?:\s+Out)?)\s*[:$]?\s*\$?\s*"
    r"([0-9,]+\.\d{2})",
    re.I,
)
_TAX_LABEL_RE = re.compile(
    r"(?:Canada\s+)?(?:GST(?:\s*/\s*HST)?|HST|\bTAX\b)",
    re.I,
)
_AMOUNT_DUE_RE = re.compile(
    r"(?:AMOUNT\s+DUE|GRAND\s+TOTAL)\s*[:$]?\s*\$?\s*([0-9,]+\.\d{2})",
    re.I,
)
_SUBTOTAL_RE = re.compile(
    r"SUB[-\s]?TOTAL\s*[:$]?\s*\$?\s*([0-9,]+\.\d{2})",
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
        return float(str(raw).replace(",", ""))
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


def _first_group(m: Optional[re.Match]) -> str:
    if not m:
        return ""
    for g in m.groups():
        if g:
            return g.strip()
    return ""


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
        if "cho@" in from_a:
            return "order_confirmation"
        return "other"

    def correlate_key(self, parsed: ParsedEmail, message: EmailMessage) -> str:
        """Stable merge key — never a Gmail message id."""
        if parsed.order_reference:
            return parsed.order_reference.strip().upper()
        # Fallback: same calendar day + sorted part numbers (conf↔invoice before order # lands)
        parts = sorted(
            {
                (l.part_number or "").upper()
                for l in parsed.lines
                if l.line_type == "item" and l.part_number
            }
        )
        day = (parsed.purchase_date or "")[:10]
        if parts and day:
            return f"DGI-{day}-{'-'.join(parts[:4])}"
        if parts:
            return f"DGI-PARTS-{'-'.join(parts[:4])}"
        return ""

    def parse(self, message: EmailMessage) -> ParsedEmail:
        email_type = self.classify(message)
        body = _normalize(message.body_text or strip_html_to_text(message.body_html))
        pdf_text = _normalize(self._attachment_pdf_text(message))
        blob = f"{body}\n{pdf_text}"

        invoice = self._find_invoice_number(blob, message)
        order_ref = self._find_order_number(blob, message, invoice=invoice)

        customer_po = self._find_customer_po(blob)

        dm = _INVOICE_DATE_RE.search(blob) or _ORDER_DATE_RE.search(blob)
        purchase_date = _norm_date(dm.group(1) if dm else None)

        am = _AMOUNT_DUE_RE.search(blob)
        total = _money(am.group(1) if am else None)
        sm = _SUBTOTAL_RE.search(blob)
        subtotal = _money(sm.group(1) if sm else None)

        lines: list[ParsedLine] = []
        if email_type in ("order_confirmation", "invoice", "other"):
            lines = self._parse_lines(pdf_text or body, total=total, subtotal=subtotal)

        freight = None
        fm = _FREIGHT_RE.search(blob)
        if fm:
            freight = _money(fm.group(1))

        tax_amt = self._find_tax_amount(blob, total=total, subtotal=subtotal, freight=freight)
        if tax_amt is None:
            tax_amt = self._tax_from_total_minus_lines(
                total=total, freight=freight, lines=lines, subtotal=subtotal
            )

        if freight and freight > 0 and not any(l.line_type == "shipping" for l in lines):
            # DGI Next Day Air is a fixed $34.95 charge on these invoices
            ship_desc = "Next Day Air" if abs(float(freight) - 34.95) < 0.01 else ""
            lines.append(
                ParsedLine(
                    line_type="shipping",
                    description=ship_desc,
                    quantity=1.0,
                    unit_cost=freight,
                )
            )
        if tax_amt and tax_amt > 0 and not any(l.line_type == "tax" for l in lines):
            lines.append(
                ParsedLine(
                    line_type="tax",
                    description="GST",
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
            mime = (att.get("mime_type") or "").lower()
            if not fn:
                continue
            # Never tag logos / signature images as invoice/confirmation
            if self._is_skip_attachment(fn, mime):
                continue
            if not (fn_l.endswith(".pdf") or "pdf" in mime):
                continue
            if "invoice" in fn_l or email_type == "invoice":
                attachment_roles[fn] = "invoice"
            else:
                attachment_roles[fn] = (
                    "confirmation" if email_type == "order_confirmation" else "invoice"
                )

        ok = bool(order_ref or lines)
        error = ""
        if not ok:
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

    @staticmethod
    def _find_customer_po(blob: str) -> str:
        m = _PO_NUMBER_RE.search(blob or "")
        if not m:
            return ""
        raw = m.group(1).strip()
        # Take first token; stop at Net / Carrier / etc.
        tok = raw.split()[0] if raw.split() else raw
        if _PO_STOP.match(tok):
            return ""
        if len(tok) > 24:
            return ""
        return tok.upper()

    @staticmethod
    def _is_skip_attachment(filename: str, mime: str = "") -> bool:
        """Drop logos, signature images, and other non-document attachments."""
        fn = (filename or "").lower()
        mime = (mime or "").lower()
        if any(
            fn.endswith(ext)
            for ext in (
                ".jpg",
                ".jpeg",
                ".png",
                ".gif",
                ".webp",
                ".bmp",
                ".svg",
                ".ico",
            )
        ):
            return True
        if mime.startswith("image/"):
            return True
        if any(k in fn for k in ("logo", "dgilog", "signature", "spacer", "pixel")):
            return True
        return False

    @classmethod
    def _find_invoice_number(cls, blob: str, message: EmailMessage) -> str:
        inv = _first_group(_INVOICE_NUMBER_RE.search(blob or ""))
        if inv:
            return inv
        subj = message.subject or ""
        m = re.search(r"\binvoice\s*#?\s*([0-9]{5,12})\b", subj, re.I)
        if m:
            return m.group(1)
        for att in message.attachments or []:
            fn = att.get("filename") or ""
            # inv_3525554.pdf / invoice-3525554.pdf
            m = re.search(
                r"(?:invoice|inv)[_\s.-]*#?\s*([0-9]{5,12})", fn, re.I
            )
            if m:
                return m.group(1)
            # Live DGI names: 3525554_in_….pdf
            m = re.search(r"\b([0-9]{5,12})_in(?:v(?:oice)?)?[_\-.]", fn, re.I)
            if m:
                return m.group(1)
            m = re.search(r"\b([0-9]{5,12})_in_", fn, re.I)
            if m:
                return m.group(1)
        return ""

    @classmethod
    def _find_order_number(
        cls, blob: str, message: EmailMessage, *, invoice: str = ""
    ) -> str:
        inv = (invoice or "").strip()
        # Prefer an Order Number that is not the invoice #
        for m in _ORDER_NUMBER_RE.finditer(blob or ""):
            hit = _first_group(m)
            if hit and hit != inv:
                return hit
        # Sales / cust order variants
        for pat in (
            r"Sales\s*[\n\r\t ]*Order\s*[:#]?\s*([0-9]{5,10})",
            r"Cust(?:omer)?\s*[\n\r\t ]*Order\s*[:#]?\s*([0-9]{5,10})",
        ):
            m = re.search(pat, blob or "", re.I)
            if m and m.group(1) != inv:
                return m.group(1)
        # Confirmation attachments only — never bare digits from invoice PDFs
        from_a = (message.from_address or "").lower()
        subj = (message.subject or "").lower()
        if "ar_canada" in from_a or "invoice" in subj:
            return ""
        return cls._order_from_filenames(message, invoice=inv)

    @staticmethod
    def _order_from_filenames(
        message: EmailMessage, *, invoice: str = ""
    ) -> str:
        inv = (invoice or "").strip()
        for att in message.attachments or []:
            fn = att.get("filename") or ""
            fn_l = fn.lower()
            # Never pull order # from an invoice-named attachment
            if any(k in fn_l for k in ("invoice", "inv_", "inv-", "inv.")):
                continue
            m = re.search(r"(?:order|ord|ack)[^\d]{0,8}([0-9]{5,10})", fn, re.I)
            if m:
                hit = m.group(1)
                if hit != inv:
                    return hit
            m = re.search(r"\b([0-9]{6,8})\b", fn)
            if m:
                hit = m.group(1)
                if hit != inv:
                    return hit
        return ""

    @classmethod
    def _find_tax_amount(
        cls,
        blob: str,
        *,
        total: Optional[float],
        subtotal: Optional[float],
        freight: Optional[float],
    ) -> Optional[float]:
        """Pick GST/TAX amount — never amount-due / subtotal / freight."""
        banned: set[float] = set()
        for v in (total, subtotal, freight):
            if v is not None:
                banned.add(round(float(v), 2))

        candidates: list[tuple[float, str]] = []
        for m in _TAX_LABEL_RE.finditer(blob or ""):
            window = blob[m.end() : m.end() + 120]
            # Skip leading REG# / percent junk; take the first plausible money
            for money in _EXT2_RE.finditer(window):
                amt = _money(money.group(1))
                if amt is None or amt <= 0:
                    continue
                if round(amt, 2) in banned:
                    continue
                # GST on these orders is a small % of merchandise — reject absurd
                if total and amt >= float(total) * 0.5:
                    continue
                if amt > 200:
                    continue
                candidates.append((amt, m.group(0).lower()))
                break

        if not candidates:
            return None
        # Prefer a match whose label mentions GST
        for amt, label in candidates:
            if "gst" in label:
                return amt
        return candidates[0][0]

    @staticmethod
    def _tax_from_total_minus_lines(
        *,
        total: Optional[float],
        freight: Optional[float],
        lines: list[ParsedLine],
        subtotal: Optional[float],
    ) -> Optional[float]:
        """When GST label is missing from the PDF extract, back into tax."""
        if total is None or total <= 0:
            return None
        freight_v = float(freight or 0)
        if subtotal is not None and subtotal > 0:
            approx = round(float(total) - float(subtotal) - freight_v, 2)
        else:
            items = 0.0
            for l in lines:
                if l.line_type != "item" or l.unit_cost is None:
                    continue
                items += float(l.unit_cost) * float(l.quantity or 1)
            if items <= 0:
                return None
            approx = round(float(total) - items - freight_v, 2)
        if 0.5 <= approx <= 200:
            return approx
        return None

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

    def _parse_lines(
        self,
        text: str,
        *,
        total: Optional[float] = None,
        subtotal: Optional[float] = None,
    ) -> list[ParsedLine]:
        """DGI PDFs shuffle columns — pair HVT ids with 4-decimal unit prices."""
        blob = text or ""
        banned = {round(float(v), 2) for v in (total, subtotal) if v is not None}

        # Collect raw HVT hits, normalize trailing glued digits
        raw_hits: list[tuple[int, int, str]] = []
        for m in _HVT_RE.finditer(blob):
            part = self._normalize_part(m.group(1).upper(), blob)
            if not part:
                continue
            raw_hits.append((m.start(), m.end(), part))

        # Dedupe by part, keep first index
        seen: set[str] = set()
        ordered: list[tuple[int, int, str]] = []
        for start, end, part in raw_hits:
            if part in seen:
                continue
            seen.add(part)
            ordered.append((start, end, part))

        # Unit prices only in the merchandise region (before footer totals)
        footer = _FOOTER_RE.search(blob)
        body_end = footer.start() if footer else len(blob)
        body = blob[:body_end]
        prices: list[tuple[int, int, float]] = []
        for m in _UNIT4_RE.finditer(body):
            amt = _money(m.group(1))
            if amt is None or amt <= 0 or amt > 5000:
                continue
            if round(amt, 2) in banned:
                continue
            prices.append((m.start(), m.end(), round(float(amt), 2)))

        units = self._assign_unit_prices(ordered, prices, blob)

        lines: list[ParsedLine] = []
        for i, (idx, end, part) in enumerate(ordered):
            prev_end = ordered[i - 1][1] if i > 0 else 0
            next_idx = ordered[i + 1][0] if i + 1 < len(ordered) else body_end
            before = blob[prev_end:idx]
            after = blob[idx:next_idx]
            unit = units.get(part)
            if unit is None:
                # Last-resort: local window, never footer TAX/subtotal amounts
                local = self._cut_footer(after)
                unit = self._unit_price_near(local, banned=banned, prefer_near=0)
                if unit is None:
                    unit = self._unit_price_near(
                        before, banned=banned, prefer_near=len(before)
                    )
            # Prefer text around this line's unit price (avoids stealing neighbor titles)
            others = [p for (_s, _e, p) in ordered if p != part]
            desc = self._best_description(
                part, others, unit=unit, blob=blob, before=before, after=after
            )
            lines.append(
                ParsedLine(
                    line_type="item",
                    description=desc[:500] or part,
                    part_number=part,
                    quantity=1.0,
                    unit_cost=unit,
                )
            )
        return lines

    @classmethod
    def _assign_unit_prices(
        cls,
        parts: list[tuple[int, int, str]],
        prices: list[tuple[int, int, float]],
        blob: str,
    ) -> dict[str, float]:
        """1:1 HVT↔unit price. Clean PDFs are part→price; scrambled are price→part."""
        if not parts or not prices:
            return {}

        assigned: dict[str, float] = {}
        used_price: set[int] = set()

        def _take(part: str, ps: int, amt: float) -> None:
            if part in assigned or ps in used_price:
                return
            assigned[part] = amt
            used_price.add(ps)

        # Pass 1: HVT then unit price for *this* line (clean + invoice mid-line).
        # Skip when the next UNIT4 is really the following item (scrambled layout).
        for i, (start, end, part) in enumerate(parts):
            next_start = parts[i + 1][0] if i + 1 < len(parts) else len(blob)
            region = cls._cut_footer(blob[end:next_start])
            m = _UNIT4_RE.search(region)
            if not m or m.start() > 120:
                continue
            between = region[: m.start()]
            # Immediate "HVT68320 EA 189.5300" — require EA so a bare newline
            # before the *next* item's price (scrambled) does not match.
            close = m.start() <= 24 and bool(re.search(r"\bEA\b", between, re.I))
            owned = cls._catalog_score(part, between) >= 40 or bool(
                _DESC_START_RE.search(between)
            )
            if not (close or owned):
                continue
            abs_pos = end + m.start()
            hit = next((p for p in prices if abs(p[0] - abs_pos) <= 1), None)
            if not hit:
                continue
            _take(part, hit[0], hit[2])

        # Pass 2: unit price then HVT with catalog digits between (scrambled conf)
        for ps, pe, amt in prices:
            if ps in used_price:
                continue
            best: Optional[str] = None
            best_score = -1
            for start, end, part in parts:
                if part in assigned:
                    continue
                if start < pe:
                    continue
                gap = start - pe
                if gap > 220:
                    continue
                window = blob[pe:start]
                if _UNIT4_RE.search(window):
                    continue
                cat = cls._catalog_score(part, window)
                if cat < 40:
                    # Require catalog/desc evidence so invoice doesn't steal
                    continue
                score = cat + max(0, 40 - gap // 5)
                if score > best_score:
                    best_score = score
                    best = part
            if best:
                _take(best, ps, amt)

        # Pass 3: residual unmatched — catalog score, then document order
        leftover_prices = [p for p in prices if p[0] not in used_price]
        leftover_parts = [p for p in parts if p[2] not in assigned]
        if leftover_prices and leftover_parts:
            pairs: list[tuple[int, int, float, str]] = []
            for ps, pe, amt in leftover_prices:
                for start, end, part in leftover_parts:
                    win = blob[max(0, ps - 40) : min(len(blob), pe + 100)]
                    # Exclude other HVTs already assigned from inflating score
                    score = cls._catalog_score(part, win)
                    if end <= ps <= end + 60:
                        score += 35  # part just before this price
                    if pe <= start <= pe + 160:
                        score += 10
                    pairs.append((score, ps, amt, part))
            pairs.sort(key=lambda t: t[0], reverse=True)
            for score, ps, amt, part in pairs:
                if score < 35:
                    break
                if part in assigned or ps in used_price:
                    continue
                _take(part, ps, amt)
            still_prices = [p for p in leftover_prices if p[0] not in used_price]
            still_parts = [p for p in leftover_parts if p[2] not in assigned]
            for (_ps, _pe, amt), (_s, _e, part) in zip(still_prices, still_parts):
                _take(part, _ps, amt)

        return assigned

    @staticmethod
    def _catalog_score(part: str, window: str) -> int:
        """How well a part number's catalog digits appear in nearby text."""
        rest = (part or "")[3:]
        if not rest or not window:
            return 0
        score = 0
        if re.search(rf"\b{re.escape(part)}\b", window, re.I):
            score += 100
        m = re.match(r"^(\d+)([A-Z]\d*)$", rest)
        if m:
            catalog = f"{m.group(1)}-{m.group(2)}"
            if re.search(rf"\b{re.escape(catalog)}\b", window, re.I):
                score += 90
            if re.search(rf"\b{re.escape(m.group(1))}\b", window):
                score += 50
            if re.search(rf"\b{re.escape(rest)}\b", window, re.I):
                score += 70
        elif rest.isdigit() and re.search(rf"\b{re.escape(rest)}\b", window):
            score += 80
        return score

    @staticmethod
    def _cut_footer(window: str) -> str:
        m = _FOOTER_RE.search(window or "")
        if not m:
            return window or ""
        return window[: m.start()]

    @classmethod
    def _normalize_part(cls, part: str, blob: str) -> str:
        """Strip glued trailing qty digit: HVT989816C41 → HVT989816C4, HVT683201 → HVT68320."""
        p = (part or "").upper()
        if not p.startswith("HVT"):
            return p

        def _well_formed(cand: str) -> bool:
            # 68320 or 989816C4 — not a dangling letter like 989816C
            return bool(re.match(r"^HVT\d+(?:[A-Z]\d+)?$", cand))

        candidates = [p]
        if p[-1].isdigit() and len(p) > 8:
            shorter = p[:-1]
            if _well_formed(shorter) or re.search(
                rf"\b{re.escape(shorter)}\b", blob, re.I
            ):
                candidates.append(shorter)

        def _score(cand: str) -> int:
            rest = cand[3:]
            score = 0
            m = re.match(r"^(\d+)([A-Z]\d+)$", rest)
            m_num = re.match(r"^(\d+)$", rest)
            if m:
                catalog = f"{m.group(1)}-{m.group(2)}"
                if re.search(rf"\b{re.escape(catalog)}\b", blob, re.I):
                    score += 50
                if re.search(rf"\b{re.escape(rest)}\b", blob, re.I):
                    score += 30
                score += 15  # prefer letter+digit variant codes
            elif m_num:
                if re.search(rf"\b{re.escape(rest)}\b", blob):
                    score += 30
            if _well_formed(cand):
                score += 20
            # Prefer shorter when both well-formed (glued trailing qty 1)
            score += max(0, 20 - len(cand))
            return score

        return sorted(candidates, key=_score, reverse=True)[0]

    @staticmethod
    def _unit_price_near(
        window: str, *, banned: set[float], prefer_near: int = 0
    ) -> Optional[float]:
        """Prefer 4-decimal DGI unit prices closest to the part-number position."""
        window = DgiSupplyAdapter._cut_footer(window)
        hits: list[tuple[int, float]] = []
        for m in _UNIT4_RE.finditer(window):
            amt = _money(m.group(1))
            if amt is None or amt <= 0 or amt > 5000:
                continue
            if round(amt, 2) in banned:
                continue
            hits.append((m.start(), round(float(amt), 2)))
        if hits:
            hits.sort(key=lambda t: abs(t[0] - prefer_near))
            return hits[0][1]
        money: list[tuple[int, float]] = []
        for m in _EXT2_RE.finditer(window):
            amt = _money(m.group(1))
            if amt is None or amt <= 0 or amt > 5000:
                continue
            if round(amt, 2) in banned:
                continue
            if not (1.0 <= amt <= 2000):
                continue
            money.append((m.start(), amt))
        if not money:
            return None
        money.sort(key=lambda t: abs(t[0] - prefer_near))
        return money[0][1]

    @classmethod
    def _best_description(
        cls,
        part: str,
        others: list[str],
        *,
        unit: Optional[float],
        blob: str,
        before: str,
        after: str,
    ) -> str:
        # Exclusive span between this unit price and the next — no neighbor bleed
        span_desc = cls._description_from_price_span(blob, part, unit, others)
        if span_desc:
            return span_desc[:500]

        unit_desc = cls._description_for_unit(blob, part, unit)
        if (
            unit_desc
            and _DESC_START_RE.search(unit_desc)
            and cls._description_belongs(part, unit_desc, others)
        ):
            return unit_desc[:500]

        candidates = [
            unit_desc,
            cls._description_near(before, part),
            cls._description_near(after, part),
            cls._description_near(before + " " + after, part),
        ]
        scored: list[tuple[int, str]] = []
        for desc in candidates:
            if not desc or len(desc) < 8:
                continue
            if not cls._description_belongs(part, desc, others):
                continue
            score = cls._catalog_score(part, desc)
            if _DESC_START_RE.search(desc):
                score += 20
            scored.append((score, desc))
        if scored:
            scored.sort(key=lambda t: (t[0], -len(t[1])), reverse=True)
            return scored[0][1][:500]
        if unit_desc:
            cleaned = cls._strip_foreign_catalog(unit_desc, part, others)
            if cleaned and _DESC_START_RE.search(cleaned):
                return cleaned[:500]
        for desc in candidates[1:]:
            if desc and len(desc) >= 8:
                cleaned = cls._strip_foreign_catalog(desc, part, others)
                if (
                    cleaned
                    and _DESC_START_RE.search(cleaned)
                    and cls._description_belongs(part, cleaned, others)
                ):
                    return cleaned[:500]
        return part

    @classmethod
    def _description_from_price_span(
        cls,
        blob: str,
        part: str,
        unit: Optional[float],
        others: list[str],
    ) -> str:
        """Title text owned by this line's unit price until the next unit price."""
        if unit is None:
            return ""
        target = round(float(unit), 2)
        price_hits = [
            (m.start(), m.end())
            for m in _UNIT4_RE.finditer(blob or "")
            if round(float(m.group(1)), 2) == target
        ]
        if not price_hits:
            return ""
        all_prices = [(m.start(), m.end()) for m in _UNIT4_RE.finditer(blob or "")]
        best = ""
        best_score = -1
        for ps, pe in price_hits:
            next_ps = min((p[0] for p in all_prices if p[0] > ps), default=len(blob))
            # Include a short lookback for "HVT… EA 189.5300" / glued titles after price
            start = max(0, ps - 60)
            # Don't start inside a previous unit price span
            prev = [p for p in all_prices if p[0] < ps]
            if prev:
                start = max(start, prev[-1][1])
            end = next_ps
            # Stop before a different HVT that is not this part
            for hm in _HVT_RE.finditer(blob[pe:end]):
                other = cls._normalize_part(hm.group(1).upper(), blob)
                if other and other != part:
                    end = pe + hm.start()
                    break
            slice_ = cls._cut_footer(blob[start:end])
            desc = cls._description_near(slice_, part)
            if not desc or not _DESC_START_RE.search(desc):
                continue
            if not cls._description_belongs(part, desc, others):
                continue
            score = cls._catalog_score(part, desc) + len(desc)
            if score > best_score:
                best_score = score
                best = desc
        return best

    @classmethod
    def _description_belongs(cls, part: str, desc: str, others: list[str]) -> bool:
        """Reject titles that clearly belong to a different HVT on the order."""
        own = cls._catalog_score(part, desc)
        foreign = max((cls._catalog_score(o, desc) for o in others), default=0)
        if foreign >= 70 and foreign > own:
            return False
        # Keyword families: ball/endmill vs keyseat must not cross
        d = (desc or "").upper()
        rest = (part or "")[3:]
        if "KEYSEAT" in d and own < 40 and not rest.isdigit():
            # Letter-variant parts (989816C4) are endmills, not keyseats
            return False
        if ("BALL" in d or "ENDMILL" in d) and "KEYSEAT" not in d:
            if rest.isdigit() and own < 40:
                # Pure numeric Harvey codes on this order are the keyseat line
                return False
        return True

    @classmethod
    def _strip_foreign_catalog(cls, desc: str, part: str, others: list[str]) -> str:
        raw = desc
        for o in others:
            if cls._catalog_score(o, raw) >= 70:
                # Drop the other part's catalog token + HVT id if present
                rest = o[3:]
                raw = re.sub(rf"\b{re.escape(o)}\b", " ", raw, flags=re.I)
                if rest:
                    raw = re.sub(rf"\b{re.escape(rest)}\b", " ", raw, flags=re.I)
                m = re.match(r"^(\d+)([A-Z]\d+)$", rest)
                if m:
                    cat = f"{m.group(1)}-{m.group(2)}"
                    raw = re.sub(rf"\b{re.escape(cat)}\b", " ", raw, flags=re.I)
        raw = re.sub(r"\s+", " ", raw).strip()
        return raw if len(raw) >= 8 else ""

    @classmethod
    def _description_for_unit(
        cls, blob: str, part: str, unit: Optional[float]
    ) -> str:
        if unit is None:
            return ""
        target = round(float(unit), 2)
        best = ""
        for m in _UNIT4_RE.finditer(blob or ""):
            if round(float(m.group(1)), 2) != target:
                continue
            rest = blob[m.end() :]
            nm = _UNIT4_RE.search(rest)
            span = nm.start() if nm and nm.start() < 160 else 160
            start = max(0, m.start() - 50)
            end = m.end() + span
            # Drop a previous line's HVT from the lookback
            pre = blob[start : m.start()]
            for hm in _HVT_RE.finditer(pre):
                other = cls._normalize_part(hm.group(1).upper(), blob)
                if other and other != part:
                    start = start + hm.end()
            # Don't run into the next HVT of a different part
            for hm in _HVT_RE.finditer(blob[m.end() : end]):
                other = cls._normalize_part(hm.group(1).upper(), blob)
                if other and other != part:
                    end = m.end() + hm.start()
                    break
            slice_ = cls._cut_footer(blob[start:end])
            desc = cls._description_near(slice_, part)
            if _DESC_START_RE.search(desc) and len(desc) >= len(best):
                best = desc
        return best

    @staticmethod
    def _description_near(window: str, part: str) -> str:
        raw = re.sub(r"\s+", " ", window or "").strip()
        # Prefer text starting at a product-y token
        m = _DESC_START_RE.search(raw)
        if m:
            raw = raw[m.start() :].strip()
        # Cut at footer noise
        raw = re.split(
            r"\b(?:SUB-?TOTAL|TOTAL\s+FREIGHT|AMOUNT\s+DUE|Canada\s+GST|TAX\b|"
            r"Expected\s+Delivery|Total\s+Lines)\b",
            raw,
            maxsplit=1,
            flags=re.I,
        )[0].strip()
        # Drop leading price/qty crumbs
        raw = re.sub(
            r"^(?:[\d.,]+\s+|EA\s+|R\s+|1\.0\s+|1\.00\s+)+",
            "",
            raw,
            flags=re.I,
        ).strip()
        # Drop duplicate part at end (do not re-append — that fools catalog scoring)
        raw = re.sub(rf"\s*{re.escape(part)}\s*$", "", raw, flags=re.I).strip()
        # Drop glued trailing catalog-only fragments after a clean title
        if len(raw) > 180:
            raw = raw[:180].rsplit(" ", 1)[0]
        return raw[:500]


ADAPTER = DgiSupplyAdapter()
