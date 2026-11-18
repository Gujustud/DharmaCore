#!/usr/bin/env python3
"""Strip CR/CRLF from files listed on argv (safe; does not delete letter r)."""
import sys
from pathlib import Path

for raw in sys.argv[1:]:
    p = Path(raw)
    data = p.read_bytes()
    cleaned = data.replace(b"\r\n", b"\n").replace(b"\r", b"")
    if cleaned != data:
        p.write_bytes(cleaned)
        print(f"stripped CRLF: {p}")
    else:
        print(f"ok (no CR): {p}")
