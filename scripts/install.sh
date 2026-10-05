#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: docker is required."
  exit 1
}

docker compose version >/dev/null 2>&1 || {
  echo "ERROR: Docker Compose plugin is required."
  exit 1
}

UPLOAD_TEMP_DIR="/opt/radware/storage/uploads/temp"
MAINTENANCE_DIR="/opt/radware/storage/maintenance"
CONFIG_DIR="/opt/firefox-browser/config"
MAINTENANCE_DOWNLOAD_DIR="${MAINTENANCE_DIR}/browser-downloads"

if [[ ! -d "${UPLOAD_TEMP_DIR}" ]]; then
  echo "ERROR: ${UPLOAD_TEMP_DIR} does not exist."
  echo "This guide expects CyberController's existing uploads/temp path (plural 'uploads')."
  exit 1
fi

if [[ ! -d "${MAINTENANCE_DIR}" ]]; then
  echo "ERROR: ${MAINTENANCE_DIR} does not exist."
  exit 1
fi

mkdir -p "${CONFIG_DIR}" "${MAINTENANCE_DOWNLOAD_DIR}"
chown -R 1003:1003 "${CONFIG_DIR}"
chown 1003:1003 "${MAINTENANCE_DOWNLOAD_DIR}"
chmod 700 "${MAINTENANCE_DOWNLOAD_DIR}"

if [[ ! -f .env ]]; then
  command -v openssl >/dev/null 2>&1 || {
    echo "ERROR: openssl is required to generate the initial password."
    exit 1
  }

  PASSWORD="$(openssl rand -hex 18)"
  cp .env.example .env
  sed -i "s/^PASSWORD=.*/PASSWORD=${PASSWORD}/" .env
  chmod 600 .env

  echo
  echo "Generated Firefox web credentials:"
  echo "  Username: admin"
  echo "  Password: ${PASSWORD}"
  echo "  Stored in: ${ROOT_DIR}/.env"
  echo
fi

if ss -lnt 2>/dev/null | grep -qE "[:.]3010[[:space:]]"; then
  if ! docker ps --format '{{.Names}}' | grep -qx firefox; then
    echo "ERROR: host TCP port 3010 is already in use."
    exit 1
  fi
fi

docker compose pull
docker compose up -d

echo
docker compose ps
echo
echo "Firefox started. Next:"
echo "  sudo ${ROOT_DIR}/scripts/open-firewall.sh"
echo "  Browse to https://<CyberController-IP>:3010"
