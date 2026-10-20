import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from adapters.base import EmailMessage
from adapters.dgi_supply import DgiSupplyAdapter
from matchers.tools import match_tool_line, part_candidates


# Clean-ish extract (happy path)
CONF_PDF = """
DGI Supply Canada
Order Number 1653184
Order Date 10/15/2026 12:58:01
PO Number AMISH
Carrier SHIPPED DIRECT

HVT989816C4 .250 BALL V-HELIX NF 3X LOC 3 FL DMD
989816-C4
1.00 EA 112.1800 112.18

HVT68320 .020 R X 3/16 D FULL RAD KEYSEAT CUTTER 68320
1.00 EA 189.5300 189.53

SUB-TOTAL 301.71
TAX 15.09
AMOUNT DUE 316.80
"""

# Real pypdf-ish column scramble (from live review UI)
SCRAMBLED_CONF = """
DGI Supply Canada
Order
Number
1653184
Order Date 10/15/2026
PO Number AMISH
CHO
SHIPPED DIRECT
112.1800EAEA1.00 112.18R 1.0 1.0.250 BALL V-HELIX NF 3X LOC 3 FL DMD
.250 BALL V-HELIX NF 3X LOC 3 FLUTE ENDMILL DMD 989816-C4 HVT989816C41
189.5300EAEA1.00 189.53R 1.0 1.0.020 R X 3/16 D FULL RAD KEYSEAT
.020 R X 3/16 D FULL RAD KEYSEAT CUTTER 68320 HVT683201
SUB-TOTAL 301.71
TAX 15.09
AMOUNT DUE 316.80
"""

SCRAMBLED_INVOICE = """
DGI Supply Canada
Invoice Number 3525554
Invoice Date 10/15/2026
Order Number 1653184
PO Number AMISH Net 30 11/14/2026
EA 112.1800 112.18 1.0 1.0 1.00 .250 BALL V-HELIX NF 3X LOC 3 FL DMD
1.00 EA HVT68320 EA 189.5300 189.53 1.0 1.0 1.00 .020 R X 3/16 D FULL RAD KEYSEAT
SUB-TOTAL:Total Lines: 2 301 HVT989816C4
EA 189.5300 189.53 Total Freight Out: 34.95 0.00 34.95
Canada GST 5% - (REG#: R885680330): 16.84 HVT68320
AMOUNT DUE 353.50
"""


def test_classify_cliff_vs_ar():
    a = DgiSupplyAdapter()
    conf = EmailMessage("1", from_address="cho@dgisupply.ca", subject="Harvey Tool order")
    inv = EmailMessage("2", from_address="ar_canada@dgisupply.ca", subject="Invoice 3525554")
    assert a.classify(conf) == "order_confirmation"
    assert a.classify(inv) == "invoice"


def test_confirmation_clean():
    a = DgiSupplyAdapter()
    orig = DgiSupplyAdapter._pdf_bytes_to_text
    DgiSupplyAdapter._pdf_bytes_to_text = staticmethod(lambda _d: CONF_PDF)
    try:
        msg = EmailMessage(
            "c",
            from_address="cho@dgisupply.ca",
            subject="Harvey tools",
            attachments=[{"filename": "c.pdf", "data": b"%PDF", "mime_type": "application/pdf"}],
        )
        p = a.parse(msg)
        assert p.order_reference == "1653184"
        assert p.currency == "CAD"
        assert p.customer_po == "AMISH"
        assert a.correlate_key(p, msg) == "1653184"
        assert not a.correlate_key(p, msg).startswith("19f")  # not gmail id
        by = {l.part_number: l for l in p.lines if l.line_type == "item"}
        assert by["HVT989816C4"].unit_cost == 112.18
        assert by["HVT68320"].unit_cost == 189.53
        tax = next(l for l in p.lines if l.line_type == "tax")
        assert tax.unit_cost == 15.09
    finally:
        DgiSupplyAdapter._pdf_bytes_to_text = orig


def test_scrambled_conf_strips_glued_digit_and_finds_order():
    a = DgiSupplyAdapter()
    orig = DgiSupplyAdapter._pdf_bytes_to_text
    DgiSupplyAdapter._pdf_bytes_to_text = staticmethod(lambda _d: SCRAMBLED_CONF)
    try:
        msg = EmailMessage(
            "c2",
            from_address="cho@dgisupply.ca",
            subject="order",
            attachments=[{"filename": "c.pdf", "data": b"%PDF", "mime_type": "application/pdf"}],
        )
        p = a.parse(msg)
        assert p.order_reference == "1653184"
        assert a.correlate_key(p, msg) == "1653184"
        by = {l.part_number: l for l in p.lines if l.line_type == "item"}
        assert "HVT989816C4" in by
        assert "HVT68320" in by
        assert "HVT989816C41" not in by
        assert "HVT683201" not in by
        assert by["HVT989816C4"].unit_cost == 112.18
        assert by["HVT68320"].unit_cost == 189.53
        assert "SUB-TOTAL" not in (by["HVT989816C4"].description or "").upper()
    finally:
        DgiSupplyAdapter._pdf_bytes_to_text = orig


