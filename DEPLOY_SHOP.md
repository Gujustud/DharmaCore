# Live shop deployment (CT 105 / dharmacore)

Deploy the **Flutter web** app to the **live shop** Proxmox LXC.

| | |
|------|--------|
| **URL** | `https://dharmacore.sscadcam.com/` |
| **CT** | **105** · LAN `192.168.20.101` |
| **SSH** | `root@192.168.20.101` (password in your terminal; no deploy key on the laptop yet) |
| **Web root** | `/opt/pocketbase-erp-dev/pb_public/` |
| **Laptop zip** | `deploy\shop-web.zip` |

This is **not** CribHub (`DEPLOY.md` → CT 101 / `cribhub.sscadcam.com`) and **not** erp-dev on `.104` (`DEPLOY_ERP.md`).  
Same `pb_public` path name as erp-dev, but the host is **CT 105**.

---

## Copying commands

Indented lines (no backticks) copy cleanly into PowerShell / bash.

---

## Quick path (usual)

### 1. Build + zip (laptop)

    cd c:\cribhub
    .\scripts\build_web_shop.ps1

Bakes in `https://dharmacore.sscadcam.com/` and writes **`deploy\shop-web.zip`**.  
The script prints the two deploy lines when it finishes.

### 2. Copy + install (your PowerShell — type the password when asked)

Run these **on the Windows laptop**, not inside the CT:

    scp c:\cribhub\deploy\shop-web.zip root@192.168.20.101:/root/
    ssh root@192.168.20.101 "rm -rf /opt/pocketbase-erp-dev/pb_public/* && unzip -o /root/shop-web.zip -d /opt/pocketbase-erp-dev/pb_public/ && ls /opt/pocketbase-erp-dev/pb_public/index.html /opt/pocketbase-erp-dev/pb_public/main.dart.js"

You must see **`index.html`** and **`main.dart.js`** directly under `pb_public/` (not under `pb_public/web/`).

### 3. Browser

Hard refresh or **clear site data** for `https://dharmacore.sscadcam.com/` (Flutter service worker caches old `main.dart.js`).

Static-only deploy: no PocketBase restart needed.

### Schema / migrations (when `pb_migrations/` changed)

Live shop PocketBase on CT **105** uses the unit/path named **`pocketbase-erp-dev`** (leftover name from cutover; this **is** live `dharmacore`). Work as **`root@dharmacore`** (or `ssh root@192.168.20.101`), not on the Proxmox host.

Copy the new `.js` file from the laptop, then on CT 105 restart and **verify health before anything else**:

    scp c:\cribhub\pb_migrations\1775300000_maintenance_records.js root@192.168.20.101:/opt/pocketbase-erp-dev/pb_migrations/

On `root@dharmacore`:

    systemctl restart pocketbase-erp-dev
    sleep 2
    systemctl is-active pocketbase-erp-dev
    curl -sS http://127.0.0.1:8091/api/health

Must print `active` and healthy JSON. If it crash-loops again, `systemctl stop`, move the bad `.js` out of `pb_migrations/`, start, then fix the file.

---

## MCP server (Extract from URL / tool import)

Shop web builds call **`https://dharmacore.sscadcam.com/mcp`** (see `scripts/build_web_shop.ps1`).  
That path must reverse-proxy to a FastAPI process on CT 105 (usually **`127.0.0.1:8001`**, code in repo `mcp-server/`).

**Symptom if MCP is down:** app toast like `Unexpected token '<' … is not valid JSON`, or browser/`curl` → **`502 Bad Gateway`** on `/mcp/`. Nginx is up; upstream on **8001** is not.

### Diagnose (laptop PowerShell)

    cd c:\cribhub
    .\deploy\ct105_mcp_diagnose.ps1

Or one-shot public check:

    curl.exe https://dharmacore.sscadcam.com/mcp/

### On CT 105 — what to look for

    systemctl list-units --type=service --all | grep -iE 'mcp|ollama'
    ss -tlnp | grep 8001
    grep -RIn 'mcp\|8001' /etc/nginx/sites-enabled /etc/nginx/conf.d
    curl -sS http://127.0.0.1:8001/health

**Nginx** should have something like (exact file name varies — often the dharmacore / pocketbase site):

    location /mcp/ {
        proxy_pass http://127.0.0.1:8001/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }

Trailing slashes matter: `/mcp/` → `http://127.0.0.1:8001/` strips the `/mcp` prefix so FastAPI sees `/api/extract-page-images`.

**systemd** example (adjust paths after you place `mcp-server/` on the CT):

    # /etc/systemd/system/dharmacore-mcp.service
    [Unit]
    Description=DharmaCore MCP (tool import / page images)
    After=network.target

    [Service]
    Type=simple
    WorkingDirectory=/opt/dharmacore/mcp-server
    ExecStart=/opt/dharmacore/mcp-server/.venv/bin/uvicorn mcp_server:app --host 127.0.0.1 --port 8001
    Restart=always
    RestartSec=5

    [Install]
    WantedBy=multi-user.target

Ollama is only required for **Import specs** (LLM). **Extract from URL** (page images) needs FastAPI + httpx + BeautifulSoup only.

After fixing: `curl.exe https://dharmacore.sscadcam.com/mcp/health` should return JSON, then retry Extract from URL in the app.

---

## Why Cursor / the agent can’t finish step 2 alone

`scp`/`ssh` to CT 105 need a **password** (or an SSH key). Non-interactive agent shells can’t type that password (`BatchMode` → permission denied; interactive `scp` hangs).

**Fix for next time (optional):** put a laptop SSH public key in CT 105 `root` `authorized_keys`, then agents can run the same two lines without you.

Until then: agent builds the zip → **you** run the two PowerShell lines.

---

## Fallback — HTTP pull from the CT

If `scp` is awkward, on the laptop:

    cd c:\cribhub\deploy
    python -m http.server 8888

On the CT (console / SSH):

    cd ~
    curl -fLO http://192.168.1.192:8888/shop-web.zip
    rm -rf /opt/pocketbase-erp-dev/pb_public/*
    unzip -o ~/shop-web.zip -d /opt/pocketbase-erp-dev/pb_public/

Replace `192.168.1.192` with the laptop’s current LAN IP (`ipconfig`).

---

## Android APK (tablet)

Shop tablet builds must use **dharmacore** URLs (not `buildapk.bat`, which still targets cribhub):

    cd c:\cribhub
    .\scripts\buildapk_shop.bat

Output: `build\app\outputs\flutter-apk\app-release.apk`

The script refreshes `lib\git_info.dart` first. After install, **About** shows Version, Built date, branch, and commit so you know which APK is on the tablet.

Application ID is `com.sscadcam.dharmacore`. Uninstall any old `com.example.cribhub` build before sideloading so Bitwarden / autofill see the new package.

---

## Related

| Doc / script | Use for |
|--------------|---------|
| `SHOP_NEXT.md` | Living shop checklist |
| `.\scripts\build_web_shop.ps1` | Live shop web build + zip |
| `.\scripts\buildapk_shop.bat` | Live shop Android APK |
| `.\deploy\ct105_mcp_diagnose.ps1` | MCP / Extract-from-URL 502 diagnose on CT 105 |
| `mcp-server/` | FastAPI MCP (images + tool import) |
| `DEPLOY.md` | Old CribHub production |
| `DEPLOY_ERP.md` | erp-dev CT **103** (`.104`) |
