# Shop ERP data contract (DharmaCore)

This document freezes **ownership** and **naming** so Flutter and PocketBase stay aligned while ERP features grow.

## Source of truth (by domain)

| Domain | Owner (PocketBase) | Notes |
|--------|--------------------|--------|
| Tool catalog, stock by location, transfers, movement history | Existing inventory collections (`inventory`, `locations`, `tool_locations`, `movement_history`, …) | Do not rename without a migration plan. |
| Purchase orders / buy list | Existing purchase collections (`purchases`, `purchase_items`, …) | Keep separate from customer quotes. |
| Brands, suppliers (vendors for tooling) | Existing `brands`, `suppliers` | “Vendor” for **materials/tooling** lives here unless we later split a dedicated `vendors` collection. |
| **Customers** (people/companies you quote) | **New** `customers` collection (Week 1) | Not the same as `suppliers` unless you explicitly merge workflows. |
| **Customer ship-to sites** | **`customer_ship_tos`** | Many named addresses per customer (label, address, attn, `is_default`). Jobs pick one via `jobs.ship_to`; optional `jobs.ship_to_override` for one-offs. |
| **Quotes** and **quote line items** | **New** `quotes`, `quote_line_items` (Week 2) | Links to `customers`; totals snapshotted on the quote where possible. Line-item relations `material_vendor`, `subcontractor_1`, `subcontractor_2` use `suppliers` (DharmaCore used `vendors`). |
| **Jobs** and **job line items** | **`jobs`**, **`job_line_items`** | Ordered parts live on `job_line_items` (description, quantity, packed_quantity). `parts_description` is a synced search snapshot. Packing slip # on `jobs.packing_slip_number`; next number in `app_settings.next_packing_slip_number` (starts at 3000 → `PS3000`). |
| **Wiki** (shop docs) | **`wiki_pages`** | Nested pages, markdown, visibility `everyone` / `staff` / `owner`. |
| **Maintenance** (log + schedules) | **`maintenance_records`**, **`maintenance_machines`**, **`maintenance_schedules`** | Log = completed work (ad-hoc OK). Schedules = recurring days/weeks/months with `next_due_date`; Mark done writes a log row and advances next due. Optional `schedule` on records. Everyone logged in can CRUD. |

## Cross-app references

- Store **PocketBase record ids** (`id` strings) on relations; avoid duplicating whole objects on quotes/jobs.
- DharmaCore (React) remains read-only reference until Flutter parity; **ids** in new collections should be native to this PocketBase instance (no assumed overlap with another DB).

## Quote / job status enums (draft)

- Quotes: `draft` | `sent` | `won` | `lost`
- Jobs: `planning` | `in_progress` | `done` | `cancelled`

Adjust in one place (contract + PB select fields + Flutter) when you lock real shop wording.

## Dev vs prod

- **`erp-dev`** uses a **copy** of data and its own URL/port; schema experiments happen there first.
- Production changes only after migrations are in `pb_migrations/` and tested on dev.
