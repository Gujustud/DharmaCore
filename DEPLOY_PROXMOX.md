# Deploy to Proxmox (from your laptop)

Use this when you’ve updated the app on your laptop and want to put the new version on the Proxmox server. No git on the server — you build locally, zip, then upload.

---

## Prerequisites

- Frontend is built with the right API URL. In `frontend/.env.production` you should have:
  ```env
  VITE_POCKETBASE_URL=https://dharmacore.sscadcam.com/api
  ```
- Your laptop and the Proxmox server can reach each other on your network (e.g. same LAN).

---

## Step 1 – Build the frontend (on your laptop)

In PowerShell (or terminal) at the project root:

```powershell
cd c:\DharmaCore\frontend
npm run build
```

This creates/updates `c:\DharmaCore\frontend\dist` (the files Nginx will serve).

---

## Step 2 – Create the zip files (on your laptop)

Still from `c:\DharmaCore` (project root):

**Frontend (only the build output):**

```powershell
Compress-Archive -Path frontend\dist -DestinationPath deploy\dist.zip -Force
```

**Migrations (only if you changed backend/migrations):**

```powershell
Compress-Archive -Path backend\pb_migrations\* -DestinationPath deploy\pb_migrations.zip -Force
```

- If the `deploy` folder doesn’t exist, create it first: `mkdir deploy`
- You can skip `pb_migrations.zip` if you didn’t add or change any migrations.

---

## Step 3 – Serve the deploy folder from your laptop

In a **new** PowerShell window:

```powershell
cd c:\DharmaCore\deploy
python -m http.server 8888
```

Leave this running. Your laptop’s IP (e.g. `192.168.1.247`) must be reachable from the server. Note your laptop IP (run `ipconfig` and use the IPv4 address of your LAN adapter).

---

## Step 4 – On the Proxmox server: download and unzip

SSH into the server, then:

**4a. Download the zips** (replace `YOUR_LAPTOP_IP` with your laptop’s IP, e.g. `192.168.1.247`):

```bash
cd /opt/dharmacore
curl -O http://YOUR_LAPTOP_IP:8888/dist.zip
curl -O http://YOUR_LAPTOP_IP:8888/pb_migrations.zip
```

**4b. Deploy the frontend**

Nginx expects the built app at `/opt/dharmacore/repo/frontend/dist` (that directory must contain `index.html` and `assets/`). Unzip so that the `dist` folder ends up inside `repo/frontend/`:

```bash
cd /opt/dharmacore/repo/frontend
unzip -o /opt/dharmacore/dist.zip
```

This should create/overwrite `dist/index.html` and `dist/assets/` under `repo/frontend/`.

**4c. Deploy migrations** (only if you updated and uploaded `pb_migrations.zip`)

PocketBase expects the `.js` migration files **directly** in `/opt/dharmacore/pb_migrations/` (next to the `pb` binary). Unzip into that folder:

```bash
cd /opt/dharmacore/pb_migrations
unzip -o /opt/dharmacore/pb_migrations.zip
```

**4d. Restart PocketBase** (only if you deployed new migrations)

```bash
sudo systemctl restart pocketbase
```

**4e. Clean up the zips** (optional)

```bash
rm /opt/dharmacore/dist.zip /opt/dharmacore/pb_migrations.zip
```

---

## Step 5 – Stop the Python server on your laptop

In the PowerShell window where `python -m http.server 8888` is running, press **Ctrl+C**.

---

## Done

Open **https://dharmacore.sscadcam.com** and confirm the app and data load correctly.

---

## Quick reference

| Where | What |
|-------|------|
| Laptop | Build in `frontend/`, zips go in `deploy/` |
| Server frontend | `/opt/dharmacore/repo/frontend/dist` must contain `index.html` and `assets/` |
| Server migrations | `/opt/dharmacore/pb_migrations/` must contain the `*.js` migration files |
| Do **not** overwrite | `/opt/dharmacore/pb_data/` or the `pb` binary |
