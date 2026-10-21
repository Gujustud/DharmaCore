import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from adapters.base import EmailMessage
from adapters.mcmaster import McMasterAdapter
from matchers.materials import match_material_line


def test_classify_real_subject_lines():
    a = McMasterAdapter()
    conf = EmailMessage(
        "1",
        from_address="orders@mcmaster.com",
        subject="Confirmation for Your October 13th Order with McMaster-Carr",
    )
    cert = EmailMessage(
        "2",
        from_address="orders@mcmaster.com",
        subject="Certificate and Tracking for Your October 13th Order with McMaster-Carr",
    )
    receipt = EmailMessage(
        "3",
        from_address="sales@mcmaster.com",
        subject="Receipt for Your October 13th Order with McMaster-Carr",
    )
    assert a.classify(conf) == "order_confirmation"
    assert a.classify(cert) == "certificate"
    assert a.classify(receipt) == "invoice"


def test_does_not_use_for_as_order_ref():
    """Regression: 'Confirmation for Your…' used to become Ref: FOR."""
    a = McMasterAdapter()
    msg = EmailMessage(
        "1",
        from_address="orders@mcmaster.com",
        subject="Confirmation for Your October 13th Order with McMaster-Carr",
        body_text=(
            "Amish Solanki McMaster-Carr number 7110963 1013ASOLANKI "
            "Delivers Oct 15, 9-11 am\n"
            "1 White Delrin Acetal Resin Bar 8575K11 1 $50.00\n"
            "Order Total: $198.25\n"
        ),
        received_at="2026-10-13T12:00:00+00:00",
    )
    parsed = a.parse(msg)
    assert parsed.order_reference == "7110963"
    assert a.correlate_key(parsed, msg) == "7110963"
    assert "1013ASOLANKI" in (parsed.notes or "")
    assert parsed.total == 198.25
    assert parsed.email_type == "order_confirmation"


def test_cert_and_receipt_share_correlate_key():
    a = McMasterAdapter()
    conf_body = "McMaster-Carr number 7110963 1013ASOLANKI\nOrder Total: $198.25\n"
    cert = EmailMessage(
        "c",
        from_address="orders@mcmaster.com",
        subject="Certificate and Tracking for Your October 13th Order with McMaster-Carr",
        body_text=(
            "We shipped the plastic and steel on your October 13th order. "
            "You will receive them tomorrow. "
            "Track your shipment using Purolator CPK004315941.\n"
            "McMaster-Carr number 7110963\n"
            "The certificate for the steel is attached.\n"
        ),
        received_at="2026-10-14T12:00:00+00:00",
        attachments=[{"filename": "Certificate for 7110963.pdf", "data": b"%PDF", "mime_type": "application/pdf"}],
    )
    receipt = EmailMessage(
        "r",
        from_address="sales@mcmaster.com",
        subject="Receipt for Your October 13th Order with McMaster-Carr",
        body_text="Receipt\nMcMaster-Carr number 7110963\nTrack your shipment using Purolator CPK004315941.\n",
        received_at="2026-10-15T12:00:00+00:00",
    )
    conf = EmailMessage(
        "o",
        from_address="orders@mcmaster.com",
        subject="Confirmation for Your October 13th Order with McMaster-Carr",
        body_text=conf_body,
        received_at="2026-10-13T12:00:00+00:00",
    )
    p_conf = a.parse(conf)
    p_cert = a.parse(cert)
    p_rcpt = a.parse(receipt)
    assert a.correlate_key(p_conf, conf) == a.correlate_key(p_cert, cert) == a.correlate_key(p_rcpt, receipt)
    assert p_cert.email_type == "certificate"
    assert p_cert.tracking == "CPK004315941"
    assert p_cert.tracking != "7110963"
    assert p_cert.attachment_roles.get("Certificate for 7110963.pdf") == "mill_cert"
    assert p_rcpt.email_type == "invoice"


