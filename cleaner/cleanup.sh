#!/bin/sh
# Removes uploads (and their metadata) older than RETENTION_DAYS.
set -eu
DAYS="${RETENTION_DAYS:-7}"
ROOT=/var/www/data

[ -d "$ROOT/uploads" ] || exit 0
find "$ROOT/uploads" -mindepth 1 -maxdepth 1 -type d -mtime +"$DAYS" -exec rm -rf {} + 2>/dev/null || true
[ -d "$ROOT/meta" ] && find "$ROOT/meta" -type f -name '*.json' -mtime +"$DAYS" -delete 2>/dev/null || true
# drop metadata whose folder is gone
if [ -d "$ROOT/meta" ]; then
  for m in "$ROOT/meta"/*.json; do
    [ -e "$m" ] || continue
    id=$(basename "$m" .json)
    [ -d "$ROOT/uploads/$id" ] || rm -f "$m"
  done
fi
echo "[cleanup] $(date -u '+%F %T') done (retention ${DAYS}d)"
