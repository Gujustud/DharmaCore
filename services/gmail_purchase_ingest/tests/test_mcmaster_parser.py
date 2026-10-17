import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from adapters.base import EmailMessage
from adapters.mcmaster import McMasterAdapter
from matchers.materials import match_material_line


def test_classify_order_confirmation():
    a = McMasterAdapter()
    msg = EmailMessage(
        gmail_message_id="1",
        from_address="orders@mcmaster.com",
        subject="McMaster-Carr Order Confirmation 1234567",
        body_text="Thanks for your order",
    )
    assert a.classify(msg) == "order_confirmation"
    assert a.detect(msg, a.default_domains)


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
    test_classify_order_confirmation()
    test_parse_lines_and_order()
    test_material_matcher_propose_and_match()
    print("ok")
