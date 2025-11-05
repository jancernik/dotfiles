#!/usr/bin/env bash

# Manage brightness of all connected monitors via DDC/CI

set -euo pipefail

brightness="${1:-}"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/brightness"

get_bus_ids() {
  ddcutil detect --terse | awk '
    /I2C bus:/ {
      if (match($0, /\/dev\/i2c-([0-9]+)/, m)) {
        bus = m[1]
        next
      }
    }
    /Monitor:/ {
      if (bus != "") {
        print bus
        bus = ""
      }
    }
  ' | sort -n | uniq
}

show_current_brightness() {
  local bus="$1"
  local value
  value=$(ddcutil --bus "$bus" getvcp 0x10 --terse 2>/dev/null | awk '{print $4}')
  echo -n "${value}% "
}

get_brightness() {
  local bus="$1"
  ddcutil --bus "$bus" getvcp 0x10 --terse 2>/dev/null | awk '{print $4}'
}

save_brightness() {
  mkdir -p "$STATE_DIR"
  : > "$STATE_FILE"
  
  for bus in "${bus_ids[@]}"; do
    local value
    value=$(get_brightness "$bus")
    echo "$bus:$value" >> "$STATE_FILE"
  done
  
  echo "Brightness saved"
}

restore_brightness() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "No saved brightness values found."
    exit 1
  fi
  
  pids=()
  while IFS=: read -r bus value; do
    if [[ -n "$bus" && -n "$value" ]]; then
      set_brightness "$bus" "$value" &
      pids+=("$!")
    fi
  done < "$STATE_FILE"
  
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
  
  echo "Brightness restored."
}

set_brightness() {
  local bus="$1"
  local value="$2"
  
  sleep "$(awk -v r="$RANDOM" 'BEGIN{printf "%.3f", (r % 40) / 1000.0}')"
  
  ddcutil --bus "$bus" --noverify --sleep-multiplier=0.6 setvcp 0x10 "$value" >/dev/null 2>&1 ||
  {
    sleep 0.2
    ddcutil --bus "$bus" --sleep-multiplier=1.0 setvcp 0x10 "$value" >/dev/null 2>&1
  }
}

adjust_brightness() {
  local bus="$1"
  local adjustment="$2"
  local operator="$3"
  
  sleep "$(awk -v r="$RANDOM" 'BEGIN{printf "%.3f", (r % 40) / 1000.0}')"
  
  ddcutil --bus "$bus" --noverify --sleep-multiplier=0.6 setvcp 0x10 "$operator" "$adjustment" >/dev/null 2>&1 ||
  {
    sleep 0.2
    ddcutil --bus "$bus" --sleep-multiplier=1.0 setvcp 0x10 "$operator" "$adjustment" >/dev/null 2>&1
  }
}

mapfile -t bus_ids < <(get_bus_ids)

if [[ ${#bus_ids[@]} -eq 0 ]]; then
  echo "No DDC/CI-capable displays found."
  exit 1
fi

case "$brightness" in
  s|save)
    save_brightness
    exit 0
    ;;
  r|restore)
    restore_brightness
    exit 0
    ;;
  "")
    echo -n "Current brightness: "
    for bus in "${bus_ids[@]}"; do
      show_current_brightness "$bus"
    done
    echo
    exit 0
    ;;
esac

if [[ "$brightness" =~ ^[+-][0-9]{1,3}$ ]]; then
  operator="${brightness:0:1}"
  amount="${brightness:1}"
  
  if [[ $amount -lt 0 ]] || [[ $amount -gt 100 ]]; then
    echo "Usage: b [0..100|+N|-N|s|save|r|restore]"
    exit 1
  fi
  
  echo "Adjusting brightness: ${brightness}%"
  pids=()
  for bus in "${bus_ids[@]}"; do
    adjust_brightness "$bus" "$amount" "$operator" &
    pids+=("$!")
  done
  
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
  
  exit 0
fi

if ! [[ "$brightness" =~ ^[0-9]{1,3}$ ]] || [[ $brightness -lt 0 ]] || [[ $brightness -gt 100 ]]; then
  echo "Usage: b [0..100|+N|-N|s|save|r|restore]"
  exit 1
fi

echo "Setting brightness: ${brightness}%"
pids=()
for bus in "${bus_ids[@]}"; do
  set_brightness "$bus" "$brightness" &
  pids+=("$!")
done

for pid in "${pids[@]}"; do
  wait "$pid"
done