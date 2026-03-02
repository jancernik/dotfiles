#!/usr/bin/env bash

# Locks focus to vicinae while it is open. Closes it when clicking outside.

set -u

VICINAE_CLASS="${VICINAE_CLASS:-vicinae}"
DEFAULT_FOLLOW_MOUSE="${DEFAULT_FOLLOW_MOUSE:-1}"
DEFAULT_MOUSE_REFOCUS="${DEFAULT_MOUSE_REFOCUS:-1}"

EVENT_SOCKET="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
[[ -S "$EVENT_SOCKET" ]] || EVENT_SOCKET="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/socket2.sock"

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

lock_focus() {
	hyprctl --batch \
		"keyword input:follow_mouse 0; keyword input:mouse_refocus 0" \
		>/dev/null 2>&1 || true
}

unlock_focus() {
	hyprctl --batch \
		"keyword input:follow_mouse $DEFAULT_FOLLOW_MOUSE; keyword input:mouse_refocus $DEFAULT_MOUSE_REFOCUS" \
		>/dev/null 2>&1 || true
}

close_all_vicinae_windows() {
	local window_address
	for window_address in "${!open_vicinae_windows[@]}"; do
		hyprctl dispatch closewindow "address:$window_address" >/dev/null 2>&1 || true
	done
}

declare -A open_vicinae_windows=()

sync_initial_state() {
	if ! command -v jq >/dev/null 2>&1; then
		unlock_focus
		return 0
	fi

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

if [[ ! -S "$EVENT_SOCKET" ]]; then
	printf 'focus-guard: socket not found: %s\n' "$EVENT_SOCKET" >&2
	exit 1
fi

sync_initial_state

socat -u "UNIX-CONNECT:$EVENT_SOCKET" - 2>/dev/null |
	while IFS= read -r event_line; do
		case "${event_line%%>>*}" in
		openwindow)
			event_payload="${event_line#openwindow>>}"
			window_info="$(parse_openwindow_payload "$event_payload")"
			window_address="$(cut -f1 <<<"$window_info")"
			window_class="$(cut -f2 <<<"$window_info")"
			[[ -n "${window_address:-}" && -n "${window_class:-}" ]] || continue
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
				close_all_vicinae_windows
				open_vicinae_windows=()
				unlock_focus
			fi
			;;
		esac
	done
