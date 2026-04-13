#!/usr/bin/env bash

# Toggle my homelab web dashboard

set -euo pipefail

URL="https://dash.cuasar.cc"
TARGET_CLASS="brave-browser"
TARGET_TITLE="Cuasar Dashboard - Brave"

active_json="$(hyprctl activewindow -j 2>/dev/null || true)"

if [[ -z "$active_json" ]]; then
  exec brave --new-window "$URL"
fi

active_class="$(jq -r '.class // ""' <<< "$active_json")"
active_title="$(jq -r '.title // ""' <<< "$active_json")"
active_address="$(jq -r '.address // ""' <<< "$active_json")"

if [[ "$active_class" == "$TARGET_CLASS" ]]; then
  if [[ "$active_title" == "$TARGET_TITLE" ]]; then
    exec hyprctl dispatch sendshortcut "CONTROL,W,address:$active_address"
  else
    exec brave "$URL"
  fi
else
  exec brave --new-window "$URL"
fi
