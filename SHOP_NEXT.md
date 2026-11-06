# Shop next (new DharmaCore CT)

Living list so we don’t rely on chat history. Update this when something is done.

**Live shop (use this):** `https://dharmacore.sscadcam.com/` → CT **105**, LAN `192.168.20.101`  
**Deploy web:** **`DEPLOY_SHOP.md`** — `.\scripts\build_web_shop.ps1`, then laptop `scp` + `ssh` (you type the password).  
**Logins:** PocketBase **`users`** (not `/_/` admin). This PC may use a `hosts` line to `.101`. **Do not** port-forward **443** to the internet.

**Leave running:** Cribhub CT **101** (`.102`), old DharmaCore CT **102** (`.103`), erp-dev CT **103** (`.104`).

---

## App / product

- [ ] **Users screen** in the app (list/edit shop logins: email, `role`, `wiki_owner`, `wiki_readonly`) so you are not stuck in PocketBase Admin. Wiki visibility stays flexible for that later.
- [x] **Maintenance log** — PocketBase `maintenance_records` + `maintenance_machines`; Shop ERP drawer; everyone logged in can edit; add machines from the app. Migration fixed (no `-created` sort). Applied on CT 105.
- [ ] **Maintenance schedules / alerts** — see **Maintenance roadmap** below (Phase A in progress).
- [ ] Wiki on live CT 105: copy `pb_migrations/1775000000_wiki_pages_and_user_flags.js`, restart PocketBase, set your user **`wiki_owner` = true**, deploy a new web zip. Paste Notion as markdown.
- [ ] Chrome **Not secure** on the HTTPS shop: mixed HTTP content. Optional; cert is valid.
- [ ] Bitwarden autofill: often blocked by that warning + Flutter fields. Login form now has autofill hints; sessions persist across hard refresh. Still may need Fill from the extension until mixed content is gone.
- [ ] Extra shop logins: create more records in PocketBase **`users`**.
- [x] Tablets/phones: use `.\scripts\buildapk_shop.bat` (dharmacore URLs + About build stamp). Old `buildapk.bat` remains cribhub-only.
- [ ] Inventory barcode scanning (`lib/inventory_home_screen.dart`) — old code TODO, not part of the merge.

## Maintenance roadmap

Keep **log** (what was done) separate from **schedules** (what is due next). Ad-hoc log entries without a schedule are fine — use history later to decide a frequency.

**Locked decisions**
- Frequencies: **days / weeks / months** (hours skipped for now; calendar or runtime hours later if needed).
- **Mark done** always creates a `maintenance_records` log row, then advances `next_due_date`.
- Alerts: **everyone** logged in (same as current maintenance CRUD).
- No special “once” frequency — one-off work stays a Log entry.
- Default **lead_days** = 7 (due soon within a week of next due).
- Suggest-schedule-from-history: not in v1 (add schedule by hand when you know the interval).

**Phases**
- [x] **Phase A — in-app schedules** (code ready) — Collection `maintenance_schedules`; Log | Schedule on Maintenance screen; due/overdue banner at top of Maintenance; Mark done → log + bump next due. **Deploy:** migration `1775400000_maintenance_schedules.js` + `shop-web.zip` on CT 105 (restart + `/api/health`).
- [ ] **Phase A2 — dashboard** — Due/overdue count or banner on the main dashboard (after Phase A feels solid).
- [ ] **Phase B — passive reminders** — Optional email/Slack digest later (no push infra on CT 105 yet).
- [ ] **Phase C — hours** — Optional calendar-hours frequency and/or machine runtime hours (needs hour meter) if the shop wants it.

**Live deploy reminder (CT 105):** unit/path is still named `pocketbase-erp-dev` on `root@dharmacore` (`192.168.20.101`). That **is** live shop. Copy migrations from the **laptop**, then restart and confirm health on the CT.

---

## UI look (theme-first)

**Decision (2026-10-01):** Refresh the look with **Material theme skins**, not a full rewrite onto `shadcn_ui` / Forui yet.

- **Done (first pass):** Named skins + tokens in `lib/app_theme.dart`. Default **Machine Shop Graphite** (charcoal + amber). Alternates **Precision Cool** (steel blue), **Cool Mint** (teal). Settings → Display → **Skin** picker + dark mode. Quote sidebar CTAs / list action buttons use `ColorScheme` (no indigo→violet gradient).
- **Done (shadcn-like Material chrome):** Zinc neutrals, Inter font, flat AppBars/cards/dialogs (1px borders, no elevation), outline inputs, denser buttons. Skins now only change the accent; chrome language is shared.
- **Later (optional):** Middle-path `shadcn_ui` only if forms/dialogs/badges still feel weak — buttons/inputs first, not a full screen rewrite. Skip Forui unless we want bleeding-edge Flutter.
- **Still to chase:** Hardcoded Tailwind greys / status chip hexes on tables and dense screens as we touch them; more shared chrome on lists/forms. Redeploy via **`DEPLOY_SHOP.md`** when ready.
- **Done (sidebar chrome):** `DrawerSectionLabel` + `DrawerNavTile` in `app_drawer.dart` — muted section labels, hover rows, flat bordered panel (no Material elevation).
- **Done (list toolbar alignment):** Search fields and primary list actions share `kListToolbarControlHeight` (**48**) via `InventoryListSearchField` + `InventoryListActionButton` in `lib/list_toolbar_widgets.dart`.

### Workspace layout tokens

Shared numbers live in `lib/ui_breakpoints.dart`, `lib/workspace_layout.dart`, and `lib/list_toolbar_widgets.dart` — prefer those constants over hardcoding.

| Token | Value | Use |
|-------|------:|-----|
| `kWorkspaceContentMaxWidth` | **1400** | Primary content for **Shop ERP** and **Management** list/workspace screens. Wrap with `workspaceContentFrame(...)`. |
| `kWorkspacePanelContentMaxWidth` | **420** | Master-list column when a detail panel is open (e.g. Purchases). Detail gets ~70% (`flex` 3/7); date/total move to hover tooltip on list rows. |
| `kAppDrawerWidth` (`app_drawer.dart`) | **200** | Fixed side menu width. |
| `kPinnedDrawerBreakpointPx` | **900** | Pin drawer when viewport ≥ this and keep-drawer-open is on. |
| `kWorkspaceWideBreakpointPx` | **1024** | Two-column / master-detail layouts. |
| `kListToolbarControlHeight` | **48** | List search field + `InventoryListActionButton` height (same row). Use `InventoryListSearchField` (not a bare `TextField`) so height is locked. |

Detail/editor screens may use smaller form widths. New Shop ERP / Management screens should use `workspaceContentFrame` and not invent a new content max width. List toolbars should use `InventoryListSearchField` + `InventoryListActionButton` so heights stay matched.

## Ops (only if it bites you)

- [ ] UniFi **DNS Host (A)** `dharmacore.sscadcam.com` → `192.168.20.101` if some LAN device still misses the new site (skip if WiFiman/phone already work).
- [ ] Next Let’s Encrypt renew: HTTP-01 needs WAN **80** to CT **102** (or move Certbot to **105**), then copy certs **102 → 105** again. Do not leave **80** open.
- [ ] Commit `scripts/migrate_dcore/migrate.js` superuser (`_superusers`) auth fallback if you want that in git. **Never commit** `scripts/migrate_dcore/.env`.

## Done (this cutover)

- Cribhub `pb_data` on CT 105; ERP import from `.103`; Flutter zip for `https://dharmacore.sscadcam.com/`; Nginx + renewed cert on 105.