def test_tracking_href_from_html_link():
    a = McMasterAdapter()
    html = (
        '<p>Track your shipment using Purolator '
        '<a href="https://www.purolator.com/en/shipping/tracker?pin=CPK004315941">'
        "CPK004315941</a>.</p>"
        "<p>McMaster-Carr number 7110963</p>"
    )
    msg = EmailMessage(
        "h",
        from_address="orders@mcmaster.com",
        subject="Certificate and Tracking for Your October 13th Order with McMaster-Carr",
        body_html=html,
        body_text="Track your shipment using Purolator CPK004315941.",
    )
    parsed = a.parse(msg)
    assert "purolator.com" in parsed.tracking.lower()
    assert "CPK004315941" in parsed.tracking


def test_tracking_is_not_mcmaster_order_number():
    a = McMasterAdapter()
    msg = EmailMessage(
        "x",
        from_address="orders@mcmaster.com",
        subject="Certificate and Tracking for Your October 13th Order with McMaster-Carr",
        body_text=(
            "Track your shipment.\n"
            "McMaster-Carr number 7110963\n"
            "We shipped the plastic and steel.\n"
        ),
    )
    parsed = a.parse(msg)
    assert parsed.order_reference == "7110963"
    assert parsed.tracking == ""  # no real PIN present — don't fake it


def test_cert_pdf_header_order_number_strips_suffix():
    """Cert PDF shows 'McMaster-Carr Number 7110963-01'; correlate on 7110963."""
    a = McMasterAdapter()
    pdf_header = (
        "McMASTER-CARR\n"
        "Purchase Order 1013ASOLANKI\n"
        "Order Date 10/13/2026\n"
        "Placed By Amish Solanki\n"
        "McMaster-Carr Number 7110963-01\n"
        "Number of Certificates 1\n"
        "Line 2 Product 8910K54 Low-Carbon Steel Bar\n"
    )
    orig = McMasterAdapter._pdf_bytes_to_text
    McMasterAdapter._pdf_bytes_to_text = staticmethod(lambda _data: pdf_header)
    try:
        # Body intentionally has NO order number — only subject day phrase (old MC-DAY path)
        msg = EmailMessage(
            "cert-pdf",
            from_address="orders@mcmaster.com",
            subject="Certificate and Tracking for Your October 13th Order with McMaster-Carr",
            body_text=(
                "We shipped the plastic and steel on your October 13th order. "
                "Track your shipment using Purolator CPK004315941. "
                "The certificate for the steel is attached."
            ),
            received_at="2026-10-14T12:00:00+00:00",
            attachments=[
                {
                    "filename": "Certificate.pdf",
                    "data": b"%PDF-1.4 fake",
                    "mime_type": "application/pdf",
                }
            ],
        )
        parsed = a.parse(msg)
        assert parsed.order_reference == "7110963"
        assert a.correlate_key(parsed, msg) == "7110963"
        assert "1013ASOLANKI" in (parsed.notes or "")
        assert "7110963-01" in (parsed.notes or "")
        assert parsed.purchase_date == "2026-10-13"
        assert parsed.tracking == "CPK004315941"
        assert not parsed.order_reference.startswith("MC-DAY-")
    finally:
        McMasterAdapter._pdf_bytes_to_text = orig


def test_find_order_normalizes_suffix_in_body():
    a = McMasterAdapter()
    base, suffix = a._find_order("McMaster-Carr Number: 7110963-01", "")
    assert base == "7110963"
    assert suffix == "01"


def test_unicode_hyphen_mcmaster_number_and_suffix():
    """Cert/invoice PDFs use U+2212 minus: McMaster−Carr Number 7110963 − 01."""
    a = McMasterAdapter()
    blob = (
        "McMaster\u2212Carr Number: 7110963 \u2212 01\n"
        "Purchase Order 1013ASOLANKI\n"
        "Invoice Number: 73569330\n"
    )
    base, suffix = a._find_order(blob, "")
    assert base == "7110963"
    assert suffix == "01"
    assert a._find_customer_po(blob, "") == "1013ASOLANKI"


