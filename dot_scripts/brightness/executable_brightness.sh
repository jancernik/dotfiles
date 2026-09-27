#!/usr/bin/env bash

# Brightness daemon and command-line client.

set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"

if [[ "${1:-}" == "daemon" ]]; then
  exec "$DIR/supervisor.sh"
fi

exec python3 "$DIR/main.py" "$@"
