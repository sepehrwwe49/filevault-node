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
ok()   { printf '%s[OK]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*"; }
err()  { printf '%s[X]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%s%s%s\n' "$C_D" "------------------------------------------------------------" "$C_0"; }
pause(){ printf '\n%sPress Enter to return to the menu...%s' "$C_D" "$C_0"; read -r _; }

# ---------------------------------------------------------------- env ------
load_env() {
  [ -f "$ENV_FILE" ] || return 1
  set -a; . "$ENV_FILE"; set +a
  : "${SITE_DOMAINS:=}" "${REALITY_DOMAINS:=}" "${XRAY_REALITY_PORT:=12000}"
  : "${XRAY_XHTTP_PORT:=12001}" "${XRAY_XHTTP_PATH:=/}" "${LOCAL_TLS_PORT:=8443}"
  : "${CF_API_TOKEN:=}" "${LE_EMAIL:=}" "${MAX_UPLOAD_MB:=50}" "${RETENTION_DAYS:=7}"
  : "${SITE_NAME:=FileVault}" "${PANEL_PORT:=2053}" "${SSH_PORT:=22}"
  : "${CF_HTTP_PORTS:=80}" "${ENABLE_TLS_LAYER:=1}" "${CF_TLS_PORTS:=443}"
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
  say "Installing prerequisites..."
  if command -v apt-get >/dev/null; then
    apt-get update -y
    apt-get install -y curl openssl python3 ca-certificates iproute2 tar
  elif command -v dnf >/dev/null; then
    dnf install -y curl openssl python3 ca-certificates iproute tar
  fi
  if ! need_docker; then
    say "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker 2>/dev/null || true
  fi
  need_docker && ok "Docker ready" || die "Docker installation failed"
}

dc() { ( cd "$FV_DIR" && docker compose "$@" ); }

# -------------------------------------------------------- config render ----
render_config() {
  load_env || die ".env not found - run option 1 (Setup wizard) first"
  [ -n "$PRIMARY" ] || die "SITE_DOMAINS is empty"

  local map=""
  if [ -n "$REALITY_DOMAINS" ]; then
    local d
    for d in $(echo "$REALITY_DOMAINS" | tr ',' ' '); do
      d="$(echo "$d" | xargs)"; [ -n "$d" ] || continue
      map+="    ${d}   127.0.0.1:${XRAY_REALITY_PORT};"$'\n'
    done
  fi
  if [ "$ENABLE_TLS_LAYER" = "1" ]; then
    REALITY_MAP="$map" python3 "$FV_DIR/lib/render_stream.py" \
      "$FV_DIR/nginx/stream.d/00-map.conf.template" \
      "$FV_DIR/nginx/stream.d/00-map.conf" "$LOCAL_TLS_PORT" "$CF_TLS_PORTS" \
      || die "stream render failed"
  else
    rm -f "$FV_DIR/nginx/stream.d/00-map.conf"
    warn "TLS layer disabled (ENABLE_TLS_LAYER=0) - nginx will NOT bind port 443"
  fi


  local f
  for f in robots.txt sitemap.xml; do
    sed "s|__PRIMARY__|${PRIMARY}|g" "$FV_DIR/site/${f}.template" > "$FV_DIR/site/${f}"
  done

  mkdir -p "$FV_DIR/data/uploads" "$FV_DIR/data/meta" "$FV_DIR/nginx/acme" \
           "$FV_DIR/letsencrypt/current"
  chown -R 33:33 "$FV_DIR/data" 2>/dev/null || true
  chmod -R 775 "$FV_DIR/data" 2>/dev/null || true

  # nginx always reads /etc/letsencrypt/current; certbot republishes into it on
  # every issue and renew, so the vhost never needs re-rendering for a new cert.
  mkdir -p "$FV_DIR/letsencrypt/current"
  if [ ! -f "$FV_DIR/letsencrypt/current/fullchain.pem" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -keyout "$FV_DIR/letsencrypt/current/privkey.pem" \
      -out    "$FV_DIR/letsencrypt/current/fullchain.pem" \
      -subj "/CN=$PRIMARY" >/dev/null 2>&1
    warn "Bootstrap certificate in place - certbot will replace it automatically"
  fi
  CERT_DIR="/etc/letsencrypt/current"
  python3 "$FV_DIR/lib/render_vhost.py" \
      "$FV_DIR/nginx/conf.d/00-site.conf.template" \
      "$FV_DIR/nginx/conf.d/00-site.conf" \
      "$LOCAL_TLS_PORT" "$XRAY_XHTTP_PORT" "$XRAY_XHTTP_PATH" "$PRIMARY" "$MAX_UPLOAD_MB" \
      "$CF_HTTP_PORTS" "$ENABLE_TLS_LAYER" "$CERT_DIR" \
      || die "Failed to render nginx config"
  ok "Config rendered (primary domain: $PRIMARY)"
}


# ----------------------------------------------------------- port helpers --
port_busy() { ss -ltn "( sport = :$1 )" 2>/dev/null | grep -q LISTEN; }
port_owner(){ ss -ltnp "( sport = :$1 )" 2>/dev/null | awk 'NR>1{print $NF}' | head -1; }

# first free port at or after $1
free_port() {
  local p="$1"
  while port_busy "$p"; do p=$((p+1)); done
  echo "$p"
}

# keep only the ports of a list that are free (or already ours)
filter_free_ports() {
  local out="" p
  for p in $(echo "$1" | tr ',' ' '); do
    if ! port_busy "$p" || port_owner "$p" | grep -qi nginx; then
      out="${out:+$out,}$p"
    fi
  done
  echo "$out"
}

port_scan() {
  hr; echo " PORT MAP"; hr
  printf '  %-8s %-10s %s\n' PORT STATE OWNER
  local p
  for p in 80 443 2052 2053 2082 2083 2086 2087 2095 2096 8080 8443 8880 \
           "${LOCAL_TLS_PORT:-8443}" "${XRAY_XHTTP_PORT:-12001}" "${XRAY_REALITY_PORT:-12000}"; do
    if port_busy "$p"; then
      printf '  %-8s %-10s %s\n' "$p" "BUSY" "$(port_owner "$p")"
    else
      printf '  %-8s %-10s\n' "$p" "free"
    fi
  done
  hr
  echo "  Cloudflare HTTP ports: 80 8080 8880 2052 2082 2086 2095"
  echo "  Cloudflare TLS  ports: 443 2053 2083 2087 2096 8443"
}

# ----------------------------------------------------------- checks --------

preflight() {
  load_env || { err ".env not found"; return 1; }
  local fail=0
  hr; echo " PREFLIGHT CHECK"; hr
  local p
  for p in "$XRAY_XHTTP_PORT" "$XRAY_REALITY_PORT"; do
    if port_busy "$p"; then ok "port $p is LISTENING  $(port_owner "$p")"
    else err "port $p is NOT listening - create/enable that inbound in the panel"; fail=1; fi
  done
  if port_busy 443; then
    local o; o="$(port_owner 443)"
    if echo "$o" | grep -qi nginx; then ok "port 443 is held by nginx"
    else warn "port 443 still held by Xray/panel -> $o   (must be freed to cut over)"; fi
  else warn "port 443 is free"; fi
  port_busy "$PANEL_PORT" && ok "panel is up on $PANEL_PORT" || warn "panel not listening on $PANEL_PORT"
  [ -n "$CF_API_TOKEN" ] && ok "Cloudflare token is set" || { err "CF_API_TOKEN is empty"; fail=1; }
  return $fail
}

# ------------------------------------------------------------- lifecycle ---
build_up()   {
  render_config
  say "Starting containers..."
  dc up -d --build >/dev/null 2>&1 || true
  # a container stuck in a restart loop is not touched by plain "up"
  if dc ps nginx 2>/dev/null | grep -qi restarting; then
    warn "nginx was restarting - recreating it"
    dc up -d --force-recreate nginx
  else
    dc up -d --build
  fi
  sleep 2
  if dc ps nginx 2>/dev/null | grep -qi restarting; then
    err "nginx is still failing:"
    dc logs --tail 6 nginx | grep -i emerg || dc logs --tail 8 nginx
    return 1
  fi
  ok "Containers are up"
}
restart_all(){ render_config; dc up -d --build; dc restart; ok "Restarted"; }
stop_all()   { dc down; ok "Stopped"; }
nginx_test() { dc exec -T nginx nginx -t; }
nginx_reload(){
  render_config
  if dc exec -T nginx nginx -t >/dev/null 2>&1; then
    dc exec -T nginx nginx -s reload && ok "nginx reloaded"
  else
    warn "reload not possible - recreating nginx"
    dc up -d --force-recreate nginx
    sleep 2
    if dc ps nginx 2>/dev/null | grep -qi restarting; then
      err "nginx failed to start:"; dc logs --tail 6 nginx | grep -i emerg
      return 1
    fi
    ok "nginx recreated"
  fi
}

# Start web stack WITHOUT binding port 443 (safe pre-cutover stage)
start_backend_only() {
  render_config
  say "Starting php/certbot/cleaner (nginx stays down, port 443 untouched)..."
  dc up -d --build php certbot cleaner
  ok "Backend is up - SSL is issued over DNS-01, no web port needed"
}

cutover() {
  load_env || { err ".env not found"; return 1; }
  hr
  cat <<TXT
 ZERO-DOWNTIME CUTOVER
 ---------------------
 1) In the Pasarguard panel, CLONE your current inbound. On the clone set:
        XHTTP   -> listen 127.0.0.1:$XRAY_XHTTP_PORT   (TLS OFF, nginx terminates)
        Reality -> listen 127.0.0.1:$XRAY_REALITY_PORT (TLS untouched)
    Leave the old inbound on 443 running - your clients are still on it.
 2) This script waits for port 443 to become free.
 3) Disable the old 443 inbound in the panel. nginx grabs 443 in under a second.
    Clients only see a normal auto-reconnect. No client config change needed.