def test_does_not_treat_invoice_number_as_order():
    """Regression: loose order…number matched Invoice Number 73569330."""
    a = McMasterAdapter()
    body = (
        "Certificate and Tracking for Your October 13th Order with McMaster-Carr.\n"
        "We shipped the plastic and steel.\n"
        "Invoice Number: 73569330\n"
        "Invoice Date: 10/14/2026\n"
        "Track your shipment using Purolator CPK004315941.\n"
    )
    msg = EmailMessage(
        "inv-trap",
        from_address="orders@mcmaster.com",
        subject="Certificate and Tracking for Your October 13th Order with McMaster-Carr",
        body_text=body,
        received_at="2026-10-14T12:00:00+00:00",
    )
    # Without PDF McMaster number, fall back to day key — never invoice #
    pdf_header = (
        "McMaster\u2212Carr Number 7110963 \u2212 01\n"
        "Purchase Order 1013ASOLANKI\n"
        "Order Date 10/13/2026\n"
        "Invoice Number: 73569330\n"
    )
    orig = McMasterAdapter._pdf_bytes_to_text
    McMasterAdapter._pdf_bytes_to_text = staticmethod(lambda _data: pdf_header)
    try:
        msg.attachments = [
            {"filename": "Certificate.pdf", "data": b"%PDF-1.4", "mime_type": "application/pdf"}
        ]
        parsed = a.parse(msg)
        assert parsed.order_reference == "7110963"
        assert parsed.order_reference != "73569330"
        assert "Customer ref: ORDER" not in (parsed.notes or "")
        assert "1013ASOLANKI" in (parsed.notes or "")
    finally:
        McMasterAdapter._pdf_bytes_to_text = orig


def test_purchase_order_label_skips_order_date_header():
    a = McMasterAdapter()
    # Column headers smashed together by PDF extract
    blob = "Purchase Order Order Date Placed By\n1013ASOLANKI 10/13/2026 Amish"
    # Label regex requires a digit in the captured token — "Order" alone is rejected
    assert a._find_customer_po(blob, "") == "1013ASOLANKI"


def test_customer_po_is_not_a_line_item():
    a = McMasterAdapter()
    body = (
        "McMaster-Carr number 7110963 1013ASOLANKI\n"
        "Delivers Oct 15, 9-11 am\n"
        "1013ASOLANKI something\n"
        "8741K53 White Delrin Acetal Resin Bar 1 $50.00\n"
        "Order Total: $198.25\n"
    )
    msg = EmailMessage(
        "po-part",
        from_address="orders@mcmaster.com",
        subject="Confirmation for Your October 13th Order with McMaster-Carr",
        body_text=body,
    )
    parsed = a.parse(msg)
    parts = [l.part_number for l in parsed.lines]
    assert "1013ASOLANKI" not in parts
    assert any(p.startswith("8741") for p in parts)


def test_invoice_number_never_becomes_order_ref_even_near_mcmaster():
    """Multiline 'McMaster-Carr … Number: 73569330' must not win over real order #."""
    a = McMasterAdapter()
    # Old buggy pattern: McMaster-Carr then many lines then a Number: invoice
    blob = (
        "McMaster-Carr Supply Company\n"
        "cle.sales@mcmaster.com\n"
        "Purchase Order 1013ASOLANKI\n"
        "Invoice Number: 73569330\n"
        "Order Date 10/13/2026\n"
        "McMaster-Carr Number 7110963-01\n"
    )
    base, suffix = a._find_order(blob, "")
    assert base == "7110963"
    assert suffix == "01"


def test_prefer_merge_keeps_order_over_invoice_ref():
    from pb_client import prefer_merge_draft

    keeper = prefer_merge_draft(
        [
            {"id": "inv", "order_reference": "73569330", "total": 0, "notes": "Customer ref: 1013ASOLANKI"},
            {"id": "ord", "order_reference": "7110963", "total": 198.25, "notes": "Customer ref: 1013ASOLANKI", "tracking": "CPK004315941"},
        ],
        incoming_ref="7110963",
    )
    assert keeper is not None
    assert keeper["id"] == "ord"


