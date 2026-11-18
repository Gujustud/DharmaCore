# Diagnose MCP (Extract from URL) on CT 105 / dharmacore.
# Run in YOUR PowerShell (password prompts). From repo root:
#   .\deploy\ct105_mcp_diagnose.ps1
#
# Use one-line remote SSH commands only (Windows CRLF breaks multi-line bash).
$ErrorActionPreference = 'Stop'
$ct = 'root@192.168.20.101'

Write-Host "Public URL check (from laptop)..." -ForegroundColor Cyan
try {
  $r = curl.exe -sS -o NUL -w "%{http_code}" --max-time 20 "https://dharmacore.sscadcam.com/mcp/"
  Write-Host "  https://dharmacore.sscadcam.com/mcp/  -> HTTP $r"
} catch {
  Write-Host "  Public curl failed: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Inspecting CT 105 via SSH (password each time if no key)..." -ForegroundColor Cyan

Write-Host "`n=== hostname ===" -ForegroundColor Cyan
ssh $ct "hostname"

Write-Host "`n=== systemd units matching mcp / ollama / uvicorn ===" -ForegroundColor Cyan
ssh $ct "systemctl list-units --type=service --all --no-pager 2>/dev/null | grep -iE 'mcp|ollama|uvicorn' || echo '(none matched)'"

Write-Host "`n=== unit files on disk (*mcp*) ===" -ForegroundColor Cyan
ssh $ct "ls -la /etc/systemd/system/*mcp* /lib/systemd/system/*mcp* 2>/dev/null || echo '(no *mcp* unit files)'"

Write-Host "`n=== listeners 8001 / 80 / 443 / 8091 ===" -ForegroundColor Cyan
ssh $ct "ss -tlnp | grep -E ':8001|:80 |:443 |:8091' || echo '(no matches)'"

Write-Host "`n=== /opt listing ===" -ForegroundColor Cyan
ssh $ct "ls -la /opt"

Write-Host "`n=== common MCP dirs ===" -ForegroundColor Cyan
ssh $ct "ls -ld /opt/mcp-server /opt/cribhub-mcp-server /opt/dharmacore/mcp-server /root/mcp-server /root/cribhub-mcp-server 2>/dev/null || echo '(none of the common paths exist)'"

Write-Host "`n=== nginx mcp/8001 references ===" -ForegroundColor Cyan
ssh $ct "grep -RIn --include='*' 'mcp\|8001' /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null || echo '(no mcp/8001 in nginx sites)'"

Write-Host "`n=== local MCP health :8001 ===" -ForegroundColor Cyan
ssh $ct "curl -sS -m 5 http://127.0.0.1:8001/health || echo 'LOCAL :8001/health FAILED'"
ssh $ct "curl -sS -m 5 -o /dev/null -w 'local / -> %{http_code}\n' http://127.0.0.1:8001/ || true"

Write-Host "`n=== journal (common mcp unit names) ===" -ForegroundColor Cyan
ssh $ct "journalctl -u cribhub-mcp -u dharmacore-mcp -u mcp -n 40 --no-pager 2>/dev/null || echo '(no journal for common unit names)'"

Write-Host ""
Write-Host "If :8001 is down: start/install MCP (see DEPLOY_SHOP.md MCP section), then re-run this script." -ForegroundColor Yellow
Write-Host "If :8001 is up but public URL is 502: fix nginx proxy_pass for /mcp." -ForegroundColor Yellow
