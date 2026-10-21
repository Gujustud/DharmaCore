import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from note_utils import merge_note_lines, merge_tracking_field, prefer_tracking


def test_merge_notes_dedupes_customer_ref_and_drops_tracking():
    merged = merge_note_lines(
        "Customer ref: 1013ASOLANKI\nTracking: CPK004315941\n",
        "Customer ref: 1013ASOLANKI\nTracking: https://www.purolator.com/en/shipping/tracker?pin=CPK004315941\n",
        "Customer ref: ORDER\nMcMaster cert/shipment seq: 7110963-01\n",
    )
    assert merged.count("Customer ref:") == 1
    assert "1013ASOLANKI" in merged
    assert "ORDER" not in merged
    assert "Tracking:" not in merged  # lives on draft.tracking
    assert "7110963-01" in merged


def test_prefer_tracking_same_pin_keeps_url():
    assert prefer_tracking(
        "CPK004315941",
        "https://www.purolator.com/en/shipping/tracker?pin=CPK004315941",
    ).startswith("http")
    assert merge_tracking_field(
        "CPK004315941 https://www.purolator.com/en/shipping/tracker?pin=CPK004315941",
        "CPK004315941",
    ).startswith("http")


if __name__ == "__main__":
    test_merge_notes_dedupes_customer_ref_and_drops_tracking()
    test_prefer_tracking_same_pin_keeps_url()
    print("ok")
