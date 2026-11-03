# Apply material_events migrations on CT 105 and verify the collection exists.
# Run from laptop:  powershell -File .\deploy\ct105_material_events.ps1
$ErrorActionPreference = 'Stop'
$ct = 'root@192.168.20.101'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not (Test-Path (Join-Path $repo '.git'))) { $repo = Get-Location }

$files = @(
  '1776800000_material_pieces.js',
  '1776810000_ensure_material_events.js',
  '1776820000_material_events_create.js'
)
foreach ($f in $files) {
  $src = Join-Path $repo "pb_migrations\$f"
  if (-not (Test-Path -LiteralPath $src)) { Write-Error "Missing $src"; exit 1 }
  Write-Host "scp $f ..." -ForegroundColor Cyan
  scp $src "${ct}:/opt/pocketbase-erp-dev/pb_migrations/"
}

# One-line remote commands only (avoid CRLF breaking bash/systemd on the CT).
# Strip Windows CRLF from migrations — PB JSVM can fail to apply CRLF scripts.
Write-Host "Strip CRLF from migrations + restart PocketBase..." -ForegroundColor Cyan
ssh $ct "sed -i 's/\r$//' /opt/pocketbase-erp-dev/pb_migrations/17768*.js && systemctl restart pocketbase-erp-dev && sleep 3 && systemctl is-active pocketbase-erp-dev && curl -sS http://127.0.0.1:8091/api/health"

Write-Host "List migration files on CT..." -ForegroundColor Cyan
ssh $ct "ls -la /opt/pocketbase-erp-dev/pb_migrations/17768*.js"

Write-Host "Recent PocketBase log..." -ForegroundColor Cyan
ssh $ct "journalctl -u pocketbase-erp-dev -n 50 --no-pager"

Write-Host "Check material* collections in data.db..." -ForegroundColor Cyan
ssh $ct "command -v sqlite3 >/dev/null && sqlite3 /opt/pocketbase-erp-dev/pb_data/data.db `"SELECT name FROM _collections WHERE name LIKE 'material%' ORDER BY name;`" || echo 'sqlite3 missing or no data.db'"

Write-Host "Check migration rows 17768*..." -ForegroundColor Cyan
ssh $ct "command -v sqlite3 >/dev/null && sqlite3 /opt/pocketbase-erp-dev/pb_data/data.db `"SELECT file FROM _migrations WHERE file LIKE '17768%' ORDER BY file;`" || echo 'sqlite3 missing or no data.db'"

Write-Host ""
Write-Host "Expect to see material_events in the collections list above." -ForegroundColor Green
Write-Host "Then: .\scripts\build_web_shop.ps1 and deploy shop-web.zip; hard-refresh History." -ForegroundColor Yellow