TXT
  hr
  preflight || { err "Preflight failed"; return 1; }
  confirm "Start waiting for port 443 to be released?" || return 0

  say "Waiting for port 443 to be freed (Ctrl+C to abort)..."
  local i=0
  while port_busy 443; do sleep 0.3; i=$((i+1)); [ $((i%10)) -eq 0 ] && printf '.'; done
  echo
  say "443 is free - starting nginx"
  dc up -d --build nginx
  sleep 2
  if port_busy 443; then ok "nginx is now on 443. Cutover complete."
  else err "nginx did not start - check: docker compose logs nginx"; fi
}

rollback() {
  warn "nginx will be stopped and port 443 released so the old panel inbound can take it back."
  confirm "Are you sure?" || return 0
  dc stop nginx && ok "nginx stopped. Now re-enable the old 443 inbound in the panel."
}

# ------------------------------------------------------------ firewall -----
apply_firewall() {
  load_env || return 1
  command -v ufw >/dev/null || { say "Installing ufw..."; apt-get update -y && apt-get install -y ufw; }
  warn "Ports that will stay open: $SSH_PORT, http=${CF_HTTP_PORTS}, tls=${CF_TLS_PORTS}, panel=$PANEL_PORT, extra=${EXTRA_OPEN_PORTS:-none}"
  warn "UDP/443 (QUIC/h3) stays closed - nginx routes TCP only, clients fall back to h2."
  confirm "Apply firewall rules?" || return 0
  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow "$SSH_PORT"/tcp comment 'ssh' >/dev/null
  local hp
  for hp in $(echo "${CF_HTTP_PORTS:-80}" | tr ',' ' '); do
    ufw allow "${hp}"/tcp comment 'http' >/dev/null
  done
  local tp
  for tp in $(echo "${CF_TLS_PORTS:-443}" | tr ',' ' '); do
    ufw allow "${tp}"/tcp comment 'https' >/dev/null
  done
  if [ "${OPEN_QUIC:-0}" = "1" ]; then ufw allow 443/udp comment 'quic' >/dev/null; fi
  ufw allow "$PANEL_PORT"/tcp comment 'panel' >/dev/null
  if [ -n "${EXTRA_OPEN_PORTS:-}" ]; then
    local p; for p in $(echo "$EXTRA_OPEN_PORTS" | tr ',' ' '); do
      ufw allow "${p}"/tcp comment 'extra' >/dev/null; done
  fi
  ufw --force enable
  ufw status numbered
}

