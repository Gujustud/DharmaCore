#!/usr/bin/env python3
"""Fix dharmacore nginx /mcp so FastAPI sees /api/... not /mcp/api/..."""
from pathlib import Path

p = Path("/etc/nginx/sites-enabled/dharmacore")
if not p.exists():
    raise SystemExit(f"missing {p}")

text = p.read_text()
bak = Path("/etc/nginx/sites-enabled/dharmacore.bak-mcp")
if not bak.exists():
    bak.write_text(text)
    print(f"backup -> {bak}")

new_block = """    location /mcp/ {
        proxy_pass http://127.0.0.1:8001/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 360s;
    }
"""

# Already correct?
if (
    "location /mcp/" in text
    and "proxy_pass http://127.0.0.1:8001/;" in text
    and "proxy_read_timeout 360s;" in text
):
    print("nginx /mcp/ already looks correct")
    raise SystemExit(0)

import re

pattern = re.compile(
    r"    location /mcp\s*\{[^}]*proxy_pass http://127\.0\.0\.1:8001;[^}]*\}",
    re.DOTALL,
)
m = pattern.search(text)
if m:
    text2 = text[: m.start()] + new_block.rstrip() + text[m.end() :]
    p.write_text(text2)
    print("replaced location /mcp block with /mcp/ prefix-strip block")
    raise SystemExit(0)

# Broader: replace any location /mcp { ... } that proxies to 8001
pattern2 = re.compile(
    r"    location /mcp/?\s*\{.*?\}",
    re.DOTALL,
)
m2 = None
for m2 in pattern2.finditer(text):
    if "8001" in m2.group(0):
        text2 = text[: m2.start()] + new_block.rstrip() + text[m2.end() :]
        p.write_text(text2)
        print("replaced mcp location block (broad match)")
        raise SystemExit(0)

raise SystemExit("could not find location /mcp ... 8001 block to replace")
