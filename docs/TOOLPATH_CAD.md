# Toolpath CAD analysis (Phase B)

Quote lines can upload CAD (Phase A) and optionally run **Toolpath** analysis for bounding box + feature summary. Hours and price stay manual.

## Architecture

- Flutter web → `POST {MCP_URL}/api/toolpath/analyze` with filename + base64 bytes
- MCP server (`mcp-server/mcp_server.py`) holds `TOOLPATH_API_KEY` and talks to `https://api.toolpath.com/v1`
- Results stored on `quote_line_items.cad_analysis` (JSON text)
- **Stock suggest:** bounding box (inches) + `0.1"` pad, each axis rounded **up** to the next `0.5"`, then ordered **thickness × width × length** (small → large) so Find on shelf treats the last number as cut length (override with `TOOLPATH_STOCK_PAD_IN` / `TOOLPATH_STOCK_STEP_IN` on the MCP host)
- **3D preview (Phase 3):** Flutter `<model-viewer>` loads `GET {MCP_URL}/api/toolpath/parts/{toolpath_part_id}/mesh.glb`. MCP proxies Toolpath (analysis GLB when still hot, else `POST/GET /v1/parts/{id}/mesh` tessellation) and caches bytes briefly (`TOOLPATH_MESH_CACHE_TTL_S`, default 600). Toolpath parts expire (~retention window) — Re-analyze if the viewer 410s.
- **Fixture bottom:** Click a face in the 3D preview (`positionAndNormalFromPoint` with viewport `clientX/Y` — model-viewer 4.x subtracts the element rect itself) to set `bottom_direction` from the surface normal (hotspot marks the pick). Optional setup chips remain as shortcuts. Stock extents are measured in the fixture frame, then padded/ceiled and sorted **small → large** (same as AABB). Clear bottom restores AABB stock. Changing bottom refreshes applied stock when it matched the previous suggest. The model is not reoriented on pick. Default part tint is charcoal.

## CT 105 setup

1. Create a Toolpath Engine API key (Core write + DFM write). Prefer **no browser origins** (server-only).
2. On the CT:

```bash
sudo mkdir -p /etc/dharmacore
sudo tee /etc/dharmacore/toolpath.env >/dev/null <<'EOF'
TOOLPATH_API_KEY=tp_your_key_here
EOF
sudo chmod 600 /etc/dharmacore/toolpath.env
```

3. Redeploy MCP so the unit picks up `EnvironmentFile` (see `deploy/dharmacore-mcp.service`):

```powershell
cd c:\cribhub
git pull
.\deploy\ct105_mcp_install.ps1
```

4. Apply PocketBase migration `1777120000_quote_line_cad_analysis.js` and restart PocketBase (same as other shop migrations).
5. Deploy shop web so the CAD section shows Analyze / bbox UI.

## Health

```bash
curl -sS http://127.0.0.1:8001/api/toolpath/status
curl -sS https://dharmacore.sscadcam.com/mcp/api/toolpath/status
```

Expect `{"configured":true}` when the key is loaded.

Nginx `/mcp/` `proxy_read_timeout` should be **360s** (analysis can take several minutes).
