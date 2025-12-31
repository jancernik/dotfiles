#!/usr/bin/env bash

set -u
IFS=$' \t\n'
shopt -s extglob

VIC_CLASS="${VIC_CLASS:-vicinae}"
WOFI_CLASS="${WOFI_CLASS:-wofi}"
WOFI_CMD="${WOFI_CMD:-wofi}"

SOCK="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

normalize_addr() {
	local a="$1"
	[[ "$a" == 0x* ]] && {
		printf '%s\n' "$a"
		return
	}
	printf '0x%s\n' "$a"
}

parse_openwindow() {
	local payload="$1"
	if [[ "$payload" == *:* ]]; then
		local addr cls title
		addr="$(sed -n 's/.*address:\([^,]*\).*/\1/p' <<<"$payload")"
		cls="$(sed -n 's/.*class:\([^,]*\).*/\1/p'   <<<"$payload")"
		title="$(sed -n 's/.*title:\([^,]*\).*/\1/p' <<<"$payload")"
		printf '%s\t%s\t%s\n' "$addr" "$cls" "$title"
	else
		local addr rest cls title
		addr="${payload%%,*}"
		rest="${payload#*,}"
		rest="${rest#*,}"
		cls="${rest%%,*}"
		title="${rest#*,}"
		printf '%s\t%s\t%s\n' "$addr" "$cls" "$title"
	fi
}

get_follow_mouse() {
	hyprctl getoption input:follow_mouse 2>/dev/null |
		awk -F': *' '$1=="int"{print $2; exit}'
}

set_follow_mouse() {
	hyprctl keyword input:follow_mouse "$1" >/dev/null 2>&1 || true
}

kill_wofi() {
	pkill -x "$WOFI_CMD" >/dev/null 2>&1 && return 0
	killall "$WOFI_CMD" >/dev/null 2>&1 || true
}

declare -A VIC_ADDRS=()
declare -A WOFI_ADDRS=()
SAVED_FOLLOW_MOUSE=""
LAST_ACTIVE_CLASS=""

update_follow_mouse() {
	if ((${#VIC_ADDRS[@]} > 0 || ${#WOFI_ADDRS[@]} > 0)); then
		[[ -n "$SAVED_FOLLOW_MOUSE" ]] || SAVED_FOLLOW_MOUSE="$(get_follow_mouse || true)"
		set_follow_mouse 0
	else
		[[ -n "$SAVED_FOLLOW_MOUSE" ]] || return 0
		set_follow_mouse "$SAVED_FOLLOW_MOUSE"
		SAVED_FOLLOW_MOUSE=""
	fi
}

initial_sync() {
	command -v jq >/dev/null 2>&1 || {
		update_follow_mouse
		return 0
	}

	while IFS= read -r addr; do
		addr="$(normalize_addr "$addr")"
		VIC_ADDRS["$addr"]=1
	done < <(
		hyprctl clients -j 2>/dev/null |
			jq -r --arg c "$VIC_CLASS" '.[] | select(.class==$c) | .address'
	)

	while IFS= read -r addr; do
		addr="$(normalize_addr "$addr")"
		WOFI_ADDRS["$addr"]=1
	done < <(
		hyprctl clients -j 2>/dev/null |
			jq -r --arg c "$WOFI_CLASS" '.[] | select(.class==$c) | .address'
	)

	update_follow_mouse
}

initial_sync

socat -u "UNIX-CONNECT:$SOCK" - 2>/dev/null |
	while IFS= read -r line; do
		case "${line%%>>*}" in
		openwindow)
			payload="${line#openwindow>>}"
			parsed="$(parse_openwindow "$payload" 2>/dev/null || true)"
			addr="$(cut -f1 <<<"$parsed")"
			cls="$(cut -f2 <<<"$parsed")"
			[[ -n "${addr:-}" && -n "${cls:-}" ]] || continue
			addr="$(normalize_addr "$addr")"
			if [[ "$cls" == "$VIC_CLASS" ]]; then
				VIC_ADDRS["$addr"]=1
				update_follow_mouse
			elif [[ "$cls" == "$WOFI_CLASS" ]]; then
				WOFI_ADDRS["$addr"]=1
				update_follow_mouse
			fi
			;;
		closewindow)
			payload="${line#closewindow>>}"
			addr="$(normalize_addr "${payload%%,*}")"
			unset "VIC_ADDRS[$addr]" 2>/dev/null || true
			unset "WOFI_ADDRS[$addr]" 2>/dev/null || true
			update_follow_mouse
			;;
		activewindow)
			payload="${line#activewindow>>}"
			new_class="${payload%%,*}"
			if [[ "$LAST_ACTIVE_CLASS" == "$WOFI_CLASS" && "$new_class" != "$WOFI_CLASS" ]]; then
				((${#WOFI_ADDRS[@]} > 0)) && kill_wofi
			fi
			LAST_ACTIVE_CLASS="$new_class"
			;;
		esac
	done
