import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from poller import _prefer_mill_cert_line


def test_prefer_steel_over_delrin_for_mill_cert():
    lines = [
        {
            "id": "delrin",
            "description": "White Delrin Acetal Resin Bar 8741K53",
            "part_number": "8741K53",
        },
        {
            "id": "steel",
            "description": "Low-Carbon Steel Bar 8910K54",
            "part_number": "8910K54",
            "proposed_material_json": '{"grade":"1018","form":"flat"}',
        },
    ]
    pick = _prefer_mill_cert_line(lines)
    assert pick is not None
    assert pick["id"] == "steel"


def test_prefer_first_when_no_metal_hint():
    lines = [
        {"id": "a", "description": "Misc part", "part_number": "X"},
        {"id": "b", "description": "Other", "part_number": "Y"},
    ]
    pick = _prefer_mill_cert_line(lines)
    assert pick is not None
    assert pick["id"] == "a"


if __name__ == "__main__":
    test_prefer_steel_over_delrin_for_mill_cert()
    test_prefer_first_when_no_metal_hint()
    print("ok")
