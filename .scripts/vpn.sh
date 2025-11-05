#!/usr/bin/env bash

# Control WireGuard VPN state

set -euo pipefail

state="${1:-}"

case "$state" in
  on)
    sudo wg-quick up vpn
    exit 0
    ;;
  off)
    sudo wg-quick down vpn
    exit 0
    ;;
  "")
	if [[ -n $(ip l | grep vpn) ]]; then
	  echo "on"
	else
	  echo "off"
	fi
    exit 0
    ;;
  *)
    echo "Usage: vpn [on|off]"
    exit 1
    ;;
esac
