# Diagnose MCP (Extract from URL) on CT 105 / dharmacore.
# Run in YOUR PowerShell (password prompts). From repo root:
#   .\deploy\ct105_mcp_diagnose.ps1
#
# Expected healthy state:
#   - something listening on 127.0.0.1:8001 (FastAPI / uvicorn)
#   - nginx location /mcp -> http://127.0.0.1:8001/ (or similar)
#   - curl http://127.0.0.1:8001/health returns JSON
#   - https://dharmacore.sscadcam.com/mcp/ is NOT 502
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
Write-Host "Inspecting CT 105 via SSH..." -ForegroundColor Cyan
ssh $ct @'
set -e
echo "=== hostname ==="
hostname
echo ""
echo "=== systemd units matching mcp / ollama ==="
systemctl list-units --type=service --all --no-pager 2>/dev/null | grep -iE "mcp|ollama|uvicorn" || echo "(none matched)"
echo ""
echo "=== unit files on disk ==="
ls -la /etc/systemd/system/*mcp* 2>/dev/null || echo "(no *mcp* unit files)"
ls -la /lib/systemd/system/*mcp* 2>/dev/null || true
echo ""
echo "=== listeners on 8001 (and common web ports) ==="
ss -tlnp | grep -E ":8001|:80 |:443 |:8091" || echo "(no matches)"
echo ""
echo "=== MCP install dirs (common paths) ==="
for d in /opt/mcp-server /opt/cribhub-mcp-server /opt/dharmacore/mcp-server /root/cribhub-mcp-server /root/mcp-server /home/*/cribhub-mcp-server; do
  if [ -e "$d" ] 2>/dev/null; then ls -ld $d; fi
done
ls -la /opt 2>/dev/null | head -40
echo ""
echo "=== nginx: sites with mcp ==="
grep -RIn --include="*" "mcp\|8001" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null || echo "(no mcp/8001 in nginx sites)"
echo ""
echo "=== local MCP health ==="
curl -sS -m 5 http://127.0.0.1:8001/health || echo "LOCAL :8001/health FAILED"
echo ""
curl -sS -m 5 -o /dev/null -w "local / -> %{http_code}\n" http://127.0.0.1:8001/ || true
echo ""
echo "=== recent journal (mcp* if any) ==="
journalctl -u "cribhub-mcp" -u "dharmacore-mcp" -u "mcp" -n 40 --no-pager 2>/dev/null || echo "(no journal for common unit names)"
'@

Write-Host ""
Write-Host "If :8001 is down: start/install MCP (see DEPLOY_SHOP.md MCP section), then re-run this script." -ForegroundColor Yellow
Write-Host "If :8001 is up but public URL is 502: fix nginx proxy_pass for /mcp." -ForegroundColor Yellow
