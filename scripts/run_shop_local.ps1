# Run the shop app locally (hot reload). Talks to live dharmacore — no zip/scp.
# From repo root:  .\scripts\run_shop_local.ps1
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Get-Location }
Set-Location $repoRoot

$pb = if ($env:CRIBHUB_SHOP_POCKETBASE_URL) { $env:CRIBHUB_SHOP_POCKETBASE_URL } else { 'https://dharmacore.sscadcam.com/' }
$mcp = if ($env:CRIBHUB_SHOP_MCP_URL) { $env:CRIBHUB_SHOP_MCP_URL } else { 'https://dharmacore.sscadcam.com/mcp' }

# Prefer Windows (no browser CORS). Fall back to Chrome.
$device = 'windows'
$devices = flutter devices 2>&1 | Out-String
if ($devices -notmatch '(?i)windows') {
  $device = 'chrome'
}

Write-Host "Starting shop app on $device → $pb" -ForegroundColor Cyan
Write-Host "Hot reload: press r   Hot restart: press R   Quit: press q" -ForegroundColor Yellow
flutter run -d $device `
  --dart-define=POCKETBASE_URL=$pb `
  --dart-define=MCP_URL=$mcp