# --------------------------------------------------------------- ssl -------
ssl_status() { dc exec -T certbot certbot certificates 2>/dev/null || warn "certbot container is not running"; }
ssl_force()  { dc exec -T certbot certbot renew --force-renewal --non-interactive \
                 --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
                 --dns-cloudflare-propagation-seconds 30 && nginx_reload; }
ssl_reissue(){ dc rm -sf certbot >/dev/null 2>&1; render_config; dc up -d --build certbot; dc logs -f certbot; }

# ------------------------------------------------------------- status ------
status() {
  load_env || { err ".env not found"; return 1; }
  hr; printf ' %sNODE STATUS%s\n' "$C_C" "$C_0"; hr
  printf '  Primary domain   : %s\n' "$PRIMARY"
  printf '  Site domains     : %s\n' "$SITE_DOMAINS"
  printf '  Reality domains  : %s\n' "${REALITY_DOMAINS:-none}"
  printf '  Xray Reality     : 127.0.0.1:%s\n' "$XRAY_REALITY_PORT"
  printf '  Xray XHTTP       : 127.0.0.1:%s   path=%s\n' "$XRAY_XHTTP_PORT" "$XRAY_XHTTP_PATH"
  printf '  HTTP listen ports: %s\n' "$CF_HTTP_PORTS"
  printf '  TLS listen ports : %s\n' "$CF_TLS_PORTS"
  printf '  Panel port       : %s\n' "$PANEL_PORT"
  printf '  Upload limit     : %s MB   retention: %s days\n' "$MAX_UPLOAD_MB" "$RETENTION_DAYS"
  hr
  dc ps 2>/dev/null
  hr
  local p; for p in $(echo "$CF_HTTP_PORTS" | tr ',' ' ') $(echo "$CF_TLS_PORTS" | tr ',' ' ') "$LOCAL_TLS_PORT" "$XRAY_XHTTP_PORT" "$XRAY_REALITY_PORT" "$PANEL_PORT"; do
    if port_busy "$p"; then printf '  port %-6s %sLISTEN%s  %s\n' "$p" "$C_G" "$C_0" "$(port_owner "$p")"
    else printf '  port %-6s %sclosed%s\n' "$p" "$C_R" "$C_0"; fi
  done
  hr
  if [ -d "$FV_DIR/data/uploads" ]; then
    printf '  Stored files: %s  (%s)\n' \
      "$(find "$FV_DIR/data/uploads" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)" \
      "$(du -sh "$FV_DIR/data" 2>/dev/null | cut -f1)"
  fi
}

