"""Deduplicate draft notes / tracking when multiple emails merge."""

from __future__ import annotations

import re
from typing import Optional


_CUSTOMER_REF_RE = re.compile(r"^customer\s*ref\s*:\s*(.+)$", re.I)
_TRACKING_LINE_RE = re.compile(r"^tracking\s*:\s*(.+)$", re.I)
_PIN_RE = re.compile(r"\b([A-Z]{2,4}\d{8,14})\b", re.I)
_PIN_IN_URL_RE = re.compile(r"[?&]pin=([A-Z0-9]+)", re.I)


def merge_note_lines(*blobs: str) -> str:
    """Merge note blobs; keep one Customer ref / one Tracking / unique other lines."""
    customer_ref = ""
    tracking_line = ""
    other: list[str] = []
    seen_other: set[str] = set()

    for blob in blobs:
        for raw in (blob or "").splitlines():
            line = raw.strip()
            if not line:
                continue
            m = _CUSTOMER_REF_RE.match(line)
            if m:
                val = m.group(1).strip()
                if val and val.upper() not in {"ORDER", "DATE", "NUMBER"}:
                    if not customer_ref or (
                        _ref_score(val) > _ref_score(customer_ref)
                    ):
                        customer_ref = val
                continue
            m = _TRACKING_LINE_RE.match(line)
            if m:
                # Prefer URL form over bare PIN when both appear
                cand = m.group(1).strip()
                tracking_line = prefer_tracking(tracking_line, cand) or cand
                continue
            key = line.lower()
            if key in seen_other:
                continue
            seen_other.add(key)
            other.append(line)

    out: list[str] = []
    if customer_ref:
        out.append(f"Customer ref: {customer_ref}")
    # Tracking is stored on the draft.tracking field; omit from notes to avoid UI dupes
    out.extend(other)
    return "\n".join(out)


def _ref_score(val: str) -> int:
    v = val.strip()
    if re.search(r"\d", v) and re.search(r"[A-Za-z]", v):
        return 2
    if re.search(r"\d", v):
        return 1
    return 0


def tracking_pin(value: Optional[str]) -> str:
    raw = (value or "").strip()
    if not raw:
        return ""
    m = _PIN_IN_URL_RE.search(raw)
    if m:
        return m.group(1).upper()
    m = _PIN_RE.search(raw)
    return m.group(1).upper() if m else ""


def _tracking_tokens(value: str) -> list[str]:
    return [p for p in (value or "").split() if p]


def prefer_tracking(a: str, b: str) -> str:
    """Pick tracking value(s); prefer full URL over bare PIN for the same shipment."""
    tokens: list[str] = []
    for raw in (a, b):
        tokens.extend(_tracking_tokens(raw or ""))
    if not tokens:
        return ""

    # Group by PIN (or full token if no PIN)
    by_pin: dict[str, str] = {}
    order: list[str] = []
    for tok in tokens:
        pin = tracking_pin(tok) or tok.upper()
        if pin not in by_pin:
            order.append(pin)
            by_pin[pin] = tok
            continue
        cur = by_pin[pin]
        if tok.startswith("http") and not cur.startswith("http"):
            by_pin[pin] = tok
        elif tok.startswith("http") and cur.startswith("http") and len(tok) > len(cur):
            by_pin[pin] = tok
    return " ".join(by_pin[p] for p in order)


def merge_tracking_field(existing: Optional[str], incoming: Optional[str]) -> str:
    return prefer_tracking(existing or "", incoming or "")
