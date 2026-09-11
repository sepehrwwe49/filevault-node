#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  FileVault Node - core library (sourced by menu.sh)
# ---------------------------------------------------------------------------
set -uo pipefail

FV_DIR="${FV_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ENV_FILE="$FV_DIR/.env"

C_R=$'\033[1;31m'; C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'
C_B=$'\033[1;34m'; C_C=$'\033[1;36m'; C_D=$'\033[2m'; C_0=$'\033[0m'

say()  { printf '%s[*]%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '%s[✓]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*"; }
err()  { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%s%s%s\n' "$C_D" "────────────────────────────────────────────────────────────" "$C_0"; }
pause(){ printf '\n%sEnter بزن تا برگردی به منو...%s' "$C_D" "$C_0"; read -r _; }

# ---------------------------------------------------------------- env ------
load_env() {
  [ -f "$ENV_FILE" ] || return 1
  set -a; . "$ENV_FILE"; set +a
  : "${SITE_DOMAINS:=}" "${REALITY_DOMAINS:=}" "${XRAY_REALITY_PORT:=12000}"
  : "${XRAY_XHTTP_PORT:=12001}" "${XRAY_XHTTP_PATH:=xhttp}" "${LOCAL_TLS_PORT:=8443}"
  : "${CF_API_TOKEN:=}" "${LE_EMAIL:=}" "${MAX_UPLOAD_MB:=50}" "${RETENTION_DAYS:=7}"
  : "${SITE_NAME:=FileVault}" "${PANEL_PORT:=2053}" "${SSH_PORT:=22}"
  PRIMARY="$(echo "$SITE_DOMAINS" | cut -d, -f1 | xargs)"
  return 0
}

env_set() {  # env_set KEY VALUE
  local k="$1" v="$2"
  touch "$ENV_FILE"
  if grep -qE "^${k}=" "$ENV_FILE"; then
    python3 - "$ENV_FILE" "$k" "$v" <<'PY'
import sys,re
p,k,v=sys.argv[1],sys.argv[2],sys.argv[3]
lines=open(p).read().splitlines()
out=[(k+"="+v) if re.match("^"+re.escape(k)+"=",l) else l for l in lines]
open(p,"w").write("\n".join(out)+"\n")
PY
  else
    printf '%s=%s\n' "$k" "$v" >> "$ENV_FILE"
  fi
}

ask() {  # ask VAR "prompt" "default"
  local __v="$1" __p="$2" __d="${3:-}" __in
  if [ -n "$__d" ]; then
    printf '%s  %s %s[%s]%s: ' "$C_C" "$__p" "$C_D" "$__d" "$C_0"
  else
    printf '%s  %s%s: ' "$C_C" "$__p" "$C_0"
  fi
  read -r __in
  [ -z "$__in" ] && __in="$__d"
  printf -v "$__v" '%s' "$__in"
}

confirm() { local a; printf '%s  %s [y/N]: %s' "$C_Y" "$1" "$C_0"; read -r a; [ "${a,,}" = "y" ]; }

# ------------------------------------------------------------ deps ---------
need_docker() {
  command -v docker >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1 || return 1
  return 0
}

install_docker() {
  say "نصب پیش‌نیازها..."
  if command -v apt-get >/dev/null; then
    apt-get update -y
    apt-get install -y curl openssl python3 ca-certificates iproute2 tar
  elif command -v dnf >/dev/null; then
    dnf install -y curl openssl python3 ca-certificates iproute tar
  fi
  if ! need_docker; then
    say "نصب داکر..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker 2>/dev/null || true
  fi
  need_docker && ok "داکر آماده است" || die "نصب داکر ناموفق بود"
}

dc() { ( cd "$FV_DIR" && docker compose "$@" ); }

# -------------------------------------------------------- config render ----
render_config() {
  load_env || die ".env پیدا نشد — اول گزینه ۱ (نصب اولیه) را اجرا کن"
  [ -n "$PRIMARY" ] || die "SITE_DOMAINS خالی است"

  local map=""
  if [ -n "$REALITY_DOMAINS" ]; then
    local d
    for d in $(echo "$REALITY_DOMAINS" | tr ',' ' '); do
      d="$(echo "$d" | xargs)"; [ -n "$d" ] || continue
      map+="    ${d}   127.0.0.1:${XRAY_REALITY_PORT};"$'\n'
    done
  fi
  REALITY_MAP="$map" LOCAL_TLS_PORT="$LOCAL_TLS_PORT" python3 - <<'PY'
import os
tpl=open('nginx/stream.d/00-map.conf.template').read()
tpl=tpl.replace('__LOCAL_TLS_PORT__',os.environ['LOCAL_TLS_PORT'])
tpl=tpl.replace('__REALITY_MAP__',os.environ.get('REALITY_MAP','').rstrip('\n'))
open('nginx/stream.d/00-map.conf','w').write(tpl)
PY

  sed -e "s|__LOCAL_TLS_PORT__|${LOCAL_TLS_PORT}|g" \
      -e "s|__XHTTP_PORT__|${XRAY_XHTTP_PORT}|g" \
      -e "s|__XHTTP_PATH__|${XRAY_XHTTP_PATH}|g" \
      -e "s|__PRIMARY__|${PRIMARY}|g" \
      -e "s|__MAX_UPLOAD_MB__|${MAX_UPLOAD_MB}|g" \
      "$FV_DIR/nginx/conf.d/00-site.conf.template" > "$FV_DIR/nginx/conf.d/00-site.conf"

  local f
  for f in robots.txt sitemap.xml; do
    sed "s|__PRIMARY__|${PRIMARY}|g" "$FV_DIR/site/${f}.template" > "$FV_DIR/site/${f}"
  done

  mkdir -p "$FV_DIR/data/uploads" "$FV_DIR/data/meta" "$FV_DIR/nginx/acme" \
           "$FV_DIR/letsencrypt/live/$PRIMARY"
  chown -R 33:33 "$FV_DIR/data" 2>/dev/null || true
  chmod -R 775 "$FV_DIR/data"

  if [ ! -f "$FV_DIR/letsencrypt/live/$PRIMARY/fullchain.pem" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -keyout "$FV_DIR/letsencrypt/live/$PRIMARY/privkey.pem" \
      -out    "$FV_DIR/letsencrypt/live/$PRIMARY/fullchain.pem" \
      -subj "/CN=$PRIMARY" >/dev/null 2>&1
    warn "گواهی موقت self-signed ساخته شد (certbot جایگزینش می‌کند)"
  fi
  ok "کانفیگ‌ها ساخته شد (دامنه اصلی: $PRIMARY)"
}

# ----------------------------------------------------------- checks --------
port_busy() { ss -ltn "( sport = :$1 )" 2>/dev/null | grep -q LISTEN; }
port_owner(){ ss -ltnp "( sport = :$1 )" 2>/dev/null | awk 'NR>1{print $NF}' | head -1; }

preflight() {
  load_env || return 1
  local fail=0
  hr; echo " بررسی پیش از سوییچ"; hr
  local p
  for p in "$XRAY_XHTTP_PORT" "$XRAY_REALITY_PORT"; do
    if port_busy "$p"; then ok "پورت $p در حال شنیدن است $(port_owner "$p")"
    else err "پورت $p شنیده نمی‌شود — اینباند مربوطه را در پنل بساز/فعال کن"; fail=1; fi
  done
  if port_busy 443; then
    local o; o="$(port_owner 443)"
    if echo "$o" | grep -qi nginx; then ok "پورت 443 دست nginx است"
    else warn "پورت 443 هنوز دست Xray/پنل است → $o  (برای سوییچ باید آزاد شود)"; fi
  else warn "پورت 443 آزاد است"; fi
  port_busy "$PANEL_PORT" && ok "پنل روی $PANEL_PORT بالاست" || warn "پنل روی $PANEL_PORT شنیده نمی‌شود"
  [ -n "$CF_API_TOKEN" ] && ok "توکن کلودفلر ست شده" || { err "CF_API_TOKEN خالی است"; fail=1; }
  return $fail
}

# ------------------------------------------------------------- lifecycle ---
build_up()  { render_config; say "بالا آوردن کانتینرها..."; dc up -d --build && ok "کانتینرها بالا آمدند"; }
restart_all(){ render_config; dc up -d --build; dc restart; ok "ری‌استارت شد"; }
stop_all()  { dc down; ok "متوقف شد"; }
nginx_test(){ dc exec -T nginx nginx -t; }
nginx_reload(){ render_config; dc exec -T nginx nginx -t && dc exec -T nginx nginx -s reload && ok "nginx ری‌لود شد"; }

# فقط سرویس‌های وب بدون اشغال پورت ۴۴۳ (برای تست قبل از سوییچ)
start_backend_only() {
  render_config
  say "بالا آوردن php/certbot/cleaner بدون nginx..."
  dc up -d --build php certbot cleaner
  ok "بک‌اند بالاست — گواهی SSL مستقل از پورت ۴۴۳ صادر می‌شود"
}

cutover() {
  load_env || return 1
  hr
  cat <<TXT
 سوییچ بدون قطعی برای مشتری‌ها
 ─────────────────────────────
 ۱) در پنل پاسارگاد یک اینباند *جدید* بساز که کپی دقیق اینباند فعلی باشد،
    فقط پورتش 127.0.0.1:$XRAY_XHTTP_PORT (XHTTP، TLS خاموش) و
    127.0.0.1:$XRAY_REALITY_PORT (Reality) باشد. اینباند قدیمی روی 443 را دست نزن.
 ۲) وقتی هر دو پورت جدید بالا آمدند، همین اسکریپت منتظر می‌ماند.
 ۳) اینباند قدیمی 443 را در پنل غیرفعال کن → اسکریپت در کمتر از یک ثانیه
    nginx را روی 443 می‌نشاند. مشتری‌ها فقط یک ری‌کانکت خودکار می‌خورند و
    هیچ کانفیگی لازم نیست عوض شود.
TXT
  hr
  preflight || { err "پیش‌نیازها کامل نیست"; return 1; }
  confirm "شروع حالت انتظار برای آزاد شدن پورت 443؟" || return 0

  say "منتظر آزاد شدن پورت 443 (Ctrl+C برای لغو)..."
  local i=0
  while port_busy 443; do sleep 0.3; i=$((i+1)); [ $((i%10)) -eq 0 ] && printf '.'; done
  echo
  say "443 آزاد شد — بالا آوردن nginx"
  dc up -d --build nginx
  sleep 2
  if port_busy 443; then ok "nginx روی 443 نشست. سوییچ انجام شد."; else err "nginx بالا نیامد — لاگ: docker compose logs nginx"; fi
}