selftest() {
  load_env || return 1
  hr; echo " SITE SELF-TEST"; hr
  local u="https://127.0.0.1:${LOCAL_TLS_PORT}"
  printf '  home page  : '; curl -sk -o /dev/null -w '%{http_code}\n' -H "Host: $PRIMARY" "$u/"
  printf '  robots.txt : '; curl -sk -o /dev/null -w '%{http_code}\n' -H "Host: $PRIMARY" "$u/robots.txt"
  printf '  sitemap.xml: '; curl -sk -o /dev/null -w '%{http_code}\n' -H "Host: $PRIMARY" "$u/sitemap.xml"
  printf '  404 page   : '; curl -sk -o /dev/null -w '%{http_code}\n' -H "Host: $PRIMARY" "$u/nope-xyz"
  printf '  test upload: '
  local tmp; tmp="$(mktemp /tmp/fvtest.XXXX.txt)"; echo "filevault selftest" > "$tmp"
  curl -sk -H "Host: $PRIMARY" -F "file=@$tmp" "$u/upload.php" | head -c 300; echo
  rm -f "$tmp"
  hr
  echo " Also test from outside:  curl -I https://$PRIMARY/"
}

# =============================================================================
#  doctor - find and fix the usual problems without hand-written commands
# =============================================================================
doctor() {
  load_env || { err ".env not found - run the setup wizard first"; return 1; }
  local fixes=0
  hr; echo " DOCTOR"; hr

  # 1. internal ports must not clash with anything else on the host
  local p owner
  for var in LOCAL_TLS_PORT XRAY_XHTTP_PORT; do
    eval "p=\$$var"
    owner="$(port_owner "$p")"
    if port_busy "$p" && ! echo "$owner" | grep -qiE 'nginx|xray'; then
      warn "$var=$p is taken by $owner"
    fi
  done
  if port_busy "$LOCAL_TLS_PORT" && ! port_owner "$LOCAL_TLS_PORT" | grep -qi nginx; then
    local np; np="$(free_port 18443)"
    warn "LOCAL_TLS_PORT $LOCAL_TLS_PORT is used by $(port_owner "$LOCAL_TLS_PORT")"
    if confirm "Move the internal site port to $np?"; then
      env_set LOCAL_TLS_PORT "$np"; LOCAL_TLS_PORT="$np"; fixes=$((fixes+1)); ok "set to $np"
    fi
  fi

  # 2. every listen port must be free or already ours
  local clean_http clean_tls
  clean_http="$(filter_free_ports "$CF_HTTP_PORTS")"
  clean_tls="$(filter_free_ports "$CF_TLS_PORTS")"
  if [ "$clean_http" != "$CF_HTTP_PORTS" ]; then
    warn "HTTP ports in use by something else: $CF_HTTP_PORTS -> $clean_http"
    if confirm "Drop the busy ones?"; then env_set CF_HTTP_PORTS "$clean_http"; fixes=$((fixes+1)); fi
  fi
  if [ "$clean_tls" != "$CF_TLS_PORTS" ]; then
    warn "TLS ports in use by something else: $CF_TLS_PORTS -> $clean_tls"
    if confirm "Drop the busy ones?"; then env_set CF_TLS_PORTS "$clean_tls"; fixes=$((fixes+1)); fi
  fi

  # 3. the Xray upstream must actually be listening
  if port_busy "$XRAY_XHTTP_PORT"; then ok "Xray upstream $XRAY_XHTTP_PORT is listening"
  else err "Nothing is listening on $XRAY_XHTTP_PORT - create that inbound in the panel"; fi

  # 4. certificate
  local cur="$FV_DIR/letsencrypt/current/fullchain.pem"
  if [ -f "$cur" ]; then
    local issuer; issuer="$(openssl x509 -in "$cur" -noout -issuer 2>/dev/null)"
    case "$issuer" in
      *"Let's Encrypt"*) ok "certificate issued by Let's Encrypt" ;;
      *) warn "still using the bootstrap certificate"
         if confirm "Ask certbot to issue the real one now?"; then
           dc rm -sf certbot >/dev/null 2>&1
           dc up -d --build certbot
           say "issuing... (about a minute)"; sleep 55
           dc logs --tail 6 certbot
           fixes=$((fixes+1))
         fi ;;
    esac
  fi

  # 5. containers
  if dc ps nginx 2>/dev/null | grep -qi restarting; then
    err "nginx is in a restart loop:"
    dc logs --tail 6 nginx | grep -i emerg
    if confirm "Re-render the config and restart it?"; then build_up; fixes=$((fixes+1)); fi
  elif dc ps nginx 2>/dev/null | grep -qi ' Up '; then
    ok "nginx is running"
  else
    warn "nginx is not running"
    confirm "Start it?" && { build_up; fixes=$((fixes+1)); }
  fi

  hr
  if [ "$fixes" -gt 0 ]; then
    say "applied $fixes fix(es) - restarting"
    build_up
  fi
  ok "doctor finished"
}

