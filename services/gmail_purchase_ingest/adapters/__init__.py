from .base import EmailMessage, ParsedEmail, ParsedLine, VendorAdapter
from .dgi_supply import ADAPTER as DGI_ADAPTER
from .mcmaster import ADAPTER as MCMASTER_ADAPTER

ALL_ADAPTERS = {
    MCMASTER_ADAPTER.vendor_key: MCMASTER_ADAPTER,
    DGI_ADAPTER.vendor_key: DGI_ADAPTER,
}

__all__ = [
    "ALL_ADAPTERS",
    "EmailMessage",
    "ParsedEmail",
    "ParsedLine",
    "VendorAdapter",
    "MCMASTER_ADAPTER",
    "DGI_ADAPTER",
]
