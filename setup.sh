#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  FileVault Node - bootstrap installer
#  bash <(curl -fsSL https://raw.githubusercontent.com/sepehrwwe49/filevault-node/main/setup.sh)
# ---------------------------------------------------------------------------
set -euo pipefail
REPO="${FV_REPO:-https://github.com/sepehrwwe49/filevault-node.git}"
DEST="${FV_DEST:-/opt/filevault}"
BRANCH="${FV_BRANCH:-main}"

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)"; exit 1; }

echo "[*] Installing prerequisites..."
if command -v apt-get >/dev/null; then
  apt-get update -y
  apt-get install -y git curl openssl python3 ca-certificates iproute2 tar
elif command -v dnf >/dev/null; then
  dnf install -y git curl openssl python3 ca-certificates iproute tar
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "[*] Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker 2>/dev/null || true
fi

if [ -d "$DEST/.git" ]; then
  echo "[*] Updating existing checkout..."
  git -C "$DEST" pull --ff-only
else
  echo "[*] Cloning into $DEST ..."
  rm -rf "$DEST"
  git clone -b "$BRANCH" --depth 1 "$REPO" "$DEST"
fi

chmod +x "$DEST/menu.sh"
ln -sf "$DEST/menu.sh" /usr/local/bin/fv
echo "[OK] Installed. Open the menu any time with:  sudo fv"
exec bash "$DEST/menu.sh"
