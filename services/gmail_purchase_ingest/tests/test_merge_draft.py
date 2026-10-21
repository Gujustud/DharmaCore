import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from pb_client import _merge_day_key, pick_same_day_merge_draft


def test_merge_day_from_mc_day_ref():
    assert _merge_day_key("MC-DAY-2026-10-13") == "2026-10-13"
    assert _merge_day_key("MC-DAY-2026-10-13", "2026-10-14") == "2026-10-13"


def test_merge_day_from_purchase_date_for_numeric():
    assert _merge_day_key("7110963", "2026-10-13") == "2026-10-13"
    assert _merge_day_key("7110963") is None


def test_cert_merges_onto_numeric_same_order_day():
    """Cert draft dated Oct 14 still correlates via MC-DAY-2026-10-13 → Oct 13 order."""
    candidates = [
        {
            "id": "orphan",
            "order_reference": "MC-DAY-2026-10-13",
            "purchase_date": "2026-10-14",
        },
        {
            "id": "real",
            "order_reference": "7110963",
            "purchase_date": "2026-10-13",
        },
    ]
    picked = pick_same_day_merge_draft(
        candidates, day="2026-10-13", incoming_ref="MC-DAY-2026-10-13"
    )
    assert picked is not None
    assert picked["id"] == "real"


def test_numeric_absorbs_mc_day_orphan():
    candidates = [
        {
            "id": "orphan",
            "order_reference": "MC-DAY-2026-10-13",
            "purchase_date": "2026-10-14",
        },
    ]
    picked = pick_same_day_merge_draft(
        candidates, day="2026-10-13", incoming_ref="7110963"
    )
    assert picked is not None
    assert picked["id"] == "orphan"
