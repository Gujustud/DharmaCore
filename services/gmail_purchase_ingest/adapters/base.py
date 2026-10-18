"""Vendor adapter contract for Gmail purchase ingest."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional, Protocol


EMAIL_TYPES = (
    "order_confirmation",
    "shipping",
    "invoice",
    "certificate",
    "other",
)

LINE_TYPES = ("item", "material", "misc", "tax", "shipping")


@dataclass
class ParsedLine:
    line_type: str  # item|material|misc|tax|shipping
    description: str = ""
    part_number: str = ""
    quantity: float = 1.0
    unit_cost: Optional[float] = None
    heat_lot: str = ""
    # Optional material hints for matcher
    grade: str = ""
    form: str = ""
    size_label: str = ""
    unit: str = "ea"


@dataclass
class ParsedEmail:
    email_type: str
    order_reference: str = ""
    invoice: str = ""
    tracking: str = ""
    currency: str = "USD"
    purchase_date: Optional[str] = None  # YYYY-MM-DD
    total: Optional[float] = None
    notes: str = ""
    customer_po: str = ""  # e.g. McMaster "Purchase Order" / job ref 1013ASOLANKI
    lines: list[ParsedLine] = field(default_factory=list)
    # Attachment filenames that look like mill certs / invoices (matched later)
    attachment_roles: dict[str, str] = field(default_factory=dict)
    parse_notes: str = ""
    ok: bool = True
    error: str = ""


@dataclass
class EmailMessage:
    """Normalized Gmail message passed to adapters."""

    gmail_message_id: str
    gmail_thread_id: str = ""
    from_address: str = ""
    subject: str = ""
    received_at: Optional[str] = None
    body_text: str = ""
    body_html: str = ""
    # list of {filename, mime_type, data: bytes}
    attachments: list[dict[str, Any]] = field(default_factory=list)


class VendorAdapter(Protocol):
    vendor_key: str
    display_name: str
    default_domains: list[str]

    def detect(self, message: EmailMessage, domains: list[str]) -> bool:
        """True if this message belongs to the vendor."""

    def classify(self, message: EmailMessage) -> str:
        """Return one of EMAIL_TYPES."""

    def parse(self, message: EmailMessage) -> ParsedEmail:
        """Extract structured purchase data."""

    def correlate_key(self, parsed: ParsedEmail, message: EmailMessage) -> str:
        """Stable order key for merging emails onto one draft."""


def from_domain_matches(from_address: str, domains: list[str]) -> bool:
    addr = (from_address or "").lower()
    for d in domains:
        d = d.strip().lower()
        if not d:
            continue
        if d in addr:
            return True
    return False


def strip_html_to_text(html: str) -> str:
    if not html:
        return ""
    try:
        from bs4 import BeautifulSoup

        soup = BeautifulSoup(html, "html.parser")
        for tag in soup(["script", "style"]):
            tag.decompose()
        text = soup.get_text("\n")
        lines = [ln.strip() for ln in text.splitlines()]
        return "\n".join(ln for ln in lines if ln)
    except Exception:
        return html