# =============================================================================
#  take_port - hand one more port to nginx, end to end
# =============================================================================
take_port() {
  load_env || return 1
  local port kind cur
  hr; echo " TAKE OVER A PORT"; hr
  port_scan
  echo
  ask port "Port to hand to nginx" ""
  [ -n "$port" ] || return 0

  case "$port" in
    443|2053|2083|2087|2096|8443) kind=tls ;;
    *) kind=http ;;
  esac
  ask kind "Is this a plain-HTTP or a TLS port? (http/tls)" "$kind"

  if port_busy "$port"; then
    local o; o="$(port_owner "$port")"
    if echo "$o" | grep -qi nginx; then
      ok "nginx already owns $port"; return 0
    fi
    err "port $port is used by: $o"
    echo
    echo "  In the panel, change THAT inbound's port to a free internal one"
    echo "  (suggestion: $(free_port 12010)) and keep everything else the same."
    echo "  Then come back and run this again."
    confirm "Have you already freed it and want to continue anyway?" || return 0
  fi

  if [ "$kind" = "tls" ]; then
    cur="$CF_TLS_PORTS"
    echo "$cur" | tr ',' '\n' | grep -qx "$port" || env_set CF_TLS_PORTS "${cur:+$cur,}$port"
    env_set ENABLE_TLS_LAYER 1
  else
    cur="$CF_HTTP_PORTS"
    echo "$cur" | tr ',' '\n' | grep -qx "$port" || env_set CF_HTTP_PORTS "${cur:+$cur,}$port"
  fi

  load_env
  nginx_reload || return 1
  sleep 1

  hr; echo " VERIFY"; hr
  if [ "$kind" = "tls" ]; then
    printf '  website : '; curl -sk -o /dev/null -w '%{http_code}\n' -H "Host: $PRIMARY" "https://127.0.0.1:$port/"
  else
    printf '  website : '; curl -s -o /dev/null -w '%{http_code}\n' -H "Host: $PRIMARY" "http://127.0.0.1:$port/"
    printf '  vpn path: '; curl -s -o /dev/null -w '%{http_code}\n' -X POST -H "Host: $PRIMARY" "http://127.0.0.1:$port/"
  fi
  echo
  echo "  website should be 200; vpn path should NOT be 200."
  echo "  Client config: keep everything, just set the port to $port."
}
