"""
Render the nginx vhost from the template.

Two XHTTP path modes are supported:

1) Dedicated path (e.g. /xhttp or /api/v3)
   -> that location proxies to Xray, everything else serves the website.

2) Root path (client config has path "/" or "/?ed=2048")
   -> the path cannot be used to split traffic, so requests are split by SHAPE:
        - any URI starting with a session UUID (/<uuid> or /<uuid>/<seq>) -> Xray
        - any POST request                                               -> Xray
        - everything else (browser/crawler GET on /)                     -> website
   XHTTP clients always append the session UUID to the path and send uplink
   data as POST, so existing client configs keep working unchanged while
   browsers and crawlers see a normal website.
"""
import sys, re

tpl_path, out_path, local_tls, xport, xpath, primary, maxmb = sys.argv[1:8]
http_ports = sys.argv[8] if len(sys.argv) > 8 else "80"
enable_tls = (sys.argv[9] if len(sys.argv) > 9 else "1") == "1"

listen_lines = []
for i, p in enumerate([x.strip() for x in http_ports.split(",") if x.strip()]):
    d = " default_server" if i == 0 else ""
    listen_lines.append(f"    listen {p}{d};")
    listen_lines.append(f"    listen [::]:{p}{d};")
HTTP_LISTEN = "\n".join(listen_lines)

PROXY = """        proxy_pass http://xhttp_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "";
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_redirect off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        access_log off;"""

UUID = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

clean = (xpath or "").strip().strip("/")
root_mode = (clean == "")

if root_mode:
    xhttp_loc = (
        "    # ===== VPN traffic (XHTTP on root path) =====\n"
        "    # requests beginning with a session UUID -> Xray\n"
        f"    location ~ \"^/{UUID}(/.*)?$\" {{\n{PROXY}\n    }}\n"
    )
    root_loc = (
        "    # XHTTP uplink is always POST; browsers and crawlers use GET.\n"
        "    location / {\n"
        "        if ($request_method = POST) {\n"
        "            proxy_pass http://xhttp_backend;\n"
        "        }\n"
        "        try_files $uri $uri/ /index.php?$query_string;\n"
        "    }"
    )
    xhttp_loc80 = xhttp_loc + (
        "\n    # XHTTP uplink over Cloudflare http ports\n"
        "    location = / {\n"
        "        if ($request_method = POST) {\n"
        "            proxy_pass http://xhttp_backend;\n"
        "        }\n"
        "        return 301 https://$host$request_uri;\n"
        "    }\n"
    )
else:
    xhttp_loc = (
        "    # ===== VPN traffic (XHTTP) - must come before the website =====\n"
        f"    location /{clean} {{\n{PROXY}\n    }}\n"
    )
    xhttp_loc80 = xhttp_loc
    root_loc = "    location / { try_files $uri $uri/ /index.php?$query_string; }"

s = open(tpl_path, encoding="utf-8").read()
if not enable_tls:
    marker = "# ---------- TLS terminated site"
    if marker in s:
        s = s[:s.index(marker)]
s = (s.replace("__XHTTP_LOC_443__", xhttp_loc.rstrip())
       .replace("__XHTTP_LOC_80__", xhttp_loc80.rstrip())
       .replace("__ROOT_LOC__", root_loc)
       .replace("__LOCAL_TLS_PORT__", local_tls)
       .replace("__XHTTP_PORT__", xport)
       .replace("__PRIMARY__", primary)
       .replace("__MAX_UPLOAD_MB__", maxmb)
       .replace("__HTTP_LISTEN__", HTTP_LISTEN))
s += """
# error page
"""
open(out_path, "w", encoding="utf-8").write(s)
print("[render] mode=" + ("root-path" if root_mode else "/" + clean) + "  http ports=" + http_ports + "  tls-layer=" + ("on" if enable_tls else "OFF"))
