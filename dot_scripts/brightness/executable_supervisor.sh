#!/usr/bin/env bash
set -uo pipefail

script_dir="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
child=""

stop() {
    trap - INT TERM
    if [[ -n "$child" ]]; then
        kill "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
    exit 0
}
trap stop INT TERM

while true; do
    "$script_dir/main.py" daemon &
    child=$!
    wait "$child"
    result=$?
    child=""
    if ((result == 2)); then
        exit 0
    fi
    sleep 3
done
