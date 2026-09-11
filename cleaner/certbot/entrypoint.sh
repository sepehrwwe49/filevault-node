#!/bin/sh
# Issues the certificate on first run, then renews it twice a day (DNS-01 via Cloudflare).
set -eu
CRED=/etc/letsencrypt/cloudflare.ini
mkdir -p /etc/letsencrypt
printf 'dns_cloudflare_api_token = %s\n' "$CF_API_TOKEN" > "$CRED"
chmod 600 "$CRED"

PRIMARY=$(echo "$SITE_DOMAINS" | cut -d, -f1)
ARGS=""
for d in $(echo "$SITE_DOMAINS" | tr ',' ' '); do ARGS="$ARGS -d $d"; done

if [ ! -f "/etc/letsencrypt/live/$PRIMARY/fullchain.pem" ]; then
  echo "[certbot] issuing certificate for: $SITE_DOMAINS"
  certbot certonly --non-interactive --agree-tos --email "$LE_EMAIL" \
    --dns-cloudflare --dns-cloudflare-credentials "$CRED" \
    --dns-cloudflare-propagation-seconds 30 \
    --cert-name "$PRIMARY" $ARGS --key-type ecdsa || echo "[certbot] issue FAILED"
fi

while true; do
  sleep 43200
  echo "[certbot] renew check $(date -u '+%F %T')"
  certbot renew --non-interactive --quiet \
    --dns-cloudflare --dns-cloudflare-credentials "$CRED" \
    --dns-cloudflare-propagation-seconds 30 || true
done
