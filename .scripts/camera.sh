#!/usr/bin/env bash

# Control via v4l2-ctl with profile management

set -euo pipefail

DEVICE="/dev/v4l/by-id/usb-Elgato_Elgato_Facecam_FW36L1A08484-video-index0"
DEVICE_SERIAL="FW36L1A08484"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/camera"

log() { printf '%s\n' "$*" >&2; }

ctrl_line() {
	local ctrl="$1"
	v4l2-ctl -d "$DEVICE" --list-ctrls 2>/dev/null | awk -v c="$ctrl" '$1==c {print; exit}'
}

ctrl_is_writable_active() {
	local ctrl="$1"
	local line
	line="$(ctrl_line "$ctrl" || true)"
	[[ -n "$line" ]] || return 1
	[[ "$line" == *"flags=inactive"* ]] && return 1
	[[ "$line" == *"flags=read-only"* ]] && return 1
	return 0
}

get_ctrl() {
	local ctrl="$1"
	v4l2-ctl -d "$DEVICE" --get-ctrl="$ctrl" 2>/dev/null | awk '{print $NF}'
}

wake_camera() {
	v4l2-ctl -d "$DEVICE" \
		--set-fmt-video=width=1280,height=720,pixelformat=MJPG \
		--stream-mmap --stream-count=1 --stream-to=/dev/null \
		>/dev/null 2>&1 || true
}

set_ctrl() {
	local ctrl="$1" value="$2"

	if v4l2-ctl -d "$DEVICE" --set-ctrl "$ctrl=$value" >/dev/null 2>&1; then
		return 0
	fi

	case "$ctrl" in
	exposure_time_absolute)
		v4l2-ctl -d "$DEVICE" --set-ctrl auto_exposure=1 >/dev/null 2>&1 || true
		v4l2-ctl -d "$DEVICE" --set-ctrl exposure_auto=1 >/dev/null 2>&1 || true
		v4l2-ctl -d "$DEVICE" --set-ctrl exposure_auto_priority=0 >/dev/null 2>&1 || true
		v4l2-ctl -d "$DEVICE" --set-ctrl "$ctrl=$value" >/dev/null 2>&1 && return 0
		;;
	white_balance_temperature)
		v4l2-ctl -d "$DEVICE" --set-ctrl white_balance_automatic=0 >/dev/null 2>&1 || true
		v4l2-ctl -d "$DEVICE" --set-ctrl white_balance_temperature_auto=0 >/dev/null 2>&1 || true
		v4l2-ctl -d "$DEVICE" --set-ctrl "$ctrl=$value" >/dev/null 2>&1 && return 0
		;;
	esac

	return 1
}

save_settings() {
	local settings_name="$1"
	local full_path="$STATE_DIR/$settings_name"

	mkdir -p "$STATE_DIR"

	v4l2-ctl -d "$DEVICE" --list-ctrls | awk '
    {
      ctrl=$1
      if (match($0, /value=[^ ]+/)) {
        val=substr($0, RSTART+6, RLENGTH-6)
        print ctrl "=" val
      }
    }
  ' | while IFS='=' read -r ctrl val; do
		local line
		line="$(ctrl_line "$ctrl" || true)"
		[[ -n "$line" ]] || continue
		[[ "$line" == *"flags=inactive"* ]] && continue
		[[ "$line" == *"flags=read-only"* ]] && continue
		printf '%s=%s\n' "$ctrl" "$val"
	done >"$full_path"

	log "Settings saved to $full_path"
}

