#!/usr/bin/env python3
"""Render nginx stream (SNI) map: raw passthrough for Reality SNIs, everything else
to the local TLS website server."""
import sys, os
tpl_path, out_path, local_tls = sys.argv[1:4]
reality_map = os.environ.get("REALITY_MAP", "").rstrip("\n")
tpl = open(tpl_path, encoding="utf-8").read()
tpl = tpl.replace("__LOCAL_TLS_PORT__", local_tls).replace("__REALITY_MAP__", reality_map)
open(out_path, "w", encoding="utf-8").write(tpl)
print("[render] stream map written")
