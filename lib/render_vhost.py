#!/usr/bin/env python3
"""
ساخت vhost انجین‌ایکس از روی تمپلیت.

دو حالت مسیر XHTTP پشتیبانی می‌شود:

1) path اختصاصی  (مثل /xhttp یا /api/v3)
   -> location همان مسیر به Xray می‌رود، بقیه سایت.

2) path ریشه  (path در کانفیگ کلاینت = "/" یا خالی، مثل  path=/?ed=2048)
   -> نمی‌توان بر اساس مسیر تفکیک کرد، پس بر اساس *شکل درخواست* تفکیک می‌شود:
        - هر URI که با یک UUID شروع شود  (/<uuid>  یا  /<uuid>/<seq>)  => Xray
        - هر درخواست POST                                             => Xray
        - بقیه (GET مرورگر/کرالر روی /)                                => وب‌سایت
   کلاینت‌های XHTTP همیشه UUID نشست را به مسیر می‌چسبانند و آپلینک را POST
   می‌کنند، پس کانفیگ‌های قدیمی بدون هیچ تغییری کار می‌کنند و مرورگر سایت می‌بیند.
"""
import sys, re

tpl_path, out_path, local_tls, xport, xpath, primary, maxmb = sys.argv[1:8]

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
        "    # ===== VPN traffic (XHTTP روی مسیر ریشه) =====\n"
        "    # درخواست‌هایی که با UUID نشست شروع می‌شوند => Xray\n"
        f"    location ~ \"^/{UUID}(/.*)?$\" {{\n{PROXY}\n    }}\n"
    )
    root_loc = (
        "    # آپلینک XHTTP همیشه POST است؛ مرورگر و کرالر GET می‌زنند.\n"
        "    location / {\n"
        "        if ($request_method = POST) {\n"
        "            proxy_pass http://xhttp_backend;\n"
        "        }\n"
        "        try_files $uri $uri/ /index.php?$query_string;\n"
        "    }"
    )
    xhttp_loc80 = xhttp_loc + (
        "\n    # آپلینک XHTTP روی پورت‌های http کلودفلر\n"
        "    location = / {\n"
        "        if ($request_method = POST) {\n"
        "            proxy_pass http://xhttp_backend;\n"
        "        }\n"
        "        return 301 https://$host$request_uri;\n"
        "    }\n"
    )
else:
    xhttp_loc = (
        "    # ===== VPN traffic (XHTTP) — باید قبل از بقیه باشد =====\n"
        f"    location /{clean} {{\n{PROXY}\n    }}\n"
    )
    xhttp_loc80 = xhttp_loc
    root_loc = "    location / { try_files $uri $uri/ /index.php?$query_string; }"

s = open(tpl_path, encoding="utf-8").read()
s = (s.replace("__XHTTP_LOC_443__", xhttp_loc.rstrip())
       .replace("__XHTTP_LOC_80__", xhttp_loc80.rstrip())
       .replace("__ROOT_LOC__", root_loc)
       .replace("__LOCAL_TLS_PORT__", local_tls)
       .replace("__XHTTP_PORT__", xport)
       .replace("__PRIMARY__", primary)
       .replace("__MAX_UPLOAD_MB__", maxmb))
s += """
# error page
"""
open(out_path, "w", encoding="utf-8").write(s)
print("[render] mode=" + ("root-path" if root_mode else "/" + clean))