def test_parse_lines_and_order():
    a = McMasterAdapter()
    body = """
    Order Number: 9876543
    Order Total: $125.50

    8975K123 Aluminum 6061-T6 Round Bar 1" dia x 3 ft  2  $45.00
    9287T11 Socket Head Cap Screw  10  $1.20
    """
    msg = EmailMessage(
        gmail_message_id="2",
        from_address="noreply@mcmaster.com",
        subject="McMaster-Carr Order Confirmation",
        body_text=body,
    )
    parsed = a.parse(msg)
    assert parsed.order_reference == "9876543"
    assert parsed.total == 125.50
    assert parsed.currency == "USD"
    assert len(parsed.lines) >= 1
    mat = next(l for l in parsed.lines if l.part_number.startswith("8975"))
    assert mat.line_type == "material"
    assert "6061" in mat.grade.upper()


def test_explicit_shipping_line_from_receipt():
    a = McMasterAdapter()
    body = (
        "Receipt for Your October 13th Order with McMaster-Carr\n"
        "McMaster-Carr number 7110963\n"
        "Merchandise $159.33\n"
        "Shipping $38.92\n"
        "Order Total: $198.25\n"
    )
    msg = EmailMessage(
        "ship-explicit",
        from_address="sales@mcmaster.com",
        subject="Receipt for Your October 13th Order with McMaster-Carr",
        body_text=body,
    )
    parsed = a.parse(msg)
    ships = [l for l in parsed.lines if l.line_type == "shipping"]
    assert len(ships) == 1
    assert ships[0].unit_cost == 38.92
    assert ships[0].description == "Shipping"


def test_receipt_pdf_packing_list_gst_shipping_clean_lines():
    """Real receipt layout: Packing List order #, GST/HST, Shipping, clean P/N grid."""
    a = McMasterAdapter()
    pdf_text = """
    McMASTER-CARR
    330-995-5500 330-995-9600 (fax) cle.sales@mcmaster.com
    Receipt
    Billed to ATTENTION: AMISH SOLANKI S S CADCAM INC
    Purchase Order 1013ASOLANKI
    Paid (US Dollars) $198.25
    Invoice 73569330 Invoice Date 10/14/26
    Shipped to S S Cadcam Inc Squamish BC
    Your Account 375541600
    Amish Solanki placed this order.

    8741K53
    White Delrin Acetal Resin Bar Oversized Tolerance
    3" Thick, 3" Wide, 1 ft. Length
    1 1
    113.92 Each
    113.92

    8910K54
    Low-Carbon Steel Bar
    1" Thick, 2-1/2" Wide, 1 Foot Long
    1 1
    45.41 Each
    45.41

    Packing List 7110963-01
    Shipped Date 10/14/26
    Carrier Purolator
    Tracking CPK004315941

    Merchandise
    159.33
    Canadian GST/HST
    9.44
    Shipping
    29.48
    Total (US Dollars)
    $198.25
    """
    orig = McMasterAdapter._pdf_bytes_to_text
    McMasterAdapter._pdf_bytes_to_text = staticmethod(lambda _data: pdf_text)
    try:
        # Body intentionally has a wrong "order number" that used to win as Ref
        msg = EmailMessage(
            "receipt-pdf",
            from_address="sales@mcmaster.com",
            subject="Receipt for Your October 13th Order with McMaster-Carr",
            body_text=(
                "Receipt\nOrder Number: 18678242\n"
                "330-995-5500 cle.sales@mcmaster.com "
                "Billed to ATTENTION: AMISH SOLANKI "
                "8741K53 1 each 113.92 each $113.92\n"
            ),
            received_at="2026-10-15T12:00:00+00:00",
            attachments=[
                {
                    "filename": "Receipt.pdf",
                    "data": b"%PDF-1.4 fake",
                    "mime_type": "application/pdf",
                }
            ],
        )
        parsed = a.parse(msg)
        assert parsed.order_reference == "7110963"
        assert parsed.order_reference != "18678242"
        assert parsed.invoice == "73569330"
        assert parsed.total == 198.25
        by_pn = {l.part_number.upper(): l for l in parsed.lines if l.part_number}
        assert "8741K53" in by_pn and "8910K54" in by_pn
        d = by_pn["8741K53"]
        assert "Delrin" in d.description
        assert "Billed to" not in d.description
        assert "cle.sales" not in d.description
        assert d.unit_cost == 113.92
        assert by_pn["8910K54"].grade == "1018"
        ships = [l for l in parsed.lines if l.line_type == "shipping"]
        taxes = [l for l in parsed.lines if l.line_type == "tax"]
        assert len(ships) == 1 and ships[0].unit_cost == 29.48
        assert len(taxes) == 1 and taxes[0].unit_cost == 9.44
        assert taxes[0].description == "GST/HST"
        # Footer math: 159.33 + 9.44 + 29.48 = 198.25
        assert abs(159.33 + 9.44 + 29.48 - 198.25) < 0.01
    finally:
        McMasterAdapter._pdf_bytes_to_text = orig


