# DharmaCore – Deploy on Proxmox (step-by-step)

This guide deploys DharmaCore on a **Proxmox VM**: Nginx serves the React app and proxies the API to PocketBase. Optional HTTPS with Let’s Encrypt.

---

## Overview

| Component   | Role |
|------------|------|
| **VM** (Ubuntu 22.04) | Single server for app + API |
| **Nginx** | Serves static frontend, proxies `/api` to PocketBase |
| **PocketBase** | API + SQLite + migrations, runs as systemd service |
| **Frontend** | Built with Vite; `VITE_POCKETBASE_URL` points at your public API base |

Traffic: **Browser → Nginx (80/443) → (static files **or** `/api/*` → PocketBase :8090)**.

---

## Step 1 – Create a VM on Proxmox

1. In Proxmox: **Create VM**.
2. **OS**: Use an Ubuntu 22.04 LTS ISO (or Debian 12).
3. **System**: Defaults; enable QEMU Agent if you use it.
4. **Disks**: e.g. 20–32 GB.
5. **CPU / RAM**: 2 vCPU, 2 GB RAM is enough to start.
6. **Network**: Bridge (e.g. `vmbr0`), DHCP or static as you prefer.
7. Finish and **Start** the VM; complete the OS install (user, SSH, etc.).

---

## Step 2 – First login and system prep

SSH into the VM (replace with your IP/host and user):

```bash
ssh your-user@<VM_IP>
```

Update and install basics:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl nginx
```

(Optional) Set a hostname:

```bash
sudo hostnamectl set-hostname dharmacore
```

---

## Step 3 – Install Node.js (for building the frontend)

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v   # e.g. v20.x
```

---

## Step 4 – Install PocketBase (Linux)

Pick a directory for the app (e.g. `/opt/dharmacore`):

```bash
sudo mkdir -p /opt/dharmacore
sudo chown "$USER:$USER" /opt/dharmacore
cd /opt/dharmacore
```

