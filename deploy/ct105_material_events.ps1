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

Write-Host "Restart PocketBase + verify..." -ForegroundColor Cyan
ssh $ct @'
set -e
ls -la /opt/pocketbase-erp-dev/pb_migrations/17768*.js
systemctl restart pocketbase-erp-dev
sleep 3
systemctl is-active pocketbase-erp-dev
curl -sS http://127.0.0.1:8091/api/health
echo ""
echo "=== recent pocketbase log (migrations) ==="
journalctl -u pocketbase-erp-dev -n 40 --no-pager | tail -40
echo ""
echo "=== collections named material* ==="
DB=$(ls /opt/pocketbase-erp-dev/pb_data/*.db 2>/dev/null | head -1)
echo "DB=$DB"
if command -v sqlite3 >/dev/null 2>&1 && [ -n "$DB" ]; then
  sqlite3 "$DB" "SELECT name FROM _collections WHERE name LIKE 'material%' ORDER BY name;"
  echo "=== migrations 17768* ==="
  sqlite3 "$DB" "SELECT file, applied FROM _migrations WHERE file LIKE '17768%' ORDER BY file;"
else
  echo "sqlite3 not installed — skip DB check"
fi
'@

Write-Host ""
Write-Host "If material_events is listed above, hard-refresh DharmaCore and reopen History." -ForegroundColor Green
Write-Host "Then deploy latest web (for clearer errors): .\scripts\build_web_shop.ps1 + scp/unzip as usual." -ForegroundColor Yellow
