# Deploy Inspection calibration migration + shop web to CT 105.
# Run in YOUR PowerShell (password prompts). From repo root:
#   git pull
#   .\scripts\build_web_shop.ps1
#   .\deploy\ct105_calibration.ps1
$ErrorActionPreference = 'Stop'
$ct = 'root@192.168.20.101'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not (Test-Path (Join-Path $repo '.git'))) { $repo = (Get-Location).Path }

$zip = Join-Path $repo 'deploy\shop-web.zip'
$mig = Join-Path $repo 'pb_migrations\1777000000_calibration_schedules_and_records.js'
if (-not (Test-Path -LiteralPath $zip)) {
  throw "Missing $zip - run .\scripts\build_web_shop.ps1 first"
}
if (-not (Test-Path -LiteralPath $mig)) { throw "Missing $mig" }

Write-Host "Copying shop-web.zip + calibration migration..." -ForegroundColor Cyan
scp $zip "${ct}:/root/"
scp $mig "${ct}:/opt/pocketbase-erp-dev/pb_migrations/"

# Remote bash via single-quoted here-string so PowerShell does not parse &&.
Write-Host "Installing web + applying migration + restarting PocketBase..." -ForegroundColor Cyan
ssh $ct @'
sed -i 's/\r$//' /opt/pocketbase-erp-dev/pb_migrations/1777000000_calibration_schedules_and_records.js && rm -rf /opt/pocketbase-erp-dev/pb_public/* && unzip -o /root/shop-web.zip -d /opt/pocketbase-erp-dev/pb_public/ && ls /opt/pocketbase-erp-dev/pb_public/index.html /opt/pocketbase-erp-dev/pb_public/main.dart.js && systemctl restart pocketbase-erp-dev && sleep 3 && systemctl is-active pocketbase-erp-dev && curl -sS http://127.0.0.1:8091/api/health
'@

Write-Host "Confirm calibration collections..." -ForegroundColor Cyan
ssh $ct 'echo SELECT name FROM _collections | sqlite3 /opt/pocketbase-erp-dev/pb_data/data.db | grep calibration'
ssh $ct 'echo SELECT file FROM _migrations | sqlite3 /opt/pocketbase-erp-dev/pb_data/data.db | grep 1777000000'

Write-Host ""
Write-Host "Done. Hard-refresh https://dharmacore.sscadcam.com/ (or clear site data)." -ForegroundColor Green
Write-Host "Then open Inventory -> Inspection and tap a tool for the calibration panel." -ForegroundColor Yellow
