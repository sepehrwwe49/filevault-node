#!/usr/bin/env python3
"""Render the nginx stream (SNI) map.

Raw passthrough for Reality SNIs, everything else to the local TLS website
server. Listens on every TLS port Cloudflare may hit (443 plus 2053, 2083,
2087, 2096, 8443 ... whichever this node uses)."""
import sys, os

tpl_path, out_path, local_tls = sys.argv[1:4]
tls_ports = sys.argv[4] if len(sys.argv) > 4 else "443"
reality_map = os.environ.get("REALITY_MAP", "").rstrip("\n")

lines = []
for i, p in enumerate([x.strip() for x in tls_ports.split(",") if x.strip()]):
    r = " reuseport" if i == 0 else ""
    lines.append(f"    listen {p}{r};")
    lines.append(f"    listen [::]:{p}{r};")

tpl = open(tpl_path, encoding="utf-8").read()
tpl = (tpl.replace("__LOCAL_TLS_PORT__", local_tls)
          .replace("__REALITY_MAP__", reality_map)
          .replace("__STREAM_LISTEN__", "\n".join(lines)))
open(out_path, "w", encoding="utf-8").write(tpl)
print("[render] stream map written  tls ports=" + tls_ports)