rollback() {
  warn "nginx خاموش می‌شود و پورت 443 آزاد می‌شود تا اینباند قدیمی پنل دوباره فعال شود."
  confirm "مطمئنی؟" || return 0
  dc stop nginx && ok "nginx خاموش شد. حالا اینباند 443 را در پنل برگردان."
}

# ------------------------------------------------------------ firewall -----
apply_firewall() {
  load_env || return 1
  command -v ufw >/dev/null || { say "نصب ufw..."; apt-get update -y && apt-get install -y ufw; }
  warn "پورت‌های باز خواهند بود: $SSH_PORT, 80, 443(tcp+udp), $PANEL_PORT"
  confirm "اعمال شود؟" || return 0
  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow "$SSH_PORT"/tcp comment 'ssh' >/dev/null
  ufw allow 80/tcp   comment 'http'  >/dev/null
  ufw allow 443/tcp  comment 'https' >/dev/null
  ufw allow 443/udp  comment 'quic'  >/dev/null
  ufw allow "$PANEL_PORT"/tcp comment 'panel' >/dev/null
  if [ -n "${EXTRA_OPEN_PORTS:-}" ]; then
    local p; for p in $(echo "$EXTRA_OPEN_PORTS" | tr ',' ' '); do
      ufw allow "${p}"/tcp comment 'extra' >/dev/null; done
  fi
  ufw --force enable
  ufw status numbered
}

