#!/usr/bin/env bash

# Set follow_mouse to 2 while any Vicinae window exists, otherwise set to 1

set -u
IFS=$' \t\n'
shopt -s extglob

TARGET_CLASS="${TARGET_CLASS:-vicinae}"
FOLLOW_DEFAULT="${FOLLOW_DEFAULT:-1}"
FOLLOW_WITH_TARGET="${FOLLOW_WITH_TARGET:-2}"

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
		cls="$(sed -n 's/.*class:\([^,]*\).*/\1/p' <<<"$payload")"
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
	hyprctl getoption input:follow_mouse -j 2>/dev/null |
		sed -n 's/.*"int":[[:space:]]*\([0-9]\+\).*/\1/p' | head -n1
}

set_follow_mouse() {
	hyprctl keyword input:follow_mouse "$1" >/dev/null 2>&1 || true
}

declare -A TARGET_ADDRS=()

update_follow_mouse() {
	local desired current
	if ((${#TARGET_ADDRS[@]} > 0)); then
		desired="$FOLLOW_WITH_TARGET"
	else
		desired="$FOLLOW_DEFAULT"
	fi

	current="$(get_follow_mouse)"
	[[ -n "${current:-}" && "$current" == "$desired" ]] && return 0
	set_follow_mouse "$desired"
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
