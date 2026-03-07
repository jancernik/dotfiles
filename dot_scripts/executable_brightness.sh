#!/usr/bin/env bash

# Manage monitor brightness via a daemon.

set -euo pipefail

usage() {
	printf 'Usage: %s [-m N] [0..100|+N|-N|save|restore|dim|daemon]\n' "$0" >&2
	exit 1
}

PIPE="${XDG_RUNTIME_DIR:-/run/user/$UID}/brightness.pipe"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
SAVE_FILE="$STATE_DIR/brightness"
CURRENT_FILE="$STATE_DIR/brightness.current"

BACKLIGHT_MIN=12 # raw units (0..400), the built-in display looks bad below this value

monitor_index=""
backend=""

if [[ "${1:-}" == "-m" ]]; then
	[[ -n "${2:-}" ]] || {
		printf 'Option -m requires an argument\n' >&2
		usage
	}
	monitor_index="$2"
	shift 2
elif [[ "${1:-}" == -m[0-9]* ]]; then
	monitor_index="${1#-m}"
	shift
elif [[ "${1:-}" == -[^0-9]* ]]; then
	printf 'Unknown option: %s\n' "$1" >&2
	usage
fi

action="${1:-}"

detect_backend() {
	if command -v brightnessctl >/dev/null 2>&1 &&
		[[ -n "$(ls /sys/class/backlight/ 2>/dev/null)" ]]; then
		backend="brightnessctl"
	elif command -v ddcutil >/dev/null 2>&1; then
		backend="ddcutil"
	else
		printf 'No backend found. Requires brightnessctl or ddcutil\n' >&2
		exit 1
	fi
}

list_devices() {
	case "$backend" in
	brightnessctl) ls /sys/class/backlight/ 2>/dev/null ;;
	ddcutil)
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
		;;
	esac
}

get_brightness() {
	case "$backend" in
	brightnessctl)
		local current_raw=50 max_raw=100
		[[ -r "/sys/class/backlight/$1/brightness" ]] && current_raw=$(<"/sys/class/backlight/$1/brightness")
		[[ -r "/sys/class/backlight/$1/max_brightness" ]] && max_raw=$(<"/sys/class/backlight/$1/max_brightness")
		local brightness_span=$((max_raw - BACKLIGHT_MIN))
		local clamped=$((current_raw < BACKLIGHT_MIN ? BACKLIGHT_MIN : current_raw > max_raw ? max_raw : current_raw))
		printf '%d' "$((brightness_span > 0 ? (clamped - BACKLIGHT_MIN) * 100 / brightness_span : 50))"
		;;
	ddcutil)
		ddcutil --bus "$1" getvcp 0x10 --terse 2>/dev/null | awk '{print $4}'
		;;
	esac
}

set_brightness() {
	case "$backend" in
	brightnessctl)
		local device="$1" percent="$2" max_raw=100
		[[ -r "/sys/class/backlight/$device/max_brightness" ]] && max_raw=$(<"/sys/class/backlight/$device/max_brightness")
		local raw_value=$((BACKLIGHT_MIN + percent * (max_raw - BACKLIGHT_MIN) / 100))
		brightnessctl -d "$device" set "$raw_value" >/dev/null 2>&1
		;;
	ddcutil)
		local device="$1" target_level="$2"
		sleep "$(awk -v r="$RANDOM" 'BEGIN{printf "%.3f", (r % 40) / 1000.0}')"
		ddcutil --bus "$device" --noverify --sleep-multiplier=0.6 setvcp 0x10 "$target_level" >/dev/null 2>&1 ||
			{
				sleep 0.2
				ddcutil --bus "$device" --sleep-multiplier=1.0 setvcp 0x10 "$target_level" >/dev/null 2>&1
			}
		;;
	esac
}

declare -a _devices=()
declare -a _brightness_levels=()
declare -A _pending_changes=()

clamp() { printf '%d' "$(($1 < 0 ? 0 : $1 > 100 ? 100 : $1))"; }

resolve() {
	local index="$1"
	if [[ -v "_pending_changes[$index]" ]]; then
		printf '%s' "${_pending_changes[$index]}"
	elif [[ -v "_pending_changes[all]" ]]; then
		printf '%s' "${_pending_changes[all]}"
	else
		printf '%s' "${_brightness_levels[$index]:-50}"
	fi
}

write_current() {
	local i
	for i in "${!_devices[@]}"; do
		printf '%s\n' "${_brightness_levels[$i]}"
	done >"$CURRENT_FILE"
}

write_preview() {
	local i
	for i in "${!_devices[@]}"; do
		printf '%s\n' "$(resolve "$i")"
	done >"$CURRENT_FILE"
}

