# Install / start MCP on CT 105 so Extract from URL works.
# Run in YOUR PowerShell (password prompts). From repo root:
#   .\deploy\ct105_mcp_install.ps1
#
# One-line remote SSH only. Prefer single-quoted remote args so PowerShell
# does not parse bash || / && / quotes.
$ErrorActionPreference = 'Stop'
$ct = 'root@192.168.20.101'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not (Test-Path (Join-Path $repo '.git'))) { $repo = (Get-Location).Path }

$mcpPy = Join-Path $repo 'mcp-server\mcp_server.py'
$mcpReq = Join-Path $repo 'mcp-server\requirements.txt'
$unit = Join-Path $repo 'deploy\dharmacore-mcp.service'
$nginxFix = Join-Path $repo 'deploy\ct105_fix_nginx_mcp.py'
foreach ($p in @($mcpPy, $mcpReq, $unit, $nginxFix)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing $p" }
}

$remoteDir = '/opt/dharmacore/mcp-server'

Write-Host "Creating $remoteDir on CT..." -ForegroundColor Cyan
ssh $ct "mkdir -p $remoteDir"

Write-Host "Copying MCP files..." -ForegroundColor Cyan
scp $mcpPy "${ct}:${remoteDir}/mcp_server.py"
scp $mcpReq "${ct}:${remoteDir}/requirements.txt"
scp $unit "${ct}:/etc/systemd/system/dharmacore-mcp.service"
scp $nginxFix "${ct}:/tmp/ct105_fix_nginx_mcp.py"

Write-Host "Strip CRLF from copied files..." -ForegroundColor Cyan
ssh $ct 'sed -i "s/\r$//" /opt/dharmacore/mcp-server/mcp_server.py /opt/dharmacore/mcp-server/requirements.txt /etc/systemd/system/dharmacore-mcp.service /tmp/ct105_fix_nginx_mcp.py'

Write-Host "Create venv + pip install (may take a minute)..." -ForegroundColor Cyan
ssh $ct 'rm -rf /opt/dharmacore/mcp-server/.venv; python3 -m venv /opt/dharmacore/mcp-server/.venv; /opt/dharmacore/mcp-server/.venv/bin/pip install --upgrade pip; /opt/dharmacore/mcp-server/.venv/bin/pip install -r /opt/dharmacore/mcp-server/requirements.txt'
if ($LASTEXITCODE -ne 0) {
  throw "pip install failed on CT (exit $LASTEXITCODE). See errors above."
}

Write-Host "Fix nginx /mcp proxy (strip /mcp prefix for FastAPI)..." -ForegroundColor Cyan
ssh $ct 'python3 /tmp/ct105_fix_nginx_mcp.py'
if ($LASTEXITCODE -ne 0) { throw 'nginx mcp fix failed' }
ssh $ct 'nginx -t; systemctl reload nginx'
if ($LASTEXITCODE -ne 0) { throw 'nginx reload failed' }

Write-Host "Enable + start dharmacore-mcp..." -ForegroundColor Cyan
ssh $ct 'systemctl daemon-reload; systemctl enable --now dharmacore-mcp; sleep 2; systemctl is-active dharmacore-mcp'
if ($LASTEXITCODE -ne 0) {
  Write-Host 'Service not active - recent logs:' -ForegroundColor Yellow
  ssh $ct 'journalctl -u dharmacore-mcp -n 40 --no-pager'
  throw 'dharmacore-mcp failed to start'
}

Write-Host 'Local health...' -ForegroundColor Cyan
ssh $ct 'curl -sS -m 5 http://127.0.0.1:8001/health; echo'
ssh $ct 'ss -tlnp | grep 8001'
if ($LASTEXITCODE -ne 0) {
  Write-Host '8001 not listening' -ForegroundColor Yellow
}

Write-Host 'Public health...' -ForegroundColor Cyan
try {
  curl.exe -sS -m 20 'https://dharmacore.sscadcam.com/mcp/health'
  Write-Host ''
  $code = curl.exe -sS -o NUL -w '%{http_code}' -m 20 'https://dharmacore.sscadcam.com/mcp/health'
  Write-Host "public /mcp/health -> HTTP $code"
} catch {
  Write-Host "Public curl failed: $_" -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Done. Hard-refresh the app and retry Extract from URL.' -ForegroundColor Green
Write-Host 'Logs: ssh root@192.168.20.101 journalctl -u dharmacore-mcp -n 80 --no-pager' -ForegroundColor Yellow