Download PocketBase Linux binary (use latest from [releases](https://github.com/pocketbase/pocketbase/releases)):

```bash
# Example (check site for latest version and exact filename):
cd /opt/dharmacore
curl -sL -o pb.zip "https://github.com/pocketbase/pocketbase/releases/download/v0.22.0/pocketbase_0.22.0_linux_amd64.zip"
unzip -o pb.zip
chmod +x pocketbase
mv pocketbase pb
rm pb.zip
```

Create placeholders for backend (you’ll replace with your repo contents):

```bash
mkdir -p backend/pb_migrations
mkdir -p backend/pb_data
```

---

## Step 5 – Clone the repo and copy migrations


On the **server**, clone the public repo (no login required). Repo: **https://github.com/Gujustud/DharmaCore**

Install git if needed: `sudo apt install -y git`

**First-time clone and copy migrations:**

```bash
cd /opt/dharmacore
git clone https://github.com/Gujustud/DharmaCore.git repo
mkdir -p /opt/dharmacore/pb_migrations
cp -r repo/backend/pb_migrations/* /opt/dharmacore/pb_migrations/
```

PocketBase expects `pb_migrations` next to the `pb` binary. Build frontend from `repo/frontend` in Step 8.



---

## Step 6 – Run PocketBase once (create admin + run migrations)

From the directory that contains the `pb` binary **and** the `pb_migrations` folder (PocketBase expects `./pb_migrations` next to the binary):

```bash
cd /opt/dharmacore
# If your binary is in backend:  cd /opt/dharmacore/backend
./pb serve
```

- First run will create `pb_data` (SQLite + storage) and apply migrations.
- In another terminal (or from your PC using port-forward) open `http://<VM_IP>:8090/_/` and create the **first admin user** (email + password). This is the PocketBase admin; you can also use it to log into DharmaCore if you use the same user in the app’s `users` collection.
- Stop PocketBase with `Ctrl+C` once admin is created and migrations are done.

If you keep the binary in `/opt/dharmacore` and migrations in `/opt/dharmacore/backend/pb_migrations`, either:

- Copy `pb_migrations` next to `pb`, or  
- Run with explicit paths if your PocketBase version supports it; otherwise standard is:

  - Binary: `/opt/dharmacore/pb`
  - Same directory: `pb_migrations/` and `pb_data/`

So a common layout is:

```text
/opt/dharmacore/
  pb
  pb_migrations/   <- copy from repo backend/pb_migrations
  pb_data/        <- created by PocketBase
```

Adjust the paths in the next steps if you use something like `/opt/dharmacore/backend/`.

---

## Step 7 – Create a systemd service for PocketBase

So PocketBase starts on boot and restarts on failure:

```bash
sudo nano /etc/systemd/system/pocketbase.service
```

Paste (adjust paths if your binary or working dir is different):

```ini
[Unit]
Description=PocketBase API for DharmaCore
After=network.target

[Service]
Type=simple
User=YOUR_USER
Group=YOUR_USER
WorkingDirectory=/opt/dharmacore
ExecStart=/opt/dharmacore/pb serve --http=127.0.0.1:8090
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Replace `YOUR_USER` with the user that owns `/opt/dharmacore` (e.g. `ubuntu` or your SSH user).

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable pocketbase
sudo systemctl start pocketbase
sudo systemctl status pocketbase
```

PocketBase should be listening on `127.0.0.1:8090` only (Nginx will proxy to it).

---

## Step 8 – Build the frontend (on the server)

On the server you need the frontend source and a build with the **production** API URL.

**If you cloned the repo:**

```bash
cd /opt/dharmacore/repo/frontend
```

**If you copied only the backend:** copy the whole `frontend` folder (with `package.json`, `src`, etc.) to the server, then:

```bash
cd /opt/dharmacore/frontend   # or wherever you put it
```

Set the public API URL (replace with your real domain or VM IP; if you use HTTPS later, use the same URL here):

```bash
# Use your actual domain or IP. Example with domain:
echo 'VITE_POCKETBASE_URL=https://your-domain.com/api' > .env.production

# Or with IP (for testing):
echo 'VITE_POCKETBASE_URL=http://YOUR_VM_IP/api' > .env.production
```

Install and build:

```bash
npm ci
npm run build
```

This creates `frontend/dist`. We’ll point Nginx at that folder.

---

## Step 9 – Configure Nginx

Create a site config (replace `your-domain.com` or use your VM IP for testing):

```bash
sudo nano /etc/nginx/sites-available/dharmacore
```

Paste (replace `your-domain.com` and `/opt/dharmacore` paths if different):

```nginx
server {
    listen 80;
    server_name your-domain.com;   # or _ for default / IP

    root /opt/dharmacore/repo/frontend/dist;   # or /opt/dharmacore/frontend/dist
    index index.html;

    # Frontend (SPA)
    location / {
        try_files $uri $uri/ /index.html;
    }

    # PocketBase API
    location /api/ {
        proxy_pass http://127.0.0.1:8090/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Important: `proxy_pass http://127.0.0.1:8090/` with trailing slash so that `/api/xxx` becomes `http://127.0.0.1:8090/xxx` (PocketBase expects paths like `/api/collections/...` on the client, and Nginx strips `/api` and forwards the rest).

Actually: the frontend is configured with `VITE_POCKETBASE_URL=https://your-domain.com/api`. So the client will call `https://your-domain.com/api/collections/...`. Nginx receives `/api/collections/...` and should proxy to `http://127.0.0.1:8090/collections/...`. So `proxy_pass http://127.0.0.1:8090/` is correct (the `/api` prefix is stripped).

Enable the site and reload Nginx:

```bash
sudo ln -s /etc/nginx/sites-available/dharmacore /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

Open `http://your-domain.com` (or `http://YOUR_VM_IP`). You should see the app and be able to log in (create a user in PocketBase admin if needed: `http://YOUR_VM_IP:8090/_/` - but only if you temporarily allow port 8090 or use SSH tunnel).

---

## Step 10 – (Optional) HTTPS with Let’s Encrypt

If you have a real domain pointing to the VM:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

Follow the prompts. Certbot will adjust the Nginx config for HTTPS. Then ensure your `.env.production` and app use `https://your-domain.com/api` and reload Nginx if needed.

---

## Step 11 – Firewall (optional but recommended)

Allow HTTP/HTTPS and SSH; block direct access to PocketBase from the internet:

```bash
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw enable
```

Do **not** open port 8090 publicly; Nginx proxies to it on localhost.

---

## Updates (after code changes) â€” the only way we update the app

Do this on the **Proxmox server** every time you want to deploy the latest code. The repo is public (https://github.com/Gujustud/DharmaCore), so no git login is needed.

1. **SSH into the server**
   ```bash
   ssh your-user@<VM_IP>
   ```

2. **Pull latest code**
   ```bash
   cd /opt/dharmacore/repo
   git pull
   ```

3. **Copy new migrations** (so PocketBase sees them next to the `pb` binary)
   ```bash
   cp -r backend/pb_migrations/* /opt/dharmacore/pb_migrations/
   ```

4. **Rebuild the frontend**
   ```bash
   cd frontend
   npm ci && npm run build
   ```

5. **Restart PocketBase**
   ```bash
   sudo systemctl restart pocketbase
   ```

6. **Reload Nginx** only if you changed the site config; otherwise skip.
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

Done. The app is updated. No copying from your PC and no zip files â€” only this server-side flow.

---

## Quick reference – paths

| Item            | Path (example) |
|-----------------|----------------|
| App root        | `/opt/dharmacore` |
| PocketBase binary | `/opt/dharmacore/pb` |
| Migrations      | `/opt/dharmacore/pb_migrations` |
| Data + storage  | `/opt/dharmacore/pb_data` |
| Frontend build  | `/opt/dharmacore/repo/frontend/dist` (or `frontend/dist`) |
| Nginx config    | `/etc/nginx/sites-available/dharmacore` |
| systemd unit    | `/etc/systemd/system/pocketbase.service` |

---

## Troubleshooting

- **502 Bad Gateway** – PocketBase not running: `sudo systemctl status pocketbase` and `journalctl -u pocketbase -f`.
- **Blank app / wrong API** – Rebuild frontend with correct `VITE_POCKETBASE_URL` (must match the URL the browser uses, including `/api`).
- **Migrations** – Ensure `pb_migrations` is next to the `pb` binary (or as required by your PocketBase layout) and that the service restarts after adding new migrations.

If you tell me your exact domain and whether you use a separate backend folder or a single `/opt/dharmacore` tree, I can adapt paths and the Nginx `root` for you.
