#!/usr/bin/env bash

# Set follow_mouse to 2 while any Vicinae window exists, otherwise set to 1

set -u
IFS=$' \t\n'
shopt -s extglob

TARGET_CLASS="${TARGET_CLASS:-vicinae}"
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
		local addr cls
		addr="$(sed -n 's/.*address:\([^,]*\).*/\1/p' <<<"$payload")"
		cls="$(sed -n 's/.*class:\([^,]*\).*/\1/p' <<<"$payload")"
		printf '%s\t%s\n' "$addr" "$cls"
	else
		local addr rest cls
		addr="${payload%%,*}"
		rest="${payload#*,}"
		rest="${rest#*,}"
		cls="${rest%%,*}"
		printf '%s\t%s\n' "$addr" "$cls"
	fi
}

get_follow_mouse() {
	hyprctl getoption input:follow_mouse 2>/dev/null |
		awk -F': *' '$1=="int"{print $2; exit}'
}

set_follow_mouse() {
	hyprctl keyword input:follow_mouse "$1" >/dev/null 2>&1 || true
}

declare -A TARGET_ADDRS=()
SAVED_FOLLOW_MOUSE=""

update_follow_mouse() {
	if ((${#TARGET_ADDRS[@]} > 0)); then
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
		TARGET_ADDRS["$addr"]=1
	done < <(
		hyprctl clients -j 2>/dev/null |
			jq -r --arg c "$TARGET_CLASS" '.[] | select(.class==$c) | .address'
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
			[[ "$cls" == "$TARGET_CLASS" ]] || continue
			addr="$(normalize_addr "$addr")"
			TARGET_ADDRS["$addr"]=1
			update_follow_mouse
			;;
		closewindow)
			payload="${line#closewindow>>}"
			addr="$(normalize_addr "${payload%%,*}")"
			unset "TARGET_ADDRS[$addr]" 2>/dev/null || true
			update_follow_mouse
			;;
		esac
	done
