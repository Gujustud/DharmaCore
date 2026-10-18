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
            "We shipped the plastic and steel on your October 13th order.\n"
            "McMaster-Carr number 7110963\n"
            "Tracking number: 123456789012\n"
        ),
        received_at="2026-10-14T12:00:00+00:00",
        attachments=[{"filename": "Certificate for 7110963.pdf", "data": b"%PDF", "mime_type": "application/pdf"}],
    )
    receipt = EmailMessage(
        "r",
        from_address="sales@mcmaster.com",
        subject="Receipt for Your October 13th Order with McMaster-Carr",
        body_text="Receipt\nMcMaster-Carr number 7110963\nTracking number: 123456789012\n",
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
    assert p_cert.tracking
    assert p_cert.attachment_roles.get("Certificate for 7110963.pdf") == "mill_cert"
    assert p_rcpt.email_type == "invoice"


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
    test_parse_lines_and_order()
    test_material_matcher_propose_and_match()
    print("ok")
