# Gmail purchase ingest (DharmaCore)

Polls Gmail for vendor order emails (McMaster first), writes **purchase drafts** into PocketBase for review in the Purchases screen. Nothing becomes a live purchase until you approve.

## Requirements

- Python 3.11+
- PocketBase with migration `1776400000_email_purchase_ingest.js` applied
- Google Cloud project with **Gmail API** enabled
- OAuth client (Desktop) secrets JSON + one-time consent as `amish@sscadcam.com`

## Install

```bash
cd services/gmail_purchase_ingest
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Environment

```bash
export PB_URL=http://127.0.0.1:8091
export PB_ADMIN_EMAIL=...
export PB_ADMIN_PASSWORD=...
# or: export PB_TOKEN=...

export GMAIL_CREDENTIALS_PATH=/etc/dharmacore/gmail_credentials.json
export GMAIL_TOKEN_PATH=/etc/dharmacore/gmail_token.json
```

## One-time Gmail OAuth

1. Google Cloud Console → create/select project → enable **Gmail API**.
2. APIs & Services → Credentials → Create **OAuth client ID** → Application type **Desktop app**.
3. Download JSON → save as `gmail_credentials.json` on the CT (path above).
4. OAuth consent screen: add `amish@sscadcam.com` as test user if app is in Testing.
5. On a machine with browser access to the CT (or SSH tunnel):

```bash
python main.py --oauth
```

Sign in as `amish@sscadcam.com` and allow readonly Gmail. Token is saved to `GMAIL_TOKEN_PATH`.

## Run

In DharmaCore **Settings**: enable Email purchase ingest, set poll minutes (default 30), link vendors to suppliers if needed.

```bash
# single cycle (ignores enable flag with --force)
python main.py --once --force -v

# long-running (reads poll interval from PocketBase settings each cycle)
python main.py
```

## systemd (CT 105)

See [docs/GMAIL_PURCHASE_INGEST.md](../../docs/GMAIL_PURCHASE_INGEST.md).

## Vendors

| Key | Status | Domains | Notes |
|-----|--------|---------|-------|
| `mcmaster` | full | mcmaster.com | Materials + mill certs; USD |
| `dgi_supply` | full | **dgisupply.ca**, dgisupply.com | Tools from Cliff conf + AR invoice; CAD; match existing tools in review (no auto-create) |

Enable each vendor under **Settings → Email vendors**. Link a supplier. For DGI, ensure `dgisupply.ca` is in from-domains and apply migration `1776500000_draft_matched_tool_and_dgi_domains.js` (adds `matched_tool` on draft lines).

## Tests

```bash
python -m pytest tests/ -q
# or without pytest:
python tests/test_mcmaster_parser.py
python tests/test_dgi_parser.py
```