# --------------------------------------------------------------- ssl -------
ssl_status() { dc exec -T certbot certbot certificates 2>/dev/null || warn "کانتینر certbot بالا نیست"; }
ssl_force()  { dc exec -T certbot certbot renew --force-renewal --non-interactive \
                 --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
                 --dns-cloudflare-propagation-seconds 30 && nginx_reload; }
ssl_reissue(){ dc rm -sf certbot >/dev/null 2>&1; render_config; dc up -d --build certbot; dc logs -f certbot; }

# ------------------------------------------------------------- status ------
status() {
  load_env || { err ".env نیست"; return 1; }
  hr; printf ' %sوضعیت نود%s\n' "$C_C" "$C_0"; hr
  printf '  دامنه اصلی      : %s\n' "$PRIMARY"
  printf '  دامنه‌های سایت   : %s\n' "$SITE_DOMAINS"
  printf '  دامنه‌های Reality: %s\n' "${REALITY_DOMAINS:-—}"
  printf '  Xray Reality    : 127.0.0.1:%s\n' "$XRAY_REALITY_PORT"
  printf '  Xray XHTTP      : 127.0.0.1:%s  path=/%s\n' "$XRAY_XHTTP_PORT" "$XRAY_XHTTP_PATH"
  printf '  پنل             : %s\n' "$PANEL_PORT"
  printf '  سقف آپلود       : %s MB   نگهداری: %s روز\n' "$MAX_UPLOAD_MB" "$RETENTION_DAYS"
  hr
  dc ps 2>/dev/null
  hr
  local p; for p in 80 443 "$LOCAL_TLS_PORT" "$XRAY_XHTTP_PORT" "$XRAY_REALITY_PORT" "$PANEL_PORT"; do
    if port_busy "$p"; then printf '  %s:%-6s %sLISTEN%s %s\n' "port" "$p" "$C_G" "$C_0" "$(port_owner "$p")"
    else printf '  %s:%-6s %s—%s\n' "port" "$p" "$C_R" "$C_0"; fi
  done
  hr
  if [ -d "$FV_DIR/data/uploads" ]; then
    printf '  فایل‌های ذخیره‌شده: %s  (%s)\n' \
      "$(find "$FV_DIR/data/uploads" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)" \
      "$(du -sh "$FV_DIR/data" 2>/dev/null | cut -f1)"
  fi
}

selftest() {
  load_env || return 1
  hr; echo " تست سایت"; hr
  local u="https://127.0.0.1:${LOCAL_TLS_PORT}"
  printf '  صفحه اصلی : '; curl -sk -o /dev/null -w '%{http_code}\n' -H "Host: $PRIMARY" "$u/"
  printf '  robots.txt: '; curl -sk -o /dev/null -w '%{http_code}\n' -H "Host: $PRIMARY" "$u/robots.txt"
  printf '  sitemap   : '; curl -sk -o /dev/null -w '%{http_code}\n' -H "Host: $PRIMARY" "$u/sitemap.xml"
  printf '  404       : '; curl -sk -o /dev/null -w '%{http_code}\n' -H "Host: $PRIMARY" "$u/nope-xyz"
  printf '  آپلود تستی: '
  local tmp; tmp="$(mktemp /tmp/fvtest.XXXX.txt)"; echo "filevault selftest" > "$tmp"
  curl -sk -H "Host: $PRIMARY" -F "file=@$tmp" "$u/upload.php" | head -c 300; echo
  rm -f "$tmp"
  hr
  echo " از بیرون هم تست کن:  curl -I https://$PRIMARY/"
}
