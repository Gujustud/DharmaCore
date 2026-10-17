# Gmail purchase ingest — deploy & OAuth

Review-queue pipeline: Gmail → draft purchases at the top of **Purchases** → approve into live `purchases`.

## Architecture

| Piece | Role |
|-------|------|
| `services/gmail_purchase_ingest/` | Python poller + McMaster parser + material matcher |
| PocketBase collections | `email_ingest_vendors`, `email_ingest_messages`, `purchase_drafts`, `purchase_draft_lines`, `material_proposals` |
| Flutter | Drafts section on Purchases; Settings for enable / poll / vendors |

Mailbox: **amish@sscadcam.com**. Default poll: **30 minutes** (Settings). First sync backfills **7 days**.

## Apply schema

Copy `pb_migrations/1776400000_email_purchase_ingest.js` to the CT PocketBase `pb_migrations/`, restart PocketBase, confirm `/api/health`.

Seeded vendors: McMaster (enabled, full adapter), DGI Supply (disabled, stub).

## Settings fields (`settings` collection)

| Field | Purpose |
|-------|---------|
| `email_ingest_enabled` | Master switch (default off until OAuth works) |
| `email_ingest_poll_minutes` | Sleep between cycles (app-editable) |
| `email_ingest_last_sync_*` | Status for Settings UI |
| `email_ingest_history_id` / `email_ingest_backfill_done` | Sync cursor / first-run flag |

Leave **email ingest disabled** until OAuth succeeds.

## Google OAuth walkthrough (`amish@sscadcam.com`)

1. Open [Google Cloud Console](https://console.cloud.google.com/) with an account that can manage the sscadcam project (or create a project).
2. **APIs & Services → Library** → enable **Gmail API**.
3. **OAuth consent screen**: External (or Internal if Workspace allows). App name e.g. `DharmaCore Purchase Ingest`. Scopes: `gmail.readonly`. Add test user `amish@sscadcam.com` while in Testing.
4. **Credentials → Create credentials → OAuth client ID → Desktop app**. Download JSON.
5. On CT 105 (or erp-dev):

```bash
sudo mkdir -p /etc/dharmacore
sudo mv ~/gmail_credentials.json /etc/dharmacore/gmail_credentials.json
sudo chmod 600 /etc/dharmacore/gmail_credentials.json
```

6. Install service deps and run OAuth once (needs a browser — use SSH local forward if needed):

```bash
cd /opt/dharmacore/gmail_purchase_ingest   # or your deploy path
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
export GMAIL_CREDENTIALS_PATH=/etc/dharmacore/gmail_credentials.json
export GMAIL_TOKEN_PATH=/etc/dharmacore/gmail_token.json
python main.py --oauth
```

7. Sign in as **amish@sscadcam.com** → Allow. Confirm `/etc/dharmacore/gmail_token.json` exists (`chmod 600`).

## PocketBase credentials for the service

Prefer a dedicated admin/API user. Set either:

- `PB_TOKEN` (long-lived), or
- `PB_ADMIN_EMAIL` + `PB_ADMIN_PASSWORD`

`PB_URL` e.g. `http://127.0.0.1:8091` on the CT.

## systemd unit example

`/etc/systemd/system/dharmacore-gmail-ingest.service`:

```ini
[Unit]
Description=DharmaCore Gmail purchase ingest
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/dharmacore/gmail_purchase_ingest
Environment=PB_URL=http://127.0.0.1:8091
Environment=PB_ADMIN_EMAIL=REPLACE
Environment=PB_ADMIN_PASSWORD=REPLACE
Environment=GMAIL_CREDENTIALS_PATH=/etc/dharmacore/gmail_credentials.json
Environment=GMAIL_TOKEN_PATH=/etc/dharmacore/gmail_token.json
ExecStart=/opt/dharmacore/gmail_purchase_ingest/.venv/bin/python main.py
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now dharmacore-gmail-ingest
sudo journalctl -u dharmacore-gmail-ingest -f
```

Then in the app: **Settings → enable Email purchase ingest**. Confirm McMaster vendor domains and link to the McMaster supplier record.

## Review flow

1. Poll creates/updates `purchase_drafts` (pending).
2. Open **Purchases** — drafts appear in a **Needs review** section at the top.
3. Open draft → confirm materials / proposals → **Approve** (creates real purchase) or **Reject**.

## Adding another vendor

**Settings → Email vendors**: name, domains, supplier, currency, line-kind, enable. For good line extraction add `adapters/<vendor>.py` and register in `adapters/__init__.py` (DGI is the stub template).
