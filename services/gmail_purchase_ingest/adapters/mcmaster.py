"""Deterministic McMaster-Carr email parser."""

from __future__ import annotations

import re
from typing import Optional

from .base import (
    EmailMessage,
    ParsedEmail,
    ParsedLine,
    from_domain_matches,
    strip_html_to_text,
)

DEFAULT_DOMAINS = ["mcmaster.com", "mcmastercarr.com"]

# Common McMaster material title patterns
_GRADE_RE = re.compile(
    r"\b("
    r"6061(?:-T6)?|7075(?:-T6)?|2024(?:-T3)?|5052|"
    r"304(?:L)?|316(?:L)?|410|17-4(?:\s*PH)?|"
    r"4140|4340|A36|A572|1018|1045|12L14|"
    r"Delrin|Acetal|Nylon|UHMW|PTFE|Copper|Brass|Bronze|"
    r"Ti-?6Al-4V|Grade\s*\d+"
    r")\b",
    re.I,
)
_FORM_HINTS = [
    (re.compile(r"\b(round\s+)?bar\b|\brod\b|\bdia\.?\b|\bdiameter\b", re.I), "bar"),
    (re.compile(r"\bplate\b", re.I), "plate"),
    (re.compile(r"\bsheet\b", re.I), "sheet"),
    (re.compile(r"\btube\b|\btubing\b|\bpipe\b", re.I), "tube"),
    (re.compile(r"\bhex\b", re.I), "hex"),
    (re.compile(r"\bflat\s+bar\b|\brectangular\b", re.I), "flat"),
]

# Primary: "McMaster-Carr number 7110963" (body of confirmation / cert / receipt)
_MCMASTER_NUMBER_RE = re.compile(
    r"McMaster(?:-Carr)?\s+number\s*[:#]?\s*([0-9]{6,10})",
    re.I,
)
# Explicit order number labels (not "Confirmation for Your October…")
_ORDER_NUMBER_RE = re.compile(
    r"(?:order\s*(?:#|number|no\.?)\s*[:#]?\s*|confirmation\s*(?:#|number)\s*[:#]?\s*)"
    r"([0-9]{6,10})",
    re.I,
)
# Customer / job ref shown next to McMaster number, e.g. 1013ASOLANKI
_CUSTOMER_PO_RE = re.compile(
    r"\b([0-9]{3,4}A[A-Z0-9]{4,})\b",
    re.I,
)
# Subject date fallback: "October 13th Order" → merge same calendar order day
_SUBJECT_ORDER_DAY_RE = re.compile(
    r"(January|February|March|April|May|June|July|August|September|October|"
    r"November|December)\s+(\d{1,2})(?:st|nd|rd|th)?\s+Order",
    re.I,
)

_INVOICE_RE = re.compile(
    r"(?:invoice|receipt)\s*(?:#|number|no\.?)?\s*[:#]?\s*([A-Z0-9-]+)",
    re.I,
)
_TRACKING_RE = re.compile(
    r"(?:tracking\s*(?:#|number|no\.?)?|AWB\s*#?|Purolator|UPS|FedEx|DHL)"
    r"[^\n]{0,40}?\b([A-Z0-9]{8,22})\b",
    re.I,
)
_TRACKING_SIMPLE_RE = re.compile(
    r"(?:tracking\s*(?:#|number|no\.?)?)\s*[:#]?\s*([A-Z0-9]+)",
    re.I,
)
_TOTAL_RE = re.compile(
    r"(?:order\s*total|total(?:\s*due)?|amount\s*due)\s*[:$]?\s*\$?\s*([0-9,]+\.[0-9]{2})",
    re.I,
)
_DATE_RE = re.compile(
    r"\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}"
    r"|\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{2,4})\b",
    re.I,
)
# McMaster part numbers are typically like 8975K123 or 9287T11
_PART_LINE_RE = re.compile(
    r"(?P<part>[0-9]{3,5}[A-Z][0-9A-Z]{2,8})\s+"
    r"(?P<desc>.+?)\s+"
    r"(?P<qty>\d+(?:\.\d+)?)\s+"
    r"(?:\$?\s*(?P<each>[0-9,]+\.[0-9]{2}))?",
    re.I,
)
_PART_ONLY_RE = re.compile(r"\b([0-9]{3,5}[A-Z][0-9A-Z]{2,8})\b")
_MONEY_RE = re.compile(r"\$\s*([0-9,]+\.[0-9]{2})")
_SIZE_RE = re.compile(
    r"("
    r"\d+(?:\.\d+)?\s*(?:\"|in|inch|mm)?\s*(?:dia(?:meter|\.)?|OD|ID)?"
    r"(?:\s*[x×]\s*\d+(?:\.\d+)?\s*(?:\"|in|ft|mm)?){0,3}"
    r"|\d+/\d+\s*(?:\"|in)?"
    r")",
    re.I,
)

