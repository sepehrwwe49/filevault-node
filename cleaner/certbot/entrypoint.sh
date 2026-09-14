#!/bin/sh
# Issues the certificate on first run, then renews twice a day (DNS-01 via Cloudflare).
# Certificates are published to /etc/letsencrypt/current so nginx always points at
# one fixed path and never needs its config re-rendered after issuance.
set -eu
CRED=/etc/letsencrypt/cloudflare.ini
CUR=/etc/letsencrypt/current
mkdir -p /etc/letsencrypt "$CUR"
printf 'dns_cloudflare_api_token = %s\n' "$CF_API_TOKEN" > "$CRED"
chmod 600 "$CRED"

PRIMARY=$(echo "$SITE_DOMAINS" | cut -d, -f1)
ARGS=""
for d in $(echo "$SITE_DOMAINS" | tr ',' ' '); do ARGS="$ARGS -d $d"; done

publish() {
  LIVE="/etc/letsencrypt/live/$PRIMARY"
  if [ -f "$LIVE/fullchain.pem" ] && [ -f "$LIVE/privkey.pem" ]; then
    cp -L "$LIVE/fullchain.pem" "$CUR/fullchain.pem.new"
    cp -L "$LIVE/privkey.pem"   "$CUR/privkey.pem.new"
    mv "$CUR/fullchain.pem.new" "$CUR/fullchain.pem"
    mv "$CUR/privkey.pem.new"   "$CUR/privkey.pem"
    chmod 644 "$CUR/fullchain.pem"; chmod 640 "$CUR/privkey.pem"
    date -u +%s > "$CUR/.reload"        # nginx watcher picks this up
    echo "[certbot] published certificate to $CUR"
  fi
}

if [ ! -f "/etc/letsencrypt/renewal/$PRIMARY.conf" ]; then
  # a stale bootstrap cert must never block issuance
  [ -d "/etc/letsencrypt/live/$PRIMARY" ] && rm -rf "/etc/letsencrypt/live/$PRIMARY"
  echo "[certbot] issuing certificate for: $SITE_DOMAINS"
  certbot certonly --non-interactive --agree-tos --email "$LE_EMAIL" \
    --dns-cloudflare --dns-cloudflare-credentials "$CRED" \
    --dns-cloudflare-propagation-seconds 30 \
    --cert-name "$PRIMARY" $ARGS --key-type ecdsa || echo "[certbot] issue FAILED"
fi
publish

while true; do
  sleep 43200
  echo "[certbot] renew check $(date -u '+%F %T')"
  certbot renew --non-interactive --quiet \
    --dns-cloudflare --dns-cloudflare-credentials "$CRED" \
    --dns-cloudflare-propagation-seconds 30 || true
  publish
done