def test_packing_list_preferred_over_generic_order_number():
    a = McMasterAdapter()
    blob = (
        "Order Number: 18678242\n"
        "Invoice Number: 73569330\n"
        "Packing List 7110963-01\n"
    )
    base, suffix = a._find_order(blob, "")
    assert base == "7110963"
    assert suffix == "01"


def test_shipping_inferred_from_total_minus_line_items():
    """Confirmation often has Order Total but no Shipping row — infer remainder."""
    a = McMasterAdapter()
    body = """
    Confirmation for Your October 13th Order with McMaster-Carr
    McMaster-Carr number 7110963 1013ASOLANKI

    White Delrin Acetal Resin Bar Oversized Tolerance
    3" Thick, 3" Wide, 1 ft. Length
    8741K53
    1 each
    113.92 each
    $113.92

    Low-Carbon Steel Bar
    1" Thick, 2-1/2" Wide, 1 Foot Long
    8910K54
    1 each
    45.41 each
    $45.41

    Order Total: $198.25
    """
    msg = EmailMessage(
        "ship-infer",
        from_address="orders@mcmaster.com",
        subject="Confirmation for Your October 13th Order with McMaster-Carr",
        body_text=body,
    )
    parsed = a.parse(msg)
    ships = [l for l in parsed.lines if l.line_type == "shipping"]
    assert len(ships) == 1
    assert ships[0].unit_cost == 38.92


def test_merchandise_order_total_is_not_merchandise_subtotal():
    a = McMasterAdapter()
    # Must not treat "Merchandise Order Total: $198.25" as merchandise=$198.25
    assert a._find_shipping_amount(
        "Merchandise Order Total: $198.25",
        lines=[],
        total=198.25,
    ) is None
    assert (
        a._find_shipping_amount(
            "Merchandise $159.33\nOrder Total: $198.25",
            lines=[],
            total=198.25,
        )
        == 38.92
    )


def test_material_matcher_propose_and_match():
    materials = [
        {"id": "m1", "grade": "6061-T6", "form": "bar", "size_label": '1" dia x 3 ft'},
        {"id": "m2", "grade": "4140", "form": "plate", "size_label": "0.5 x 4 x 12"},
    ]
    hit = match_material_line(
        materials=materials,
        grade="6061-T6",
        form="bar",
        size_label='1" dia x 3 ft',
        line_type="material",
    )
    assert hit.status == "matched"
    assert hit.matched_material_id == "m1"

    miss = match_material_line(
        materials=materials,
        grade="7075-T6",
        form="plate",
        size_label="1 x 12 x 12",
        line_type="material",
    )
    assert miss.status == "propose_new"
    assert miss.proposed is not None


if __name__ == "__main__":
    test_classify_real_subject_lines()
    test_does_not_use_for_as_order_ref()
    test_cert_and_receipt_share_correlate_key()
    test_tracking_href_from_html_link()
    test_tracking_is_not_mcmaster_order_number()
    test_cert_pdf_header_order_number_strips_suffix()
    test_find_order_normalizes_suffix_in_body()
    test_parse_lines_and_order()
    test_material_matcher_propose_and_match()
    print("ok")
