"""Match parsed material lines against the shop materials catalog."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Optional


ALIASES = {
    "aluminium": "aluminum",
    "dia": "diameter",
    "diam": "diameter",
    "od": "od",
    "id": "id",
    '"': "in",
    "inch": "in",
    "inches": "in",
    "feet": "ft",
    "foot": "ft",
}


def normalize(text: str) -> str:
    s = (text or "").lower().strip()
    s = s.replace("×", "x").replace("″", '"').replace("′", "'")
    for a, b in ALIASES.items():
        s = re.sub(rf"\b{re.escape(a)}\b", b, s)
    s = re.sub(r"[^a-z0-9.\s/x-]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _tokens(text: str) -> set[str]:
    return {t for t in normalize(text).split() if t}


@dataclass
class MatchResult:
    status: str  # matched|ambiguous|propose_new|none|n_a
    matched_material_id: Optional[str] = None
    candidate_ids: list[str] = None  # type: ignore
    proposed: Optional[dict[str, str]] = None
    score: float = 0.0

    def __post_init__(self) -> None:
        if self.candidate_ids is None:
            self.candidate_ids = []


def score_material(
    catalog: dict[str, Any],
    grade: str,
    form: str,
    size_label: str,
    description: str = "",
) -> float:
    """Score 0..1 how well a catalog row matches the parsed hints."""
    c_grade = normalize(str(catalog.get("grade", "")))
    c_form = normalize(str(catalog.get("form", "")))
    c_size = normalize(str(catalog.get("size_label", "")))
    g = normalize(grade)
    f = normalize(form)
    s = normalize(size_label)
    desc = normalize(description)

    score = 0.0
    if g and c_grade:
        if g == c_grade or g in c_grade or c_grade in g:
            score += 0.45
        elif _tokens(g) & _tokens(c_grade):
            score += 0.2
    if f and c_form:
        if f == c_form:
            score += 0.25
    if s and c_size:
        if s == c_size:
            score += 0.3
        else:
            # partial size token overlap
            overlap = _tokens(s) & _tokens(c_size)
            if overlap:
                score += 0.15 * min(1.0, len(overlap) / max(1, len(_tokens(s))))
    # Soft boost if description mentions catalog grade/size
    if desc:
        if c_grade and c_grade in desc:
            score += 0.05
        if c_size and c_size in desc:
            score += 0.05
    return min(score, 1.0)


def match_material_line(
    *,
    materials: list[dict[str, Any]],
    grade: str = "",
    form: str = "",
    size_label: str = "",
    description: str = "",
    line_type: str = "material",
    high_threshold: float = 0.75,
    ambiguous_threshold: float = 0.45,
) -> MatchResult:
    if line_type not in ("material",):
        return MatchResult(status="n_a")

    if not grade and not form and not size_label:
        # Try to still propose from description alone
        if not description.strip():
            return MatchResult(status="none")
        proposed = {
            "grade": grade or _guess_grade(description) or "Unknown",
            "form": form or _guess_form(description) or "other",
            "size_label": size_label or _guess_size(description) or description[:80],
            "unit": "ea",
        }
        return MatchResult(status="propose_new", proposed=proposed)

    scored: list[tuple[float, dict[str, Any]]] = []
    for m in materials:
        sc = score_material(m, grade, form, size_label, description)
        if sc > 0:
            scored.append((sc, m))
    scored.sort(key=lambda x: x[0], reverse=True)

    if scored and scored[0][0] >= high_threshold:
        mid = str(scored[0][1].get("id") or scored[0][1].get("material_id") or "")
        return MatchResult(
            status="matched",
            matched_material_id=mid or None,
            candidate_ids=[str(s[1].get("id", "")) for s in scored[:3] if s[1].get("id")],
            score=scored[0][0],
            proposed={
                "grade": grade,
                "form": form or "other",
                "size_label": size_label,
                "unit": "ea",
            },
        )

    if scored and scored[0][0] >= ambiguous_threshold:
        return MatchResult(
            status="ambiguous",
            candidate_ids=[str(s[1].get("id", "")) for s in scored[:3] if s[1].get("id")],
            score=scored[0][0],
            proposed={
                "grade": grade or "Unknown",
                "form": form or "other",
                "size_label": size_label or description[:80],
                "unit": "ea",
            },
        )

    return MatchResult(
        status="propose_new",
        proposed={
            "grade": grade or _guess_grade(description) or "Unknown",
            "form": form or _guess_form(description) or "other",
            "size_label": size_label or _guess_size(description) or description[:80],
            "unit": "ea",
        },
        candidate_ids=[str(s[1].get("id", "")) for s in scored[:3] if s[1].get("id")],
        score=scored[0][0] if scored else 0.0,
    )


_GRADE_RE = re.compile(
    r"\b(6061(?:-T6)?|7075(?:-T6)?|4140|4340|A36|1018|1045|304(?:L)?|316(?:L)?|"
    r"Delrin|Acetal)\b",
    re.I,
)
_GRADE_ALIASES = [
    (re.compile(r"\blow[-\s]?carbon\s+steel\b", re.I), "1018"),
    (re.compile(r"\bmild\s+steel\b", re.I), "1018"),
]
_FORM_HINTS = [
    (re.compile(r"\bflat\s+bar\b|\bflat\b", re.I), "flat"),
    (re.compile(r"\brod\b|\bround\s+bar\b|\bdia\b|\bdiameter\b", re.I), "bar"),
    (re.compile(r"\bplate\b", re.I), "plate"),
    (re.compile(r"\bsheet\b", re.I), "sheet"),
    (re.compile(r"\btube\b|\btubing\b", re.I), "tube"),
    (re.compile(r"\bhex\b", re.I), "hex"),
    (re.compile(r"\bbar\b", re.I), "bar"),
]
_FLAT_DIM_RE = re.compile(r"\bthick\b|\bwide\b|\bwidth\b|\bthickness\b", re.I)
_SIZE_RE = re.compile(
    r"(\d+(?:\.\d+)?\s*(?:\"|in)?(?:\s*[x×]\s*\d+(?:\.\d+)?\s*(?:\"|in|ft)?){0,3})",
    re.I,
)


def _guess_grade(description: str) -> str:
    d = description or ""
    m = _GRADE_RE.search(d)
    if m:
        return m.group(1).strip()
    for rx, alias in _GRADE_ALIASES:
        if rx.search(d):
            return alias
    return ""


def _guess_form(description: str) -> str:
    d = description or ""
    if _FLAT_DIM_RE.search(d) and re.search(r"\bbar\b", d, re.I):
        if not re.search(r"\brod\b|\bround\b|\bdia\.?\b|\bdiameter\b", d, re.I):
            return "flat"
    for rx, key in _FORM_HINTS:
        if rx.search(d):
            if key == "bar" and _FLAT_DIM_RE.search(d):
                if not re.search(r"\brod\b|\bround\b|\bdia\.?\b", d, re.I):
                    return "flat"
            return key
    if _FLAT_DIM_RE.search(d):
        return "flat"
    return ""


def _guess_size(description: str) -> str:
    m = _SIZE_RE.search(description or "")
    return m.group(1).strip() if m else ""
