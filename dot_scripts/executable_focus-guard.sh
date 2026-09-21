#!/usr/bin/env bash

# Locks focus to vicinae while it is open. Closes it when clicking outside.

set -u

VICINAE_CLASS="${VICINAE_CLASS:-vicinae}"
DEFAULT_FOLLOW_MOUSE="${DEFAULT_FOLLOW_MOUSE:-1}"

EVENT_SOCKET="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
[[ -S "$EVENT_SOCKET" ]] || EVENT_SOCKET="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/socket2.sock"

LOCK_FILE="$XDG_RUNTIME_DIR/focus-guard.lock"

declare -A open_vicinae_windows=()
focus_locked=0

require_command() {
	if ! command -v "$1" >/dev/null 2>&1; then
		printf 'focus-guard: missing dependency: %s\n' "$1" >&2
		exit 1
	fi
}

normalize_address() {
	local address="$1"
	[[ "$address" == 0x* ]] && { printf '%s\n' "$address"; return; }
	printf '0x%s\n' "$address"
}

parse_openwindow_payload() {
	local payload="$1" remaining
	local window_address="${payload%%,*}"
	remaining="${payload#*,}"
	remaining="${remaining#*,}"
	local window_class="${remaining%%,*}"
	printf '%s\t%s\n' "$window_address" "$window_class"
}

set_follow_mouse() {
	local value="$1" output
	if ! output="$(hyprctl eval "hl.config({ input = { follow_mouse = $value } })" 2>&1)"; then
		printf 'focus-guard: follow_mouse=%s failed: %s\n' "$value" "$output" >&2
	fi
}

lock_focus() {
	if ((focus_locked == 0)); then
		focus_locked=1
		set_follow_mouse 0
	fi
}

unlock_focus() {
	focus_locked=0
	set_follow_mouse "$DEFAULT_FOLLOW_MOUSE"
}

close_vicinae() {
	vicinae close >/dev/null 2>&1 || true
	open_vicinae_windows=()
	unlock_focus
}

sync_initial_state() {
	local window_address
	while IFS= read -r window_address; do
		window_address="$(normalize_address "$window_address")"
		open_vicinae_windows["$window_address"]=1
	done < <(
		hyprctl clients -j 2>/dev/null |
			jq -r --arg class "$VICINAE_CLASS" '.[] | select(.class == $class) | .address'
	)

	if ((${#open_vicinae_windows[@]} > 0)); then
		lock_focus
	else
		unlock_focus
	fi
}

require_command hyprctl
require_command socat
require_command jq
require_command vicinae

if [[ ! "$DEFAULT_FOLLOW_MOUSE" =~ ^[0-3]$ ]]; then
	printf 'focus-guard: DEFAULT_FOLLOW_MOUSE must be 0-3, got: %s\n' "$DEFAULT_FOLLOW_MOUSE" >&2
	exit 1
fi

if [[ ! -S "$EVENT_SOCKET" ]]; then
	printf 'focus-guard: socket not found: %s\n' "$EVENT_SOCKET" >&2
	exit 1
fi

if ! exec 9>"$LOCK_FILE"; then
	printf 'focus-guard: cannot open lock file: %s\n' "$LOCK_FILE" >&2
	exit 1
fi

if ! flock -n 9; then
	printf 'focus-guard: already running\n' >&2
	exit 0
fi

trap 'unlock_focus' EXIT
trap 'exit 0' INT TERM HUP

sync_initial_state

while IFS= read -r event_line; do
	case "${event_line%%>>*}" in
	openwindow)
		event_payload="${event_line#openwindow>>}"
		window_info="$(parse_openwindow_payload "$event_payload")"
		IFS=$'\t' read -r window_address window_class <<<"$window_info"
		[[ -n "$window_address" && -n "$window_class" ]] || continue
		window_address="$(normalize_address "$window_address")"
		if [[ "$window_class" == "$VICINAE_CLASS" ]]; then
			open_vicinae_windows["$window_address"]=1
			lock_focus
		fi
		;;
	closewindow)
		event_payload="${event_line#closewindow>>}"
		window_address="$(normalize_address "${event_payload%%,*}")"
		if [[ -v open_vicinae_windows["$window_address"] ]]; then
			unset "open_vicinae_windows[$window_address]"
			if ((${#open_vicinae_windows[@]} == 0)); then
				unlock_focus
			fi
		fi
		;;
	activewindow)
		event_payload="${event_line#activewindow>>}"
		window_class="${event_payload%%,*}"
		if [[ -n "$window_class" \
			&& "$window_class" != "$VICINAE_CLASS" \
			&& ${#open_vicinae_windows[@]} -gt 0 ]]; then
			close_vicinae
		fi
		;;
	configreloaded)
		if ((focus_locked)); then
			set_follow_mouse 0
		fi
		;;
	esac
done < <(socat -u "UNIX-CONNECT:$EVENT_SOCKET" - 9>&-)
