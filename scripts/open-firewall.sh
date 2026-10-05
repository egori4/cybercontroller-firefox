#!/usr/bin/env bash
set -euo pipefail

HOST_PORT="${HOST_PORT:-3010}"
CHAIN="${CHAIN:-DOCKER-USER}"
IPTABLES="${IPTABLES:-iptables}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

if ! "${IPTABLES}" -S "${CHAIN}" >/dev/null 2>&1; then
  echo "ERROR: iptables chain '${CHAIN}' does not exist."
  exit 1
fi

# DOCKER-USER is evaluated after Docker DNAT. Matching --dport ${HOST_PORT}
# therefore does not work for a published host port. Match the original
# destination port from conntrack instead.
RULE=(-p tcp -m conntrack --ctorigdstport "${HOST_PORT}" -j ACCEPT)

if "${IPTABLES}" -C "${CHAIN}" "${RULE[@]}" >/dev/null 2>&1; then
  echo "Firewall rule already present for original TCP port ${HOST_PORT}."
else
  "${IPTABLES}" -I "${CHAIN}" 2 "${RULE[@]}"
  echo "Added DOCKER-USER allow rule for original TCP port ${HOST_PORT}."
fi

"${IPTABLES}" -L "${CHAIN}" -n -v --line-numbers | head -n 8
