import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from adapters.mcmaster import McMasterAdapter
from adapters.base import EmailMessage


def test_confirmation_block_prices_and_flat_size():
    a = McMasterAdapter()
    body = """
    Confirmation for Your October 13th Order with McMaster-Carr
    McMaster-Carr number 7110963 1013ASOLANKI
    Delivers Oct 15, 9-11 am

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
        "1",
        from_address="orders@mcmaster.com",
        subject="Confirmation for Your October 13th Order with McMaster-Carr",
        body_text=body,
    )
    parsed = a.parse(msg)
    assert parsed.order_reference == "7110963"
    assert parsed.total == 198.25
    assert len(parsed.lines) >= 2
    by_pn = {l.part_number.upper(): l for l in parsed.lines}
    delrin = by_pn["8741K53"]
    steel = by_pn["8910K54"]
    assert delrin.unit_cost == 113.92
    assert steel.unit_cost == 45.41
    assert delrin.form == "flat"
    assert steel.form == "flat"
    assert delrin.size_label == "3x3x12"
    assert steel.size_label in ("1x2-1/2x12", "1x2.5x12")


def test_rod_not_flat():
    a = McMasterAdapter()
    line = a._line_from_desc(
        "8975K123",
        'Aluminum 6061-T6 Round Bar 1" dia x 3 ft',
        1.0,
        45.0,
    )
    assert line.form == "bar"  # catalog key for Rod
    assert line.size_label == "1x36"


def test_same_line_visual_row():
    """Prices on the same visual row as description / P/N."""
    a = McMasterAdapter()
    body = (
        "McMaster-Carr number 7110963\n"
        "White Delrin Acetal Resin Bar Oversized Tolerance 3\" Thick, 3\" Wide, "
        "1 ft. Length 8741K53 1 each 113.92 each $113.92\n"
        "Order Total: $113.92\n"
    )
    msg = EmailMessage(
        "2",
        from_address="orders@mcmaster.com",
        subject="Confirmation for Your October 13th Order with McMaster-Carr",
        body_text=body,
    )
    parsed = a.parse(msg)
    assert any(l.part_number.upper() == "8741K53" and l.unit_cost == 113.92 for l in parsed.lines)


def test_strips_payment_method_and_maps_low_carbon_to_1018():
    a = McMasterAdapter()
    body = (
        'Payment method Visa (****2022) Placed by Amish Solanki '
        "McMaster-Carr number 7110963 1013ASOLANKI Delivers Oct 15, 9-11 am "
        '1 White Delrin Acetal Resin Bar Oversized Tolerance 3" Thick, 3" Wide, '
        "1 ft. Length 8741K53 1 each 113.92 each $113.92 "
        '2 Low-Carbon Steel Bar 1" Thick, 2-1/2" Wide, 1 Foot Long 8910K54 '
        "1 each 45.41 each $45.41 Merchandise Order Total: $198.25"
    )
    msg = EmailMessage(
        "3",
        from_address="orders@mcmaster.com",
        subject="Confirmation for Your October 13th Order with McMaster-Carr",
        body_text=body,
    )
    parsed = a.parse(msg)
    by_pn = {l.part_number.upper(): l for l in parsed.lines}
    d = by_pn["8741K53"]
    s = by_pn["8910K54"]
    assert "Payment" not in d.description and "Visa" not in d.description
    assert d.description.startswith("White Delrin")
    assert s.grade == "1018"
    assert s.description.startswith("Low-Carbon Steel")


if __name__ == "__main__":
    test_confirmation_block_prices_and_flat_size()
    test_rod_not_flat()
    test_same_line_visual_row()
    test_strips_payment_method_and_maps_low_carbon_to_1018()
    print("ok")
