"""Match DGI/item lines against the shop tools catalog (inventory/tools)."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Optional


def normalize(text: str) -> str:
    s = (text or "").lower().strip()
    s = re.sub(r"[^a-z0-9.\s/-]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def catalog_tokens(tool: dict[str, Any]) -> set[str]:
    parts = [
        str(tool.get("tool_name") or ""),
        str(tool.get("model_number") or ""),
        str(tool.get("manufacturer_barcode") or ""),
        str(tool.get("size") or ""),
        str(tool.get("serial_number") or ""),
    ]
    blob = normalize(" ".join(parts))
    return {t for t in blob.split() if len(t) >= 2}


def part_candidates(part_number: str, description: str = "") -> list[str]:
    """Harvey/DGI style: HVT989816C4 → 989816C4, 989816-C4, 989816."""
    out: list[str] = []
    pn = (part_number or "").strip().upper()
    if pn:
        out.append(pn)
        if pn.startswith("HVT") and len(pn) > 3:
            rest = pn[3:]
            out.append(rest)
            # 989816C4 → 989816-C4
            m = re.match(r"^(\d+)([A-Z].*)$", rest)
            if m:
                out.append(f"{m.group(1)}-{m.group(2)}")
                out.append(m.group(1))
    # Trailing catalog digits in description: "... 989816-C4" or "... 68320"
    for m in re.finditer(r"\b(\d{4,7}(?:-[A-Z0-9]+)?)\b", description or "", re.I):
        out.append(m.group(1).upper())
    # Dedupe preserve order
    seen: set[str] = set()
    uniq: list[str] = []
    for c in out:
        if c and c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq


@dataclass
class ToolMatchResult:
    status: str  # matched|ambiguous|none|n_a
    matched_tool_id: Optional[str] = None
    candidate_ids: list[str] = field(default_factory=list)
    score: float = 0.0


def match_tool_line(
    *,
    tools: list[dict[str, Any]],
    part_number: str = "",
    description: str = "",
    line_type: str = "item",
) -> ToolMatchResult:
    if line_type != "item":
        return ToolMatchResult(status="n_a")

    needles = part_candidates(part_number, description)
    if not needles and not (description or "").strip():
        return ToolMatchResult(status="none")

    scored: list[tuple[float, dict[str, Any]]] = []
    for t in tools:
        tid = t.get("id")
        if not tid:
            continue
        hay = normalize(
            " ".join(
                str(t.get(k) or "")
                for k in (
                    "tool_name",
                    "model_number",
                    "manufacturer_barcode",
                    "size",
                    "serial_number",
                )
            )
        )
        hay_compact = hay.replace(" ", "").replace("-", "")
        score = 0.0
        for n in needles:
            nn = normalize(n).replace(" ", "")
            if not nn:
                continue
            if nn in hay_compact or normalize(n) in hay:
                score = max(score, 0.95 if len(nn) >= 5 else 0.8)
            # model_number exact-ish
            model = normalize(str(t.get("model_number") or "")).replace(" ", "").replace("-", "")
            if model and (model == nn or nn in model or model in nn):
                score = max(score, 1.0)
        if score <= 0 and description:
            desc_toks = {t for t in normalize(description).split() if len(t) >= 3}
            overlap = desc_toks & catalog_tokens(t)
            if len(overlap) >= 3:
                score = 0.55
        if score > 0:
            scored.append((score, t))

    if not scored:
        return ToolMatchResult(status="none")

    scored.sort(key=lambda x: x[0], reverse=True)
    top = scored[0][0]
    tops = [t for s, t in scored if s >= top - 0.05 and s >= 0.75]
    if len(tops) == 1 and top >= 0.8:
        return ToolMatchResult(
            status="matched",
            matched_tool_id=str(tops[0]["id"]),
            candidate_ids=[str(tops[0]["id"])],
            score=top,
        )
    if len(tops) > 1 or (scored and top >= 0.55):
        cands = [str(t["id"]) for _, t in scored[:8]]
        return ToolMatchResult(
            status="ambiguous",
            candidate_ids=cands,
            score=top,
        )
    return ToolMatchResult(status="none", score=top)
