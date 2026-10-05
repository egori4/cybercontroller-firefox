#!/usr/bin/env bash
set -euo pipefail

HOST_PORT="${HOST_PORT:-3010}"
CHAIN="${CHAIN:-DOCKER-USER}"
IPTABLES="${IPTABLES:-iptables}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

RULE=(-p tcp -m conntrack --ctorigdstport "${HOST_PORT}" -j ACCEPT)

if "${IPTABLES}" -C "${CHAIN}" "${RULE[@]}" >/dev/null 2>&1; then
  "${IPTABLES}" -D "${CHAIN}" "${RULE[@]}"
  echo "Removed DOCKER-USER allow rule for original TCP port ${HOST_PORT}."
else
  echo "Firewall rule not present."
fi
