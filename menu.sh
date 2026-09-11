#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  FileVault Node - management menu
#  run:  sudo bash menu.sh     or after install:  sudo fv
# ---------------------------------------------------------------------------
FV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$FV_DIR/lib/core.sh"

[ "$(id -u)" -eq 0 ] || die "Run as root:  sudo bash menu.sh"

banner() {
  clear
  cat <<'B'
  ============================================================
     FileVault Node  -  nginx camouflage + upload site
  ============================================================
B
  if load_env 2>/dev/null && [ -n "$PRIMARY" ]; then
    printf '   domain: %s%s%s   |   ' "$C_G" "$PRIMARY" "$C_0"
    if port_busy 443 && port_owner 443 | grep -qi nginx; then
      printf 'nginx on 443: %sACTIVE%s\n' "$C_G" "$C_0"
    else
      printf 'nginx on 443: %sinactive%s\n' "$C_Y" "$C_0"
    fi
  else
    printf '   %sNot configured yet - run option 1%s\n' "$C_Y" "$C_0"
  fi
  hr
}

wizard() {
  hr; echo " SETUP WIZARD"; hr
  echo "  Press Enter to keep the value shown in [brackets]."
  echo
  load_env 2>/dev/null
  local sd rd rp xp xpath cft mail mb rdays sname panel sshp

  ask sd    "Site / XHTTP subdomains (comma separated)" "${SITE_DOMAINS:-}"
  ask rd    "Reality domains (comma separated, empty = none)" "${REALITY_DOMAINS:-}"
  ask rp    "Local Reality port (as set in the panel)" "${XRAY_REALITY_PORT:-12000}"
  ask xp    "Local XHTTP port (as set in the panel)" "${XRAY_XHTTP_PORT:-12001}"
  echo "    -> If your client config has path=/?ed=2048 or path=/, answer with a single  /"
  ask xpath "XHTTP path from the client config" "${XRAY_XHTTP_PATH:-/}"
  ask panel "Pasarguard panel port" "${PANEL_PORT:-2053}"
  ask sshp  "SSH port" "${SSH_PORT:-22}"
  ask cft   "Cloudflare API token (Zone:Read + DNS:Edit)" "${CF_API_TOKEN:-}"
  ask mail  "Let's Encrypt e-mail" "${LE_EMAIL:-}"
  ask mb    "Max upload size (MB)" "${MAX_UPLOAD_MB:-50}"
  ask rdays "File retention (days)" "${RETENTION_DAYS:-7}"
  ask sname "Site name" "${SITE_NAME:-FileVault}"

  env_set SITE_DOMAINS      "$sd"
  env_set REALITY_DOMAINS   "$rd"
  env_set XRAY_REALITY_PORT "$rp"
  env_set XRAY_XHTTP_PORT   "$xp"
  env_set XRAY_XHTTP_PATH   "$xpath"
  env_set PANEL_PORT        "$panel"
  env_set SSH_PORT          "$sshp"
  env_set CF_API_TOKEN      "$cft"
  env_set LE_EMAIL          "$mail"
  env_set MAX_UPLOAD_MB     "$mb"
  env_set RETENTION_DAYS    "$rdays"
  env_set SITE_NAME         "$sname"
  env_set LOCAL_TLS_PORT    "${LOCAL_TLS_PORT:-8443}"
  chmod 600 "$ENV_FILE"
  ok "Settings saved to .env"

  need_docker || install_docker
  render_config
  echo
  if confirm "Start the backend now (site + SSL) WITHOUT touching port 443?"; then
    start_backend_only
    echo
    say "Next: menu 6 -> 1 to check the certificate, then menu 3 to cut over."
  fi
}

install_shortcut() {
  ln -sf "$FV_DIR/menu.sh" /usr/local/bin/fv
  chmod +x "$FV_DIR/menu.sh"
  ok "From now on just run:  sudo fv"
}

domains_menu() {
  load_env || return 1
  hr; echo " DOMAINS"; hr
  echo "  1) Add a site / XHTTP subdomain"
  echo "  2) Add a Reality domain"
  echo "  3) Remove a domain"
  echo "  4) Show current list"
  echo "  0) Back"
  local c d
  ask c "Choice" "0"
  case "$c" in
    1) ask d "New subdomain" ""; [ -n "$d" ] && { env_set SITE_DOMAINS "${SITE_DOMAINS:+$SITE_DOMAINS,}$d"; ok "Added"; warn "Re-issue the certificate: menu 6 -> 2"; render_config; } ;;
    2) ask d "New Reality domain" ""; [ -n "$d" ] && { env_set REALITY_DOMAINS "${REALITY_DOMAINS:+$REALITY_DOMAINS,}$d"; render_config; nginx_reload; } ;;
    3) ask d "Domain to remove" ""
       [ -n "$d" ] && {
         env_set SITE_DOMAINS    "$(echo "$SITE_DOMAINS"    | tr ',' '\n' | grep -vx "$d" | paste -sd, -)"
         env_set REALITY_DOMAINS "$(echo "$REALITY_DOMAINS" | tr ',' '\n' | grep -vx "$d" | paste -sd, -)"
         render_config; nginx_reload; } ;;
    4) printf '  site   : %s\n  reality: %s\n' "$SITE_DOMAINS" "${REALITY_DOMAINS:-none}" ;;
  esac
}

