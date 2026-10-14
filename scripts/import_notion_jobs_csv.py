#!/usr/bin/env python3
"""
One-shot: import a Notion Jobs CSV export into PocketBase `jobs` (live shop).

Example:
  python scripts/import_notion_jobs_csv.py ^
    --csv "C:\\Users\\gujus\\Downloads\\Jobs ....csv" ^
    --email amish@sscadcam.com ^
    --dry-run

  python scripts/import_notion_jobs_csv.py ^
    --csv "C:\\Users\\gujus\\Downloads\\Jobs ....csv" ^
    --email amish@sscadcam.com

Password is prompted if --password is omitted.
Skips rows that fail; prints an issues report at the end.
"""

from __future__ import annotations

import argparse
import csv
import getpass
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path


STATUS_MAP = {
    "done": "done",
    "archive": "done",
    "archived": "done",
    "in progress": "in_progress",
    "in_progress": "in_progress",
    "planning": "planning",
    "backlog": "planning",
    "to do": "planning",
    "todo": "planning",
    "quotes": "planning",
    "cancelled": "cancelled",
    "canceled": "cancelled",
    "not started": "planning",
}

TRACKING_MAP = {
    "not shipped": "not_shipped",
    "not_shipped": "not_shipped",
    "in transit": "in_transit",
    "in_transit": "in_transit",
    "delivered": "delivered",
    "shipped": "in_transit",
}


def api(url: str, method: str = "GET", token: str | None = None, body: dict | None = None):
    data = None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = token
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code} {method} {url}\n{err}") from e


