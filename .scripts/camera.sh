#!/usr/bin/env bash

# Control via v4l2-ctl with profile management

set -euo pipefail

DEVICE="/dev/video0"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/camera"

save_settings() {
  local settings_name="$1"
  local full_path="$STATE_DIR/$settings_name"

  mkdir -p "$STATE_DIR"

  v4l2-ctl -d "$DEVICE" --list-ctrls | grep 'value=' | sed -E 's/.* ([a-zA-Z_]+) .*value=([0-9]+).*/\1=\2/' > "$full_path"
  echo "Settings saved to $full_path"
}

restore_settings() {
  local settings_name="$1"
  local full_path="$STATE_DIR/$settings_name"
  local failed_controls=()

  if [[ ! -f "$full_path" ]]; then
    echo "Settings file not found: $settings_name"
    exit 1
  fi

  while IFS='=' read -r control value; do
    if ! v4l2-ctl -d "$DEVICE" --set-ctrl "$control=$value" >/dev/null 2>&1; then
      failed_controls+=("$control")
    fi
  done < "$full_path"

  echo "Settings restored from $full_path"

  if [[ ${#failed_controls[@]} -gt 0 ]]; then
    echo "Warning: Failed to set the following controls (likely read-only):"
    printf '  - %s\n' "${failed_controls[@]}"
  fi
}

remove_settings() {
  local settings_name="$1"
  local full_path="$STATE_DIR/$settings_name"

  if [[ ! -f "$full_path" ]]; then
    echo "Settings file not found: $settings_name"
    exit 1
  fi

  rm "$full_path"
  echo "Removed profile: $settings_name"
}

set_or_get_control() {
  local control="$1"
  local value="${2:-}"

  if [[ -z "$value" ]]; then
    local current_value control_line min_value max_value
    current_value=$(v4l2-ctl -d "$DEVICE" --get-ctrl="$control" | awk '{print $NF}')
    echo "Value: $current_value"

    control_line=$(v4l2-ctl -d "$DEVICE" --list-ctrls | grep "$control")

    min_value=$(echo "$control_line" | sed -n 's/.*min=\([^ ]*\).*/\1/p')
    max_value=$(echo "$control_line" | sed -n 's/.*max=\([^ ]*\).*/\1/p')

    echo "Min: $min_value"
    echo "Max: $max_value"
  else
    v4l2-ctl -d "$DEVICE" --set-ctrl="$control=$value"
  fi
}

list_saves() {
  if [[ ! -d "$STATE_DIR" ]]; then
    echo "No saved profiles found."
    exit 0
  fi

  local saves
  saves=$(ls -1 "$STATE_DIR" 2>/dev/null || true)

  if [[ -z "$saves" ]]; then
    echo "No saved profiles found."
  else
    echo "Saved profiles:"
    echo "$saves"
  fi
}

list_controls() {
  v4l2-ctl -d "$DEVICE" --list-ctrls | awk '
    /:/{
        gsub(/.* /, "", $1);
        control=$1;
        gsub(/.*: /, "", $0);
        print control " - " $0
    }'
}

command="${1:-}"

case "$command" in
  save)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: camera save <profile_name>"
      exit 1
    fi
    save_settings "$2"
    ;;

  restore)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: camera restore <profile_name>"
      exit 1
    fi
    restore_settings "$2"
    ;;

  remove|rm|delete)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: camera remove <profile_name>"
      exit 1
    fi
    remove_settings "$2"
    ;;

  list|ls|saves)
    list_saves
    ;;

  "")
    list_controls
    ;;

  *)
    set_or_get_control "$command" "${2:-}"
    ;;
esac
