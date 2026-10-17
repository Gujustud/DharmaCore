"""DGI Supply adapter stub — detect by domain; parse returns needs-parser draft."""

from __future__ import annotations

from .base import EmailMessage, ParsedEmail, from_domain_matches

DEFAULT_DOMAINS = ["dgisupply.com"]


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
        if "invoice" in subject:
            return "invoice"
        if any(k in subject for k in ("ship", "tracking")):
            return "shipping"
        if "order" in subject or "confirm" in subject:
            return "order_confirmation"
        return "other"

    def correlate_key(self, parsed: ParsedEmail, message: EmailMessage) -> str:
        if parsed.order_reference:
            return parsed.order_reference.strip().upper()
        return (message.gmail_thread_id or message.gmail_message_id or "").strip()

    def parse(self, message: EmailMessage) -> ParsedEmail:
        email_type = self.classify(message)
        return ParsedEmail(
            email_type=email_type,
            currency="CAD",
            notes="DGI Supply adapter is a stub — fill in parser later.",
            parse_notes="needs_parser",
            ok=True,
            lines=[],
        )


ADAPTER = DgiSupplyAdapter()