def parse_date(raw: str) -> str | None:
    raw = (raw or "").strip()
    if not raw:
        return None
    # Notion sometimes prefixes dates with @
    if raw.startswith("@"):
        raw = raw[1:].strip()
    for fmt in (
        "%B %d, %Y",
        "%b %d, %Y",
        "%Y-%m-%d",
        "%m/%d/%Y",
        "%d/%m/%Y",
    ):
        try:
            return datetime.strptime(raw, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def clean_job_number(raw: str) -> str:
    s = (raw or "").strip()
    s = re.sub(r"\s+", "", s)
    return s


def job_number_from_project(project: str) -> str | None:
    """MMDDYYYY-style digits from project name (leading or embedded)."""
    p = (project or "").strip()
    m = re.match(r"^\s*(\d{6,10})\b", p)
    if m:
        return m.group(1)
    m = re.search(r"\b(\d{8})\b", p)  # prefer 8-digit job dates
    if m:
        return m.group(1)
    m = re.search(r"\b(\d{6,10})\b", p)
    return m.group(1) if m else None


def customer_from_project(project: str) -> str | None:
    """
    Heuristic customer from project title:
    - '11062023 - META' → META
    - 'Trial Engineering - 07042022 - PO1452' → Trial Engineering
    - 'LTT - Desk Chassis' → LTT
    """
    p = (project or "").strip()
    if " - " not in p:
        return None
    parts = [x.strip() for x in p.split(" - ") if x.strip()]
    if not parts:
        return None
    if re.fullmatch(r"\d{6,10}", parts[0].replace(" ", "")):
        return " - ".join(parts[1:]) or None
    return parts[0] or None


def map_status(raw: str) -> str:
    key = (raw or "").strip().lower()
    if not key:
        return "planning"
    return STATUS_MAP.get(key, "planning")


def map_tracking(raw: str) -> str:
    key = (raw or "").strip().lower()
    if not key:
        return "not_shipped"
    return TRACKING_MAP.get(key, "not_shipped")


def build_notes(row: dict) -> str:
    chunks: list[str] = []
    attachments = (row.get("Attachments") or "").strip()
    if attachments:
        chunks.append(f"Attachments: {attachments}")
    tasks = (row.get("Tasks") or "").strip()
    if tasks:
        # Strip Notion URLs to keep notes readable
        tasks_clean = re.sub(r"\s*\(https?://[^)]+\)", "", tasks)
        chunks.append(f"Tasks: {tasks_clean}")
    owner = (row.get("Owner") or "").strip()
    if owner:
        chunks.append(f"Owner: {owner}")
    assign = (row.get("Assign") or "").strip()
    if assign:
        chunks.append(f"Assign: {assign}")
    label = (row.get("Label") or "").strip()
    if label:
        chunks.append(f"Label: {label}")
    status1 = (row.get("Status 1") or "").strip()
    if status1:
        chunks.append(f"Status 1: {status1}")
    return "\n".join(chunks)


def list_all(base: str, collection: str, token: str, fields: str | None = None) -> list[dict]:
    items: list[dict] = []
    page = 1
    while True:
        q = f"page={page}&perPage=200"
        if fields:
            q += f"&fields={urllib.parse.quote(fields)}"
        data = api(f"{base}/api/collections/{collection}/records?{q}", token=token)
        batch = data.get("items") or []
        items.extend(batch)
        total_pages = int(data.get("totalPages") or 1)
        if page >= total_pages:
            break
        page += 1
    return items


def find_customer_id(customers: list[dict], name: str) -> str | None:
    needle = name.strip().lower()
    if not needle:
        return None
    for c in customers:
        company = (c.get("company") or "").strip().lower()
        cname = (c.get("name") or "").strip().lower()
        if company == needle or cname == needle:
            return c.get("id")
        if needle in company or company in needle:
            return c.get("id")
    return None


def ensure_customer(
    base: str,
    token: str,
    customers: list[dict],
    name: str,
    dry_run: bool,
) -> tuple[str | None, bool]:
    """Return (customer_id, created)."""
    existing = find_customer_id(customers, name)
    if existing:
        return existing, False
    if dry_run:
        return f"new:{name}", True
    rec = api(
        f"{base}/api/collections/customers/records",
        method="POST",
        token=token,
        body={"company": name.strip()},
    )
    customers.append(rec)
    return rec.get("id"), True


def normalize_url(raw: str) -> str | None:
    """Return a valid http(s) URL, or None if the value is not a link."""
    s = (raw or "").strip()
    if not s:
        return None
    # Notion sometimes appends notes after a real URL ("…id=123 last shipment").
    if re.match(r"^https?://", s, re.I):
        s = s.split()[0]
        return s if " " not in s else None
    # Common: domain without scheme
    if re.match(r"^[\w.-]+\.[a-z]{2,}(/|$)", s, re.I) and " " not in s:
        return "https://" + s
    return None


def row_to_body(
    row: dict,
    customers: list[dict],
    base: str,
    token: str,
    dry_run: bool,
    existing_job_numbers: set[str],
    pb_job_numbers: set[str],
) -> tuple[dict | None, str | None, list[str]]:
    """
    Returns (body, skip_reason, warnings).
    skip_reason set => do not create.
    """
    warnings: list[str] = []
    project = (row.get("Project name") or "").strip()
    job_raw = clean_job_number(row.get("Job") or "")
    if not job_raw:
        parsed = job_number_from_project(project)
        if parsed:
            job_raw = parsed
            warnings.append(f"job_number from project name: {job_raw}")
    if not job_raw:
        # Use sanitized project title as last resort
        if project:
            job_raw = re.sub(r"\s+", " ", project)[:80]
            warnings.append("no Job column; used Project name as job_number")
        else:
            return None, "missing job_number and Project name", warnings

    # Skip if already in PocketBase (re-runs must not create -2 copies).
    # Within this CSV run, uniquify collisions as -2, -3, ...
    base_jn = job_raw
    if job_raw.lower() in existing_job_numbers and job_raw.lower() in pb_job_numbers:
        return None, f"job_number already in PocketBase: {job_raw}", warnings
    n = 2
    while job_raw.lower() in existing_job_numbers:
        job_raw = f"{base_jn}-{n}"
        n += 1
        if n > 50:
            return None, f"could not uniquify job_number from {base_jn}", warnings
    if job_raw != base_jn:
        warnings.append(f"duplicate job_number in CSV; stored as {job_raw}")

    status_raw = (row.get("Status") or "").strip()
    status = map_status(status_raw)
    if status_raw and status_raw.strip().lower() not in STATUS_MAP:
        warnings.append(f"unknown Status '{status_raw}' → planning")

    customer_name = customer_from_project(project)
    customer_id = None
    if customer_name:
        customer_id, created = ensure_customer(
            base, token, customers, customer_name, dry_run
        )
        if created:
            warnings.append(f"will create customer: {customer_name}")

    due = parse_date(row.get("Due Date") or "")
    ship = parse_date(row.get("Ship Date") or "")
    invoice_raw = (row.get("Invoice") or "").strip()
    wave = None
    if invoice_raw:
        # Only keep if it looks like an invoice id, not a @date
        if invoice_raw.startswith("@"):
            warnings.append(f"skipped Invoice date-like value: {invoice_raw}")
        else:
            d = parse_date(invoice_raw)
            if d and d == parse_date(invoice_raw):
                # still a date
                if re.search(r"[A-Za-z]", invoice_raw) or invoice_raw.startswith("@"):
                    warnings.append(f"skipped Invoice date-like value: {invoice_raw}")
                else:
                    wave = invoice_raw
            else:
                wave = invoice_raw

    notes = build_notes(row)
    tracking_link_raw = (row.get("Tracking Link") or "").strip()
    tracking_link = normalize_url(tracking_link_raw)
    tracking_num = (row.get("Tracking Number") or "").strip() or None
    tracking_2 = (row.get("Tracking 2") or "").strip() or None
    if tracking_link_raw and not tracking_link:
        # Notion often put courier name + pin in Tracking Link (not a URL).
        if not tracking_num:
            tracking_num = tracking_link_raw
            warnings.append(
                f"Tracking Link is not a URL; stored as tracking_number_1: {tracking_link_raw}"
            )
        else:
            extra = f"Tracking (non-URL): {tracking_link_raw}"
            notes = f"{notes}\n{extra}".strip() if notes else extra
            warnings.append(
                f"Tracking Link is not a URL; appended to project_notes: {tracking_link_raw}"
            )
    tracking_status = map_tracking(row.get("Tracking Status") or "")

    body: dict = {
        "job_number": job_raw,
        "status": status,
        "tracking_status": tracking_status,
        "parts_description": project or None,
        "customer_name": customer_name,
        "customer": customer_id if customer_id and not str(customer_id).startswith("new:") else None,
        "due_date": due,
        "ship_date": ship,
        "po_number": (row.get("PO #") or "").strip() or None,
        "material_lot": (row.get("Material LOT") or "").strip() or None,
        "wave_invoice_number": wave,
        "tracking_number_1": tracking_num,
        "tracking_link_1": tracking_link,
        "tracking_number_2": tracking_2,
        "project_notes": notes or None,
    }
    # Drop None values so PB defaults apply
    body = {k: v for k, v in body.items() if v is not None and v != ""}
    return body, None, warnings


def main() -> int:
    p = argparse.ArgumentParser(description="Import Notion Jobs CSV into PocketBase jobs")
    p.add_argument("--csv", required=True, help="Path to Notion CSV export")
    p.add_argument(
        "--email",
        default="amish@sscadcam.com",
        help="PocketBase user email",
    )
    p.add_argument("--password", help="PocketBase password (prompted if omitted)")
    p.add_argument(
        "--url",
        default="https://dharmacore.sscadcam.com",
        help="PocketBase base URL (no trailing slash)",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and report; do not create records",
    )
    p.add_argument(
        "--admin",
        action="store_true",
        help="Auth as PocketBase _superusers",
    )
    p.add_argument(
        "--offline",
        action="store_true",
        help="Parse CSV only (no auth / no PocketBase). Implies --dry-run.",
    )
    args = p.parse_args()

    csv_path = Path(args.csv)
    if not csv_path.is_file():
        raise SystemExit(f"CSV not found: {csv_path}")

    if args.offline:
        args.dry_run = True

    base = args.url.rstrip("/")
    token = ""
    existing_job_numbers: set[str] = set()
    customers: list[dict] = []

    if not args.offline:
        password = (
            args.password
            or __import__("os").environ.get("PB_PASSWORD")
            or __import__("os").environ.get("POCKETBASE_PASSWORD")
            or getpass.getpass("PocketBase password: ")
        )

        auth_paths = ["_superusers"] if args.admin else ["users", "_superusers"]
        token = None
        for coll in auth_paths:
            print(f"Auth as {args.email} via {coll} @ {base} ...")
            try:
                auth = api(
                    f"{base}/api/collections/{coll}/auth-with-password",
                    method="POST",
                    body={"identity": args.email, "password": password},
                )
                token = auth.get("token")
                if token:
                    print(f"  OK ({coll})")
                    break
            except RuntimeError as e:
                print(f"  failed: {e}")
        if not token:
            raise SystemExit("Authentication failed")

        print("Loading existing jobs / customers ...")
        existing_jobs = list_all(base, "jobs", token, fields="id,job_number")
        existing_job_numbers = {
            (j.get("job_number") or "").strip().lower()
            for j in existing_jobs
            if (j.get("job_number") or "").strip()
        }
        pb_job_numbers = set(existing_job_numbers)
        customers = list_all(base, "customers", token)
        print(f"  {len(existing_jobs)} jobs, {len(customers)} customers in PB")
    else:
        print("OFFLINE parse — no PocketBase contact\n")
        existing_jobs = []
        existing_job_numbers = set()
        pb_job_numbers = set()
        customers = []

    with csv_path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    print(f"CSV rows: {len(rows)}")
    if args.dry_run:
        print("DRY RUN — no writes\n")

    created = 0
    skipped: list[tuple[int, str, str]] = []  # line, project, reason
    warnings_all: list[tuple[int, str, str]] = []  # line, project, warning
    new_customer_names: set[str] = set()

    for i, row in enumerate(rows, start=2):  # header is line 1
        project = (row.get("Project name") or "").strip() or "(no name)"
        try:
            body, skip, warnings = row_to_body(
                row,
                customers,
                base,
                token,
                args.dry_run,
                existing_job_numbers,
                pb_job_numbers,
            )
            for w in warnings:
                warnings_all.append((i, project, w))
                if w.startswith("will create customer:"):
                    new_customer_names.add(w.split(":", 1)[1].strip())
            if skip:
                skipped.append((i, project, skip))
                continue
            assert body is not None
            jn = body["job_number"]
            if args.dry_run:
                created += 1
                existing_job_numbers.add(jn.lower())
                continue
            api(
                f"{base}/api/collections/jobs/records",
                method="POST",
                token=token,
                body=body,
            )
            existing_job_numbers.add(jn.lower())
            created += 1
            if created % 25 == 0:
                print(f"  created {created} ...")
        except Exception as e:
            skipped.append((i, project, f"error: {e}"))

    print()
    print("=== Summary ===")
    print(f"Created (or would create): {created}")
    print(f"Customers created (or would): {len(new_customer_names)}")
    print(f"Skipped / issues: {len(skipped)}")
    print(f"Warnings: {len(warnings_all)}")

    if skipped:
        print("\n=== Skipped / issues ===")
        for line, project, reason in skipped:
            print(f"  CSV line {line}: {project}")
            print(f"    -> {reason}")

    if warnings_all and args.dry_run:
        print("\n=== Warnings (sample, dry-run) ===")
        for line, project, w in warnings_all[:40]:
            print(f"  CSV line {line}: {project}")
            print(f"    -> {w}")
        if len(warnings_all) > 40:
            print(f"  ... +{len(warnings_all) - 40} more")

    if not args.dry_run and warnings_all:
        # Only print warnings that aren't routine
        interesting = [
            x
            for x in warnings_all
            if not x[2].startswith("will create customer")
            and not x[2].startswith("job_number from project")
        ]
        if interesting:
            print("\n=== Notable warnings ===")
            for line, project, w in interesting:
                print(f"  CSV line {line}: {project}")
                print(f"    -> {w}")

    return 0 if not skipped or created > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
