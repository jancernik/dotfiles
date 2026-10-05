#!/usr/bin/env bash

# Brightness daemon and command-line client.

set -euo pipefail

dir() {
  cd "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd
}

if [[ "${1:-}" == "daemon" ]]; then
  exec "$(dir)/supervisor.sh"
fi

fast_change() {
  local monitor="all"
  if [[ $# -eq 3 && ("$1" == "-m" || "$1" == "--monitor") ]]; then
    monitor="$2"
    shift 2
  fi
  [[ $# -eq 1 && "$1" =~ ^[+-]?[0-9]{1,3}$ && "$monitor" =~ ^[A-Za-z0-9:_.-]+$ ]] || return 2
  local socket="${XDG_RUNTIME_DIR:-}/minishell/brightness.sock"
  [[ -S "$socket" ]] && command -v socat >/dev/null || return 2
  local request response
  request="{\"action\": \"set\", \"selector\": \"$monitor\", \"change\": \"$1\"}"
  response="$(printf '%s\n' "$request" | socat -t 1 - "UNIX-CONNECT:$socket" 2>/dev/null)" || return 2
  [[ -n "$response" ]] || return 2
  if [[ "$response" =~ \"ok\":\ *true ]]; then
    return 0
  fi
  echo "brightness: $response" >&2
  return 1
}

status=0
fast_change "$@" || status=$?
if [[ $status -ne 2 ]]; then
  exit "$status"
fi

exec python3 "$(dir)/main.py" "$@"