restore_settings() {
	local settings_name="$1"
	local full_path="$STATE_DIR/$settings_name"
	local -a failed=()
	declare -A cfg=()

	[[ -f "$full_path" ]] || {
		log "Settings file not found: $settings_name"
		exit 1
	}

	while IFS='=' read -r ctrl val; do
		[[ -n "${ctrl:-}" ]] || continue
		cfg["$ctrl"]="$val"
	done <"$full_path"

	wake_camera

	for ctrl in auto_exposure exposure_auto exposure_auto_priority white_balance_automatic white_balance_temperature_auto focus_auto; do
		if [[ -n "${cfg[$ctrl]:-}" ]] && ctrl_is_writable_active "$ctrl"; then
			set_ctrl "$ctrl" "${cfg[$ctrl]}" >/dev/null 2>&1 || true
		fi
	done

	for ctrl in "${!cfg[@]}"; do
		case "$ctrl" in
		auto_exposure | exposure_auto | exposure_auto_priority | white_balance_automatic | white_balance_temperature_auto | focus_auto) continue ;;
		esac
		ctrl_is_writable_active "$ctrl" || continue
		set_ctrl "$ctrl" "${cfg[$ctrl]}" || failed+=("$ctrl")
	done

	if ((${#failed[@]} > 0)); then
		wake_camera
		local -a still_failed=()
		for ctrl in "${failed[@]}"; do
			ctrl_is_writable_active "$ctrl" || continue
			set_ctrl "$ctrl" "${cfg[$ctrl]}" || still_failed+=("$ctrl")
		done
		failed=("${still_failed[@]}")
	fi

	log "Settings restored from $full_path"

	if ((${#failed[@]} > 0)); then
		log "Warning: Failed to set the following controls:"
		printf '  - %s\n' "${failed[@]}" >&2
	fi
}

remove_settings() {
	local settings_name="$1"
	local full_path="$STATE_DIR/$settings_name"
	[[ -f "$full_path" ]] || {
		log "Settings file not found: $settings_name"
		exit 1
	}
	rm -f "$full_path"
	log "Removed profile: $settings_name"
}

set_or_get_control() {
	local control="$1"
	local value="${2:-}"

	if [[ -z "$value" ]]; then
		local current_value control_line min_value max_value
		current_value="$(get_ctrl "$control" || true)"
		log "Value: ${current_value:-<unavailable>}"
		control_line="$(ctrl_line "$control" || true)"
		[[ -n "$control_line" ]] || {
			log "Control not found: $control"
			exit 1
		}
		min_value="$(sed -n 's/.*min=\([^ ]*\).*/\1/p' <<<"$control_line")"
		max_value="$(sed -n 's/.*max=\([^ ]*\).*/\1/p' <<<"$control_line")"
		log "Min: $min_value"
		log "Max: $max_value"
	else
		wake_camera
		ctrl_is_writable_active "$control" || {
			log "Control not writable/active right now: $control"
			exit 1
		}
		set_ctrl "$control" "$value" || {
			log "Failed to set $control=$value"
			exit 1
		}
	fi
}

list_saves() {
	[[ -d "$STATE_DIR" ]] || {
		log "No saved profiles found."
		exit 0
	}
	local saves
	saves="$(ls -1 "$STATE_DIR" 2>/dev/null || true)"
	[[ -n "$saves" ]] && {
		log "Saved profiles:"
		printf '%s\n' "$saves"
	} || log "No saved profiles found."
}

list_controls() {
	v4l2-ctl -d "$DEVICE" --list-ctrls
}

command="${1:-}"

case "$command" in
save)
	[[ -n "${2:-}" ]] || {
		log "Usage: cam save <profile_name>"
		exit 1
	}
	save_settings "$2"
	;;
restore)
	[[ -n "${2:-}" ]] || {
		log "Usage: cam restore <profile_name>"
		exit 1
	}
	restore_settings "$2"
	;;
remove | rm | delete)
	[[ -n "${2:-}" ]] || {
		log "Usage: cam remove <profile_name>"
		exit 1
	}
	remove_settings "$2"
	;;
list | ls | saves)
	list_saves
	;;
reset)
	sudo usbreset SN:"${DEVICE_SERIAL}"
	;;
"")
	list_controls
	;;
*)
	set_or_get_control "$command" "${2:-}"
	;;
esac
