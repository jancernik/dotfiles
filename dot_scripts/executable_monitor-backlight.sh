#!/usr/bin/env bash

# Manage monitor backlight via Home Assistant

set -euo pipefail

source "$HOME/.scripts/.env"

command="${1:-}"
value="${2:-}"

api_call() {
  local endpoint="$1"
  local data="$2"
  
  curl -s \
    -H "Authorization: Bearer $HOME_ASSISTANT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$data" \
    "https://homelocal.cuasar.cc/api/services/light/$endpoint" >/dev/null 2>&1
}

get_state() {
  curl -s \
    -H "Authorization: Bearer $HOME_ASSISTANT_TOKEN" \
    -H "Content-Type: application/json" \
    "https://homelocal.cuasar.cc/api/states/light.monitor_backlight"
}

to_percentage() {
  local value="$1"
  echo "$(( (value * 100) / 255 ))"
}

from_percentage() {
  local value="$1"
  echo "$(( (value * 255) / 100 ))"
}

show_current() {
  local response brightness_raw brightness_pct color_temp max_temp min_temp
  
  response=$(get_state)
  brightness_raw=$(echo "$response" | jq -r '.attributes.brightness // "null"')
  color_temp=$(echo "$response" | jq -r '.attributes.color_temp_kelvin // "null"')
  max_temp=$(echo "$response" | jq -r '.attributes.max_color_temp_kelvin // "null"')
  min_temp=$(echo "$response" | jq -r '.attributes.min_color_temp_kelvin // "null"')
  
  if [[ "$brightness_raw" == "null" ]]; then
    brightness_pct="off"
  else
    brightness_pct="$(to_percentage "$brightness_raw")%"
  fi
  
  echo "Brightness: $brightness_pct | Color Temp: $color_temp (${min_temp}-${max_temp}K)"
}

case "$command" in
  on)
    api_call "turn_on" '{"entity_id": "light.monitor_backlight"}'
    ;;
  
  off)
    api_call "turn_off" '{"entity_id": "light.monitor_backlight"}'
    ;;
  
  toggle)
    response=$(get_state)
    brightness=$(echo "$response" | jq -r '.attributes.brightness // "null"')
    
    if [[ "$brightness" == "null" ]]; then
      api_call "turn_on" '{"entity_id": "light.monitor_backlight"}'
    else
      api_call "turn_off" '{"entity_id": "light.monitor_backlight"}'
    fi
    ;;
  
  -b)
    if [[ -z "$value" ]] || ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -gt 100 ]]; then
      echo "Usage: $0 -b <0-100>"
      exit 1
    fi
    brightness_255=$(from_percentage "$value")
    api_call "turn_on" "{\"entity_id\": \"light.monitor_backlight\", \"brightness\": $brightness_255}"
    ;;
  
  -t)
    if [[ -z "$value" ]] || ! [[ "$value" =~ ^[0-9]+$ ]]; then
      echo "Usage: $0 -t <kelvin>"
      exit 1
    fi
    api_call "turn_on" "{\"entity_id\": \"light.monitor_backlight\", \"color_temp_kelvin\": $value}"
    ;;
  
  "")
    response=$(get_state)
    brightness=$(echo "$response" | jq -r '.attributes.brightness // "null"')
    
    if [[ "$brightness" == "null" ]]; then
      api_call "turn_on" '{"entity_id": "light.monitor_backlight"}'
    else
      api_call "turn_off" '{"entity_id": "light.monitor_backlight"}'
    fi
    ;;
  
  *)
    show_current
    ;;
esac