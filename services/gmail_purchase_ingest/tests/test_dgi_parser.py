import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from adapters.base import EmailMessage
from adapters.dgi_supply import DgiSupplyAdapter
from matchers.tools import match_tool_line, part_candidates


CONF_PDF = """
DGI Supply Canada
Order Number 1653184
Order Date 10/15/2026 12:58:01
PO Number AMISH
Carrier SHIPPED DIRECT
Customer Service Rep CHO

HVT989816C4 .250 BALL V-HELIX NF 3X LOC 3 FL DMD
.250 BALL V-HELIX NF 3X LOC 3 FLUTE ENDMILL DMD 989816-C4
Expected Delivery Date 10/16/2026
1.00 EA 112.1800 112.18

HVT68320 .020 R X 3/16 D FULL RAD KEYSEAT
.020 R X 3/16 D FULL RAD KEYSEAT CUTTER 68320
Expected Delivery Date 10/16/2026
1.00 EA 189.5300 189.53

Total Lines 2
SUB-TOTAL 301.71
TAX 15.09
AMOUNT DUE 316.80
CAD$
"""

INVOICE_PDF = """
DGI Supply Canada
Invoice Number 3525554
Invoice Date 10/15/2026
Order Number 1653184
DIRECT SHIPMENT
PO Number AMISH

HVT989816C4 .250 BALL V-HELIX NF 3X LOC 3 FL DMD
1.00 1.00 EA 112.1800 112.18

HVT68320 .020 R X 3/16 D FULL RAD KEYSEAT
1.00 1.00 EA 189.5300 189.53

Total Freight Out 34.95
Sub-total 301.71
Total Freight 34.95
Tax Canada GST 5% - (REG#: R885680330): 16.84
AMOUNT DUE 353.50
CAD$
"""


def test_classify_cliff_vs_ar():
    a = DgiSupplyAdapter()
    conf = EmailMessage(
        "1",
        from_address="cho@dgisupply.ca",
        subject="Harvey Tool order",
    )
    inv = EmailMessage(
        "2",
        from_address="ar_canada@dgisupply.ca",
        subject="Invoice 3525554",
    )
    assert a.classify(conf) == "order_confirmation"
    assert a.classify(inv) == "invoice"


def test_confirmation_parse_order_lines_tax():
    a = DgiSupplyAdapter()
    orig = DgiSupplyAdapter._pdf_bytes_to_text
    DgiSupplyAdapter._pdf_bytes_to_text = staticmethod(lambda _d: CONF_PDF)
    try:
        msg = EmailMessage(
            "c",
            from_address="cho@dgisupply.ca",
            subject="Harvey tools confirmation",
            body_text="Please see attached confirmation.",
            attachments=[
                {"filename": "confirm.pdf", "data": b"%PDF-1.4", "mime_type": "application/pdf"}
            ],
        )
        parsed = a.parse(msg)
        assert parsed.order_reference == "1653184"
        assert parsed.currency == "CAD"
        assert parsed.total == 316.80
        assert parsed.customer_po.upper().startswith("AMISH")
        items = [l for l in parsed.lines if l.line_type == "item"]
        assert len(items) == 2
        by = {l.part_number: l for l in items}
        assert by["HVT989816C4"].unit_cost == 112.18
        assert by["HVT68320"].unit_cost == 189.53
        taxes = [l for l in parsed.lines if l.line_type == "tax"]
        assert len(taxes) == 1 and taxes[0].unit_cost == 15.09
        assert taxes[0].description == "GST"
    finally:
        DgiSupplyAdapter._pdf_bytes_to_text = orig


def test_invoice_adds_freight_and_final_gst():
    a = DgiSupplyAdapter()
    orig = DgiSupplyAdapter._pdf_bytes_to_text
    DgiSupplyAdapter._pdf_bytes_to_text = staticmethod(lambda _d: INVOICE_PDF)
    try:
        msg = EmailMessage(
            "i",
            from_address="ar_canada@dgisupply.ca",
            subject="Your DGI Invoice",
            body_text="",
            attachments=[
                {"filename": "invoice.pdf", "data": b"%PDF-1.4", "mime_type": "application/pdf"}
            ],
        )
        parsed = a.parse(msg)
        assert parsed.order_reference == "1653184"
        assert parsed.invoice == "3525554"
        assert parsed.total == 353.50
        ships = [l for l in parsed.lines if l.line_type == "shipping"]
        taxes = [l for l in parsed.lines if l.line_type == "tax"]
        assert len(ships) == 1 and ships[0].unit_cost == 34.95
        assert len(taxes) == 1 and taxes[0].unit_cost == 16.84
        assert a.correlate_key(parsed, msg) == "1653184"
    finally:
        DgiSupplyAdapter._pdf_bytes_to_text = orig


def test_tool_part_candidates_harvey():
    c = part_candidates("HVT989816C4", "ENDMILL DMD 989816-C4")
    assert "HVT989816C4" in c
    assert "989816C4" in c or "989816-C4" in c
    assert "989816" in c


def test_tool_match_by_model():
    tools = [
        {"id": "t1", "tool_name": "Ball endmill", "model_number": "989816-C4"},
        {"id": "t2", "tool_name": "Keyseat", "model_number": "68320"},
    ]
    hit = match_tool_line(
        tools=tools,
        part_number="HVT989816C4",
        description=".250 BALL V-HELIX 989816-C4",
        line_type="item",
    )
    assert hit.status == "matched"
    assert hit.matched_tool_id == "t1"

    miss = match_tool_line(
        tools=tools,
        part_number="HVT999999",
        description="Unknown cutter",
        line_type="item",
    )
    assert miss.status == "none"


if __name__ == "__main__":
    test_classify_cliff_vs_ar()
    test_confirmation_parse_order_lines_tax()
    test_invoice_adds_freight_and_final_gst()
    test_tool_part_candidates_harvey()
    test_tool_match_by_model()
    print("ok")
