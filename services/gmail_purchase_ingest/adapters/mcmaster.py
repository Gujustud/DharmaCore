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
_ORDER_RE = re.compile(
    r"(?:order\s*(?:#|number|no\.?)|confirmation\s*(?:#|number)?)\s*[:#]?\s*([A-Z0-9-]{3,})",
    re.I,
)
_INVOICE_RE = re.compile(r"(?:invoice\s*(?:#|number|no\.?)?)\s*[:#]?\s*([A-Z0-9-]+)", re.I)
_TRACKING_RE = re.compile(
    r"(?:tracking\s*(?:#|number|no\.?)?)\s*[:#]?\s*([A-Z0-9]+)",
    re.I,
)
_TOTAL_RE = re.compile(r"(?:order\s*total|total(?:\s*due)?)\s*[:$]?\s*\$?\s*([0-9,]+\.[0-9]{2})", re.I)
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

        if any(k in subject for k in ("certificate", "cert of", "mill cert", "coc", "c of c")):
            return "certificate"
        if any(k in names for k in ("cert", "coc", "mill")) and "order" not in subject:
            if "invoice" not in subject:
                return "certificate"
        if "invoice" in subject or "invoice" in body[:500]:
            return "invoice"
        if any(k in subject for k in ("shipped", "shipping", "tracking", "on the way", "out for")):
            return "shipping"
        if any(k in subject for k in ("order confirmation", "thanks for your order", "order received")):
            return "order_confirmation"
        if "order" in subject and "confirm" in subject:
            return "order_confirmation"
        return "other"

    def correlate_key(self, parsed: ParsedEmail, message: EmailMessage) -> str:
        if parsed.order_reference:
            return parsed.order_reference.strip().upper()
        # Fall back to thread id so related mails still group
        return (message.gmail_thread_id or message.gmail_message_id or "").strip()

    def parse(self, message: EmailMessage) -> ParsedEmail:
        text = message.body_text or strip_html_to_text(message.body_html)
        email_type = self.classify(message)
        order_ref = self._find_order(text, message.subject)
        invoice = self._find_first(_INVOICE_RE, text) or ""
        tracking = self._find_first(_TRACKING_RE, text) or ""
        total = self._find_money_total(text)
        purchase_date = self._normalize_date(self._find_first(_DATE_RE, text))

        lines: list[ParsedLine] = []
        parse_notes = ""
        if email_type in ("order_confirmation", "invoice", "other"):
            lines = self._parse_lines(text)
            if not lines and email_type == "order_confirmation":
                parse_notes = "No line items extracted; review manually."

        if email_type == "shipping" and tracking:
            parse_notes = f"Tracking: {tracking}"

        attachment_roles: dict[str, str] = {}
        for att in message.attachments:
            fn = (att.get("filename") or "").lower()
            if any(k in fn for k in ("cert", "coc", "mill", "coa")):
                attachment_roles[att.get("filename", "")] = "mill_cert"
            elif "invoice" in fn:
                attachment_roles[att.get("filename", "")] = "invoice"
            elif fn.endswith(".pdf"):
                if email_type == "certificate":
                    attachment_roles[att.get("filename", "")] = "mill_cert"
                elif email_type == "invoice":
                    attachment_roles[att.get("filename", "")] = "invoice"

        ok = True
        error = ""
        if email_type == "order_confirmation" and not order_ref and not lines:
            ok = False
            error = "Could not extract order reference or line items"

        return ParsedEmail(
            email_type=email_type,
            order_reference=order_ref or "",
            invoice=invoice,
            tracking=tracking,
            currency="USD",
            purchase_date=purchase_date,
            total=total,
            notes=parse_notes,
            lines=lines,
            attachment_roles=attachment_roles,
            parse_notes=parse_notes,
            ok=ok,
            error=error,
        )

    def _find_order(self, text: str, subject: str) -> str:
        for blob in (subject or "", text or ""):
            m = _ORDER_RE.search(blob)
            if m:
                return m.group(1).strip()
        # Subject often is "McMaster-Carr Order 1234567"
        m = re.search(r"order(?:\s+confirmation)?\s+#?\s*([0-9]{3,10})", subject or "", re.I)
        if m:
            return m.group(1)
        return ""

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
        # last money amount as weak fallback — skip for safety
        return None

    @staticmethod
    def _normalize_date(raw: Optional[str]) -> Optional[str]:
        if not raw:
            return None
        raw = raw.strip()
        if re.match(r"\d{4}-\d{2}-\d{2}$", raw):
            return raw
        # Leave non-ISO for humans; PB date fields prefer ISO — try common forms
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
            line = self._line_from_desc(part, desc, qty, each)
            lines.append(line)

        if lines:
            return lines

        # Fallback: find part numbers and nearby money/qty on same line
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
            grade = gm.group(1).upper().replace(" ", "")
            if grade.lower().startswith("grade"):
                grade = gm.group(1).strip()

        form = ""
        for rx, key in _FORM_HINTS:
            if rx.search(desc):
                form = key
                break

        size_label = ""
        sm = _SIZE_RE.search(desc)
        if sm:
            size_label = re.sub(r"\s+", " ", sm.group(1).strip())

        is_material = bool(grade or form)
        # Hardware / misc if no material signals
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