xray_menu() {
  load_env || return 1
  hr; echo " XRAY PORTS & PATH"; hr
  printf '  current: Reality=%s  XHTTP=%s  path=%s\n\n' "$XRAY_REALITY_PORT" "$XRAY_XHTTP_PORT" "$XRAY_XHTTP_PATH"
  local rp xp xpath
  ask rp    "Reality port" "$XRAY_REALITY_PORT"
  ask xp    "XHTTP port"   "$XRAY_XHTTP_PORT"
  ask xpath "XHTTP path (use / for root-path configs)" "$XRAY_XHTTP_PATH"
  env_set XRAY_REALITY_PORT "$rp"; env_set XRAY_XHTTP_PORT "$xp"; env_set XRAY_XHTTP_PATH "$xpath"
  render_config; nginx_reload
  warn "These must match the inbounds in your panel."
}

site_menu() {
  load_env || return 1
  hr; echo " UPLOAD SITE SETTINGS"; hr
  local mb rd sn
  ask mb "Max upload size (MB)" "$MAX_UPLOAD_MB"
  ask rd "File retention (days)" "$RETENTION_DAYS"
  ask sn "Site name" "$SITE_NAME"
  env_set MAX_UPLOAD_MB "$mb"; env_set RETENTION_DAYS "$rd"; env_set SITE_NAME "$sn"
  render_config; dc up -d --build php cleaner; nginx_reload
}

ssl_menu() {
  hr; echo " SSL (Cloudflare DNS-01)"; hr
  echo "  1) Certificate status"
  echo "  2) Issue / re-issue (after adding domains)"
  echo "  3) Force renew"
  echo "  4) Change Cloudflare token"
  echo "  0) Back"
  local c t
  ask c "Choice" "0"
  case "$c" in
    1) ssl_status ;;
    2) ssl_reissue ;;
    3) ssl_force ;;
    4) ask t "New token" ""; [ -n "$t" ] && { env_set CF_API_TOKEN "$t"; dc up -d --force-recreate certbot; ok "Token updated"; } ;;
  esac
}

logs_menu() {
  hr; echo "  1) nginx   2) php   3) certbot   4) cleaner   5) all   0) Back"
  local c; ask c "Choice" "0"
  case "$c" in
    1) dc logs --tail 100 -f nginx ;;
    2) dc logs --tail 100 -f php ;;
    3) dc logs --tail 100 -f certbot ;;
    4) dc logs --tail 100 -f cleaner ;;
    5) dc logs --tail 60 -f ;;
  esac
}

backup_now() {
  load_env || return 1
  local out="/root/filevault-backup-$(date +%F-%H%M).tar.gz"
  tar czf "$out" -C "$FV_DIR/.." --exclude='*/data/uploads/*' "$(basename "$FV_DIR")"
  ok "Backup created: $out"
  echo "  Copy to a new server:  scp $out root@NEW_IP:/root/"
}

update_self() {
  if [ -d "$FV_DIR/.git" ]; then
    ( cd "$FV_DIR" && git pull --ff-only ) && render_config && dc up -d --build && ok "Updated"
  else
    warn "This copy was not cloned from git. Update manually or re-install via git clone."
  fi
}

uninstall_all() {
  warn "Containers, generated nginx config and (optionally) uploaded files will be removed."
  confirm "Continue?" || return 0
  dc down -v
  rm -f /usr/local/bin/fv /etc/cron.d/filevault-reload
  confirm "Delete uploaded files (data/) as well?" && rm -rf "$FV_DIR/data/uploads" "$FV_DIR/data/meta"
  ok "Removed. Port 443 is free."
}

main_menu() {
  while true; do
    banner
    cat <<'M'
   1) Setup wizard (domains, ports, path, CF token, limits)
   2) Preflight check
   3) Zero-downtime cutover  ->  put nginx on 443
   4) Node status
   5) Domains (add / remove)
   6) SSL
   7) Xray ports & path
   8) Upload site settings (size / retention / name)
   9) Firewall (UFW)
  10) Restart services
  11) Reload nginx
  12) Logs
  13) Site self-test
  14) Run cleanup now (delete expired files)
  15) Backup for moving to a new server
  16) Rollback - stop nginx and free port 443
  17) Update from GitHub
  18) Install  sudo fv  shortcut
  19) Uninstall everything
   0) Exit
M
    hr
    local c; ask c "Option" ""
    echo
    case "$c" in
      1) wizard; pause ;;
      2) preflight; pause ;;
      3) cutover; pause ;;
      4) status; pause ;;
      5) domains_menu; pause ;;
      6) ssl_menu; pause ;;
      7) xray_menu; pause ;;
      8) site_menu; pause ;;
      9) apply_firewall; pause ;;
      10) restart_all; pause ;;
      11) nginx_reload; pause ;;
      12) logs_menu; pause ;;
      13) selftest; pause ;;
      14) dc exec -T cleaner sh /cleanup.sh; pause ;;
      15) backup_now; pause ;;
      16) rollback; pause ;;
      17) update_self; pause ;;
      18) install_shortcut; pause ;;
      19) uninstall_all; pause ;;
      0|q) exit 0 ;;
      *) warn "Invalid option"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  ""|menu)   main_menu ;;
  install)   wizard; install_shortcut ;;
  up)        build_up ;;
  down)      stop_all ;;
  status)    status ;;
  cutover)   cutover ;;
  rollback)  rollback ;;
  preflight) preflight ;;
  reload)    nginx_reload ;;
  test)      selftest ;;
  firewall)  apply_firewall ;;
  backup)    backup_now ;;
  *) echo "usage: fv [menu|install|up|down|status|preflight|cutover|rollback|reload|test|firewall|backup]" ;;
esac