_MONTHS = {
    "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11,
    "december": 12,
}


class McMasterAdapter:
    vendor_key = "mcmaster"
    display_name = "McMaster-Carr"
    default_domains = list(DEFAULT_DOMAINS)

    def detect(self, message: EmailMessage, domains: list[str]) -> bool:
        use = domains or self.default_domains
        if from_domain_matches(message.from_address, use):
            return True
        blob = f"{message.subject}\n{message.from_address}".lower()
        return "mcmaster" in blob

    def classify(self, message: EmailMessage) -> str:
        subject = (message.subject or "").lower()
        body = (message.body_text or "").lower()
        names = " ".join(a.get("filename", "") for a in message.attachments).lower()

        # Combined "Certificate and Tracking for Your … Order"
        if "certificate" in subject and "tracking" in subject:
            return "certificate"
        if any(k in subject for k in ("certificate", "cert of", "mill cert", "coc", "c of c")):
            return "certificate"
        if any(k in names for k in ("cert", "coc", "mill")) and "confirm" not in subject:
            if "receipt" not in subject and "invoice" not in subject:
                return "certificate"
        # McMaster calls invoices "Receipt for Your … Order"
        if "receipt" in subject or "invoice" in subject:
            return "invoice"
        if "invoice" in body[:500] and "confirm" not in subject:
            return "invoice"
        if any(k in subject for k in ("shipped", "shipping", "tracking", "on the way", "out for")):
            return "shipping"
        if "confirmation" in subject or (
            "confirm" in subject and "order" in subject
        ):
            return "order_confirmation"
        if any(k in subject for k in ("thanks for your order", "order received")):
            return "order_confirmation"
        return "other"

    def correlate_key(self, parsed: ParsedEmail, message: EmailMessage) -> str:
        """Always prefer McMaster order number so conf/cert/receipt merge."""
        if parsed.order_reference and not parsed.order_reference.startswith("MC-DAY-"):
            return parsed.order_reference.strip().upper()
        if parsed.order_reference:
            return parsed.order_reference.strip().upper()
        day_key = self._subject_order_day_key(
            message.subject or "", message.received_at
        )
        return day_key or ""

    def parse(self, message: EmailMessage) -> ParsedEmail:
        text = message.body_text or strip_html_to_text(message.body_html)
        email_type = self.classify(message)
        order_ref = self._find_order(text, message.subject)
        customer_po = self._find_customer_po(text, message.subject)
        invoice = self._find_first(_INVOICE_RE, text) or ""
        tracking = self._find_tracking(text)
        total = self._find_money_total(text)
        purchase_date = self._normalize_date(self._find_first(_DATE_RE, text))
        subj_day = self._subject_order_day_iso(
            message.subject or "", message.received_at
        )
        if subj_day and email_type == "order_confirmation":
            purchase_date = purchase_date or subj_day

        lines: list[ParsedLine] = []
        parse_notes_parts: list[str] = []
        if customer_po:
            parse_notes_parts.append(f"Customer ref: {customer_po}")
        if email_type in ("order_confirmation", "invoice", "other"):
            lines = self._parse_lines(text)
            if not lines and email_type == "order_confirmation":
                parse_notes_parts.append("No line items extracted; review manually.")

        if tracking and email_type in ("shipping", "certificate", "invoice"):
            parse_notes_parts.append(f"Tracking: {tracking}")

        attachment_roles: dict[str, str] = {}
        for att in message.attachments:
            fn = (att.get("filename") or "")
            fn_l = fn.lower()
            if any(k in fn_l for k in ("cert", "coc", "mill", "coa")):
                attachment_roles[fn] = "mill_cert"
            elif any(k in fn_l for k in ("invoice", "receipt")):
                attachment_roles[fn] = "invoice"
            elif fn_l.endswith(".pdf"):
                if email_type == "certificate":
                    attachment_roles[fn] = "mill_cert"
                elif email_type == "invoice":
                    attachment_roles[fn] = "invoice"
                elif email_type == "order_confirmation":
                    attachment_roles[fn] = "confirmation"

        ok = True
        error = ""
        if not order_ref:
            day_key = self._subject_order_day_key(
                message.subject or "", message.received_at
            )
            if day_key:
                order_ref = day_key
            elif email_type == "order_confirmation" and not lines:
                ok = False
                error = "Could not extract McMaster order number or line items"

        return ParsedEmail(
            email_type=email_type,
            order_reference=order_ref or "",
            invoice=invoice,
            tracking=tracking,
            currency="USD",
            purchase_date=purchase_date,
            total=total,
            notes="\n".join(parse_notes_parts),
            lines=lines,
            attachment_roles=attachment_roles,
            parse_notes="\n".join(parse_notes_parts),
            ok=ok,
            error=error,
        )

    def _find_order(self, text: str, subject: str) -> str:
        blob = f"{text or ''}\n{subject or ''}"
        m = _MCMASTER_NUMBER_RE.search(blob)
        if m:
            return m.group(1).strip()
        m = _ORDER_NUMBER_RE.search(blob)
        if m:
            return m.group(1).strip()
        # Do NOT match "Confirmation for Your October…" — that produced Ref: FOR
        return ""

    def _find_customer_po(self, text: str, subject: str) -> str:
        blob = f"{text or ''}\n{subject or ''}"
        # Prefer PO near McMaster number
        m = _MCMASTER_NUMBER_RE.search(blob)
        if m:
            window = blob[m.end() : m.end() + 80]
            pm = _CUSTOMER_PO_RE.search(window)
            if pm:
                return pm.group(1).upper()
        m = _CUSTOMER_PO_RE.search(blob)
        return m.group(1).upper() if m else ""

    def _find_tracking(self, text: str) -> str:
        m = _TRACKING_SIMPLE_RE.search(text or "")
        if m:
            return m.group(1).strip()
        m = _TRACKING_RE.search(text or "")
        if m:
            return m.group(1).strip()
        return ""

    def _subject_order_day_key(
        self, subject: str, received_at: Optional[str] = None
    ) -> str:
        iso = self._subject_order_day_iso(subject, received_at)
        return f"MC-DAY-{iso}" if iso else ""

    def _subject_order_day_iso(
        self, subject: str, received_at: Optional[str] = None
    ) -> str:
        m = _SUBJECT_ORDER_DAY_RE.search(subject or "")
        if not m:
            return ""
        month = _MONTHS.get(m.group(1).lower())
        day = int(m.group(2))
        if not month:
            return ""
        y_m = re.search(r"\b(20\d{2})\b", subject or "")
        year = int(y_m.group(1)) if y_m else 0
        if not year and received_at:
            ym = re.match(r"(20\d{2})", received_at)
            if ym:
                year = int(ym.group(1))
        if not year:
            return ""
        return f"{year:04d}-{month:02d}-{day:02d}"

    @staticmethod
    def _find_first(pattern: re.Pattern, text: str) -> Optional[str]:
        m = pattern.search(text or "")
        return m.group(1).strip() if m else None

    @staticmethod
    def _find_money_total(text: str) -> Optional[float]:
        m = _TOTAL_RE.search(text or "")
        if m:
            try:
                return float(m.group(1).replace(",", ""))
            except ValueError:
                return None
        return None

    @staticmethod
    def _normalize_date(raw: Optional[str]) -> Optional[str]:
        if not raw:
            return None
        raw = raw.strip()
        if re.match(r"\d{4}-\d{2}-\d{2}$", raw):
            return raw
        months = {
            "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
            "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
        }
        m = re.match(
            r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})",
            raw,
            re.I,
        )
        if m:
            mo = months[m.group(1)[:3].lower()]
            return f"{int(m.group(3)):04d}-{mo:02d}-{int(m.group(2)):02d}"
        m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{2,4})$", raw)
        if m:
            y = int(m.group(3))
            if y < 100:
                y += 2000
            return f"{y:04d}-{int(m.group(1)):02d}-{int(m.group(2)):02d}"
        return None

    def _parse_lines(self, text: str) -> list[ParsedLine]:
        lines: list[ParsedLine] = []
        seen_parts: set[str] = set()

        for m in _PART_LINE_RE.finditer(text or ""):
            part = m.group("part").upper()
            if part in seen_parts:
                continue
            seen_parts.add(part)
            desc = (m.group("desc") or "").strip()
            desc = re.sub(r"\s+", " ", desc)
            try:
                qty = float(m.group("qty") or 1)
            except ValueError:
                qty = 1.0
            each = None
            if m.group("each"):
                try:
                    each = float(m.group("each").replace(",", ""))
                except ValueError:
                    each = None
            lines.append(self._line_from_desc(part, desc, qty, each))

        if lines:
            return lines

        for raw_line in (text or "").splitlines():
            pm = _PART_ONLY_RE.search(raw_line)
            if not pm:
                continue
            part = pm.group(1).upper()
            if part in seen_parts:
                continue
            money = _MONEY_RE.findall(raw_line)
            each = float(money[0].replace(",", "")) if money else None
            qty_m = re.search(r"\b(\d+(?:\.\d+)?)\b", raw_line[pm.end() :])
            qty = float(qty_m.group(1)) if qty_m else 1.0
            desc = raw_line.strip()
            seen_parts.add(part)
            lines.append(self._line_from_desc(part, desc, qty, each))

        return lines

    def _line_from_desc(
        self, part: str, desc: str, qty: float, each: Optional[float]
    ) -> ParsedLine:
        grade = ""
        gm = _GRADE_RE.search(desc)
        if gm:
            grade = gm.group(1).strip()
            if not grade.lower().startswith("grade"):
                # Keep Delrin / Acetal readable; alloys can be uppercased
                if re.match(r"^[0-9A-Z-]+$", grade, re.I) and not re.search(
                    r"[a-z]{3,}", grade
                ):
                    grade = grade.upper().replace(" ", "")

        form = ""
        for rx, key in _FORM_HINTS:
            if rx.search(desc):
                form = key
                break

        size_label = ""
        sm = _SIZE_RE.search(desc)
        if sm:
            size_label = re.sub(r"\s+", " ", sm.group(1).strip())

        # Plastics / metals with bar/plate/etc. count as material
        is_material = bool(grade or form) or bool(
            re.search(r"\b(resin|plastic|steel|aluminum|aluminium)\b", desc, re.I)
            and form
        )
        if not is_material and form:
            is_material = True
        line_type = "material" if is_material else "misc"

        return ParsedLine(
            line_type=line_type,
            description=desc[:500],
            part_number=part,
            quantity=qty,
            unit_cost=each,
            grade=grade,
            form=form or ("other" if is_material else ""),
            size_label=size_label,
            unit="ea",
        )


ADAPTER = McMasterAdapter()