flush_pending() {
	[[ ${#_pending_changes[@]} -eq 0 ]] && return
	local target_key job_pids=()
	if [[ -v "_pending_changes[all]" ]]; then
		local target_level="${_pending_changes[all]}" i
		for i in "${!_devices[@]}"; do
			_brightness_levels[$i]="$target_level"
			set_brightness "${_devices[$i]}" "$target_level" &
			job_pids+=("$!")
		done
	else
		for target_key in "${!_pending_changes[@]}"; do
			_brightness_levels[$target_key]="${_pending_changes[$target_key]}"
			set_brightness "${_devices[$target_key]}" "${_pending_changes[$target_key]}" &
			job_pids+=("$!")
		done
	fi
	for pid in "${job_pids[@]}"; do wait "$pid"; done
	_pending_changes=()
}

daemon_mode() {
	detect_backend
	mapfile -t _devices < <(list_devices)
	[[ ${#_devices[@]} -gt 0 ]] || {
		printf 'No displays found\n' >&2
		exit 1
	}

	mkfifo "$PIPE" 2>/dev/null || true
	trap 'rm -f "$PIPE"' EXIT

	exec 3<>"$PIPE"

	local device
	for device in "${_devices[@]}"; do
		_brightness_levels+=("$(get_brightness "$device")")
	done
	write_current

	printf 'Daemon started (pipe: %s)\n' "$PIPE"

	local debounce_seconds
	[[ "$backend" == "brightnessctl" ]] && debounce_seconds=0.01 || debounce_seconds=0.1

	local message="" target_key="" value="" operator="" base_level=0 next_level=0 adjustment=0 i=0 job_pids=()
	while true; do
		if read -t "$debounce_seconds" -r message <&3; then
			case "$message" in
			save)
				flush_pending
				mkdir -p "$STATE_DIR"
				: >"$SAVE_FILE"
				for i in "${!_devices[@]}"; do
					printf '%s:%s\n' "${_devices[$i]}" "${_brightness_levels[$i]}" >>"$SAVE_FILE"
				done
				;;
			restore)
				flush_pending
				[[ -f "$SAVE_FILE" ]] || continue
				job_pids=()
				i=0
				while IFS=: read -r device value; do
					[[ -n "$device" && -n "$value" ]] || continue
					_brightness_levels[$i]="$value"
					set_brightness "$device" "$value" &
					job_pids+=("$!")
					i=$((i + 1))
				done <"$SAVE_FILE"
				write_current
				for pid in "${job_pids[@]}"; do wait "$pid"; done
				;;
			*)
				if [[ "$message" == *:* ]]; then
					target_key="${message%%:*}"
					value="${message#*:}"
					[[ -n "$target_key" ]] || continue
				else
					target_key="all"
					value="$message"
				fi
				if [[ "$value" == [+-]* ]]; then
					operator="${value:0:1}"
					adjustment="${value:1}"
					if [[ "$target_key" == "all" ]]; then
						for i in "${!_devices[@]}"; do
							base_level=$(resolve "$i")
							if [[ "$operator" == "+" ]]; then
								next_level=$((base_level + adjustment))
							else
								next_level=$((base_level - adjustment))
							fi
							_pending_changes[$i]=$(clamp "$next_level")
						done
						unset '_pending_changes[all]'
					else
						base_level=$(resolve "$target_key")
						if [[ "$operator" == "+" ]]; then
							next_level=$((base_level + adjustment))
						else
							next_level=$((base_level - adjustment))
						fi
						_pending_changes[$target_key]=$(clamp "$next_level")
					fi
				else
					_pending_changes[$target_key]="$value"
				fi
				write_preview
				;;
			esac
		elif [[ ${#_pending_changes[@]} -gt 0 ]]; then
			flush_pending
		fi
	done
}

preview_current() {
	[[ -f "$CURRENT_FILE" ]] || return
	local value="$1" i new_level current_level
	mapfile -t preview_lines < "$CURRENT_FILE"
	for i in "${!preview_lines[@]}"; do
		[[ -n "$monitor_index" && "$i" != "$monitor_index" ]] && continue
		current_level="${preview_lines[$i]}"
		if [[ "$value" == [+-]* ]]; then
			local operator="${value:0:1}" adjustment="${value:1}"
			[[ "$operator" == "+" ]] && new_level=$((current_level + adjustment)) || new_level=$((current_level - adjustment))
			new_level=$(clamp "$new_level")
		else
			new_level="$value"
		fi
		preview_lines[$i]="$new_level"
	done
	printf '%s\n' "${preview_lines[@]}" >"$CURRENT_FILE"
}

send_to_daemon() {
	[[ -p "$PIPE" ]] || {
		printf 'Daemon not running\n' >&2
		exit 1
	}
	printf '%s\n' "$1" >"$PIPE"
}

case "$action" in
daemon)
	daemon_mode
	;;
save | s)
	send_to_daemon "save"
	;;
restore | r)
	touch "$STATE_DIR/brightness.silent"
	send_to_daemon "restore"
	(sleep 1; rm -f "$STATE_DIR/brightness.silent") &
	;;
dim)
	touch "$STATE_DIR/brightness.silent"
	preview_current "0"
	send_to_daemon "${monitor_index:+${monitor_index}:}0"
	(sleep 1; rm -f "$STATE_DIR/brightness.silent") &
	;;
+* | -*)
	[[ "$action" =~ ^[+-][0-9]{1,3}$ && ${action:1} -le 100 ]] || usage
	preview_current "$action"
	send_to_daemon "${monitor_index:+${monitor_index}:}${action}"
	;;
[0-9]*)
	[[ "$action" =~ ^[0-9]{1,3}$ && $action -le 100 ]] || usage
	preview_current "$action"
	send_to_daemon "${monitor_index:+${monitor_index}:}${action}"
	;;
*)
	usage
	;;
esac
