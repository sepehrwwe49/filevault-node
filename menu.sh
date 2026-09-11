#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  FileVault Node — منوی مدیریت
#  اجرا:  sudo bash menu.sh      یا بعد از نصب:  sudo fv
# ---------------------------------------------------------------------------
FV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$FV_DIR/lib/core.sh"

[ "$(id -u)" -eq 0 ] || die "با root اجرا کن:  sudo bash menu.sh"

banner() {
  clear
  cat <<'B'
  ╔══════════════════════════════════════════════════════════╗
  ║   FileVault Node  ·  nginx camouflage + upload site       ║
  ╚══════════════════════════════════════════════════════════╝
B
  if load_env 2>/dev/null && [ -n "$PRIMARY" ]; then
    printf '   دامنه: %s%s%s   |   ' "$C_G" "$PRIMARY" "$C_0"
    if port_busy 443 && port_owner 443 | grep -qi nginx; then
      printf 'nginx روی 443: %sفعال%s\n' "$C_G" "$C_0"
    else
      printf 'nginx روی 443: %sغیرفعال%s\n' "$C_Y" "$C_0"
    fi
  else
    printf '   %sهنوز پیکربندی نشده — گزینه ۱ را بزن%s\n' "$C_Y" "$C_0"
  fi
  hr
}

wizard() {
  hr; echo " نصب اولیه / پیکربندی"; hr
  echo "  هر چیزی که خالی بگذاری، مقدار داخل [] استفاده می‌شود."
  echo
  load_env 2>/dev/null
  local sd rd rp xp xpath cft mail mb rd7 sname panel sshp

  ask sd    "ساب‌دامنه‌های سایت/XHTTP (با کاما)" "${SITE_DOMAINS:-}"
  ask rd    "دامنه‌های Reality (با کاما، خالی=ندارم)" "${REALITY_DOMAINS:-}"
  ask rp    "پورت لوکال Reality در پنل" "${XRAY_REALITY_PORT:-12000}"
  ask xp    "پورت لوکال XHTTP در پنل" "${XRAY_XHTTP_PORT:-12001}"
  ask xpath "path کانفیگ XHTTP (بدون /)" "${XRAY_XHTTP_PATH:-xhttp}"
  ask panel "پورت پنل پاسارگاد" "${PANEL_PORT:-2053}"
  ask sshp  "پورت SSH" "${SSH_PORT:-22}"
  ask cft   "توکن API کلودفلر (Zone:Read + DNS:Edit)" "${CF_API_TOKEN:-}"
  ask mail  "ایمیل Let's Encrypt" "${LE_EMAIL:-}"
  ask mb    "سقف آپلود (MB)" "${MAX_UPLOAD_MB:-50}"
  ask rd7   "نگهداری فایل (روز)" "${RETENTION_DAYS:-7}"
  ask sname "نام سایت" "${SITE_NAME:-FileVault}"

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
  env_set RETENTION_DAYS    "$rd7"
  env_set SITE_NAME         "$sname"
  env_set LOCAL_TLS_PORT    "${LOCAL_TLS_PORT:-8443}"
  chmod 600 "$ENV_FILE"
  ok "تنظیمات ذخیره شد در .env"

  need_docker || install_docker
  render_config
  echo
  if confirm "الان بک‌اند (سایت + SSL) بدون اشغال پورت 443 بالا بیاید؟"; then
    start_backend_only
    echo
    say "برای گرفتن گواهی: منو → ۶ → صدور مجدد. بعد گزینه ۳ (سوییچ) را بزن."
  fi
}

install_shortcut() {
  ln -sf "$FV_DIR/menu.sh" /usr/local/bin/fv
  chmod +x "$FV_DIR/menu.sh"
  ok "از این به بعد فقط کافیست بزنی:  sudo fv"
}

domains_menu() {
  load_env || return 1
  hr; echo " مدیریت دامنه‌ها"; hr
  echo "  1) افزودن ساب‌دامنه سایت/XHTTP"
  echo "  2) افزودن دامنه Reality"
  echo "  3) حذف یک دامنه"
  echo "  4) نمایش لیست"
  echo "  0) بازگشت"
  local c d
  ask c "انتخاب" "0"
  case "$c" in
    1) ask d "ساب‌دامنه جدید" ""; [ -n "$d" ] && { env_set SITE_DOMAINS "${SITE_DOMAINS:+$SITE_DOMAINS,}$d"; ok "اضافه شد"; warn "برای گواهی جدید: منو → ۶ → صدور مجدد"; render_config; } ;;
    2) ask d "دامنه Reality جدید" ""; [ -n "$d" ] && { env_set REALITY_DOMAINS "${REALITY_DOMAINS:+$REALITY_DOMAINS,}$d"; render_config; nginx_reload; } ;;
    3) ask d "دامنه‌ای که حذف شود" ""
       [ -n "$d" ] && {
         env_set SITE_DOMAINS    "$(echo "$SITE_DOMAINS"    | tr ',' '\n' | grep -vx "$d" | paste -sd, -)"
         env_set REALITY_DOMAINS "$(echo "$REALITY_DOMAINS" | tr ',' '\n' | grep -vx "$d" | paste -sd, -)"
         render_config; nginx_reload; } ;;
    4) printf '  سایت   : %s\n  Reality: %s\n' "$SITE_DOMAINS" "${REALITY_DOMAINS:-—}" ;;
  esac
}

