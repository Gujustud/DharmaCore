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

Uninstall the old app on the tablet before sideloading if auth/cache looks stale.

---

## Related

| Doc / script | Use for |
|--------------|---------|
| `SHOP_NEXT.md` | Living shop checklist |
| `.\scripts\build_web_shop.ps1` | Live shop web build + zip |
| `.\scripts\buildapk_shop.bat` | Live shop Android APK |
| `DEPLOY.md` | Old CribHub production |
| `DEPLOY_ERP.md` | erp-dev CT **103** (`.104`) |