def test_scrambled_invoice_freight_gst_not_amount_due():
    a = DgiSupplyAdapter()
    orig = DgiSupplyAdapter._pdf_bytes_to_text
    DgiSupplyAdapter._pdf_bytes_to_text = staticmethod(lambda _d: SCRAMBLED_INVOICE)
    try:
        msg = EmailMessage(
            "i",
            from_address="ar_canada@dgisupply.ca",
            subject="Invoice",
            attachments=[{"filename": "inv.pdf", "data": b"%PDF", "mime_type": "application/pdf"}],
        )
        p = a.parse(msg)
        assert p.order_reference == "1653184"
        assert p.invoice == "3525554"
        assert p.order_reference != p.invoice
        assert p.total == 353.50
        assert p.customer_po == "AMISH"
        ships = [l for l in p.lines if l.line_type == "shipping"]
        taxes = [l for l in p.lines if l.line_type == "tax"]
        assert len(ships) == 1 and ships[0].unit_cost == 34.95
        assert len(taxes) == 1 and taxes[0].unit_cost == 16.84
        assert taxes[0].unit_cost != 353.50
        by = {l.part_number: l for l in p.lines if l.line_type == "item"}
        assert by["HVT989816C4"].unit_cost == 112.18
        assert by["HVT68320"].unit_cost == 189.53
        # Descriptions must not cross-contaminate
        d4 = (by["HVT989816C4"].description or "").upper()
        d20 = (by["HVT68320"].description or "").upper()
        assert "BALL" in d4 or "989816" in d4
        assert "KEYSEAT" in d20 or "68320" in d20
        assert "989816" not in d20
    finally:
        DgiSupplyAdapter._pdf_bytes_to_text = orig


def test_invoice_filename_not_used_as_order_ref():
    """Inv_3525554.pdf must not become order_reference when Order Number is absent."""
    a = DgiSupplyAdapter()
    pdf = """
DGI Supply Canada
Invoice Number 3525554
Invoice Date 10/15/2026
PO Number AMISH
EA 112.1800 112.18 .250 BALL V-HELIX NF 3X LOC 3 FL DMD HVT989816C4
1.00 EA HVT68320 EA 189.5300 189.53 .020 R X 3/16 D FULL RAD KEYSEAT CUTTER 68320
Total Freight Out: 34.95
AMOUNT DUE 353.50
"""
    orig = DgiSupplyAdapter._pdf_bytes_to_text
    DgiSupplyAdapter._pdf_bytes_to_text = staticmethod(lambda _d: pdf)
    try:
        msg = EmailMessage(
            "i2",
            from_address="ar_canada@dgisupply.ca",
            subject="Invoice 3525554",
            attachments=[
                {
                    "filename": "Inv_3525554.pdf",
                    "data": b"%PDF",
                    "mime_type": "application/pdf",
                }
            ],
        )
        p = a.parse(msg)
        assert p.invoice == "3525554"
        assert p.order_reference != "3525554"
        assert a.correlate_key(p, msg) != "3525554"
        taxes = [l for l in p.lines if l.line_type == "tax"]
        assert len(taxes) == 1 and abs(taxes[0].unit_cost - 16.84) < 0.02
        by = {l.part_number: l for l in p.lines if l.line_type == "item"}
        assert "BALL" in (by["HVT989816C4"].description or "").upper()
        assert "KEYSEAT" in (by["HVT68320"].description or "").upper()
        assert "BALL" not in (by["HVT68320"].description or "").upper()
    finally:
        DgiSupplyAdapter._pdf_bytes_to_text = orig


def test_live_ui_style_invoice_keeps_order_not_invoice_ref():
    """Matches the review UI: order 1653184, invoice 3525554, GST, no crossed descs."""
    a = DgiSupplyAdapter()
    # Order Number present; filename is invoice digits only
    pdf = SCRAMBLED_INVOICE
    orig = DgiSupplyAdapter._pdf_bytes_to_text
    DgiSupplyAdapter._pdf_bytes_to_text = staticmethod(lambda _d: pdf)
    try:
        msg = EmailMessage(
            "live",
            from_address="ar_canada@dgisupply.ca",
            subject="Invoice 3525554",
            attachments=[
                {
                    "filename": "3525554.pdf",
                    "data": b"%PDF",
                    "mime_type": "application/pdf",
                }
            ],
        )
        p = a.parse(msg)
        assert p.order_reference == "1653184"
        assert p.invoice == "3525554"
        assert a.correlate_key(p, msg) == "1653184"
        by = {l.part_number: l for l in p.lines if l.line_type == "item"}
        assert by["HVT989816C4"].unit_cost == 112.18
        assert by["HVT68320"].unit_cost == 189.53
        assert "BALL" in (by["HVT989816C4"].description or "").upper()
        assert "KEYSEAT" in (by["HVT68320"].description or "").upper()
        taxes = [l for l in p.lines if l.line_type == "tax"]
        assert taxes and abs(taxes[0].unit_cost - 16.84) < 0.02
    finally:
        DgiSupplyAdapter._pdf_bytes_to_text = orig


def test_correlate_parts_fallback_not_gmail_id():
    a = DgiSupplyAdapter()
    msg = EmailMessage("19f3e545c60a8114", from_address="cho@dgisupply.ca", subject="x")
    # No PDF — empty parse
    p = a.parse(msg)
    key = a.correlate_key(p, msg)
    assert key == "" or key.startswith("DGI-")
    assert key != "19f3e545c60a8114"


def test_tool_match():
    tools = [
        {"id": "t1", "tool_name": "Ball", "model_number": "989816-C4"},
        {"id": "t2", "tool_name": "Keyseat", "model_number": "68320"},
    ]
    hit = match_tool_line(
        tools=tools, part_number="HVT989816C4", description="989816-C4", line_type="item"
    )
    assert hit.status == "matched" and hit.matched_tool_id == "t1"
    assert "989816" in part_candidates("HVT989816C4", "989816-C4")


if __name__ == "__main__":
    test_classify_cliff_vs_ar()
    test_confirmation_clean()
    test_scrambled_conf_strips_glued_digit_and_finds_order()
    test_scrambled_invoice_freight_gst_not_amount_due()
    test_invoice_filename_not_used_as_order_ref()
    test_live_ui_style_invoice_keeps_order_not_invoice_ref()
    test_correlate_parts_fallback_not_gmail_id()
    test_tool_match()
    print("ok")