xray_menu() {
  load_env || return 1
  hr; echo " پورت‌ها و path ایکس‌ری"; hr
  printf '  فعلی: Reality=%s  XHTTP=%s  path=/%s\n\n' "$XRAY_REALITY_PORT" "$XRAY_XHTTP_PORT" "$XRAY_XHTTP_PATH"
  local rp xp xpath
  ask rp    "پورت Reality" "$XRAY_REALITY_PORT"
  ask xp    "پورت XHTTP"   "$XRAY_XHTTP_PORT"
  ask xpath "path (بدون /)" "$XRAY_XHTTP_PATH"
  env_set XRAY_REALITY_PORT "$rp"; env_set XRAY_XHTTP_PORT "$xp"; env_set XRAY_XHTTP_PATH "$xpath"
  render_config; nginx_reload
  warn "همین مقادیر باید در اینباندهای پنل هم ست باشد."
}

site_menu() {
  load_env || return 1
  hr; echo " تنظیمات سایت آپلود"; hr
  local mb rd sn
  ask mb "سقف آپلود (MB)" "$MAX_UPLOAD_MB"
  ask rd "نگهداری فایل (روز)" "$RETENTION_DAYS"
  ask sn "نام سایت" "$SITE_NAME"
  env_set MAX_UPLOAD_MB "$mb"; env_set RETENTION_DAYS "$rd"; env_set SITE_NAME "$sn"
  render_config; dc up -d --build php cleaner; nginx_reload
}

ssl_menu() {
  hr; echo " SSL (DNS-01 کلودفلر)"; hr
  echo "  1) وضعیت گواهی‌ها"
  echo "  2) صدور مجدد / اضافه کردن دامنه‌های جدید"
  echo "  3) تمدید اجباری"
  echo "  4) تغییر توکن کلودفلر"
  echo "  0) بازگشت"
  local c t
  ask c "انتخاب" "0"
  case "$c" in
    1) ssl_status ;;
    2) ssl_reissue ;;
    3) ssl_force ;;
    4) ask t "توکن جدید" ""; [ -n "$t" ] && { env_set CF_API_TOKEN "$t"; dc up -d --force-recreate certbot; ok "ست شد"; } ;;
  esac
}

logs_menu() {
  hr; echo "  1) nginx   2) php   3) certbot   4) cleaner   5) همه   0) بازگشت"
  local c; ask c "انتخاب" "0"
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
  ok "بکاپ ساخته شد: $out"
  echo "  انتقال به سرور جدید:  scp $out root@NEW_IP:/root/"
}

update_self() {
  if [ -d "$FV_DIR/.git" ]; then
    ( cd "$FV_DIR" && git pull --ff-only ) && render_config && dc up -d --build && ok "به‌روزرسانی شد"
  else
    warn "این نسخه از گیت کلون نشده. دستی آپدیت کن یا با git clone دوباره نصب کن."
  fi
}

uninstall_all() {
  warn "کانتینرها، کانفیگ nginx و (اختیاری) فایل‌های آپلودشده حذف می‌شوند."
  confirm "ادامه؟" || return 0
  dc down -v
  rm -f /usr/local/bin/fv /etc/cron.d/filevault-reload
  confirm "فایل‌های آپلودشده (data/) هم پاک شود؟" && rm -rf "$FV_DIR/data/uploads" "$FV_DIR/data/meta"
  ok "حذف شد. پورت 443 آزاد است."
}

main_menu() {
  while true; do
    banner
    cat <<'M'
   1) نصب اولیه / تغییر تنظیمات (ویزارد)
   2) بررسی پیش از سوییچ (preflight)
   3) سوییچ بدون قطعی → نشاندن nginx روی 443
   4) وضعیت نود
   5) دامنه‌ها (افزودن / حذف)
   6) SSL
   7) پورت‌ها و path ایکس‌ری
   8) تنظیمات سایت آپلود (حجم / مدت نگهداری / نام)
   9) فایروال (UFW)
  10) ری‌استارت سرویس‌ها
  11) ری‌لود nginx
  12) لاگ‌ها
  13) تست سایت (self-test)
  14) پاک‌سازی دستی فایل‌های منقضی
  15) بکاپ برای انتقال به سرور جدید
  16) بازگشت (rollback) — خاموش کردن nginx و آزادسازی 443
  17) به‌روزرسانی از گیت‌هاب
  18) نصب میانبر  sudo fv
  19) حذف کامل
   0) خروج
M
    hr
    local c; ask c "گزینه" ""
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
      *) warn "گزینه نامعتبر"; sleep 1 ;;
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
