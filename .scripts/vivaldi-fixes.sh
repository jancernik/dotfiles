#!/usr/bin/env bash

# Autofocus Vivaldi's URL bar on "New Tab" windows

set -u
IFS=$' \t\n'
shopt -s extglob

TARGET_CLASS="${TARGET_CLASS:-vivaldi-stable}"
TARGET_TITLE="${TARGET_TITLE:-New Tab - Vivaldi}"
SETTLE_AFTER_ACTIVE="${SETTLE_AFTER_ACTIVE:-0.25}"
BACKSPACES="${BACKSPACES:-1}"

SOCK="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

normalize_addr() {
  local a="$1"
  [[ "$a" == 0x* ]] && { printf '%s\n' "$a"; return; }
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
    addr="${payload%%,*}"; rest="${payload#*,}"
    rest="${rest#*,}";     cls="${rest%%,*}"
    title="${rest#*,}"
    printf '%s\t%s\t%s\n' "$addr" "$cls" "$title"
  fi
}

parse_windowtitlev2() {
  local payload="$1"
  local addr title
  addr="${payload%%,*}"
  title="${payload#*,}"
  printf '%s\t%s\n' "$addr" "$title"
}

focus_urlbar() {
  local addr="$1"
  hyprctl dispatch sendshortcut CTRL,L,address:"$addr"   >/dev/null 2>&1 && return 0
  hyprctl dispatch sendshortcut ,F6,address:"$addr"      >/dev/null 2>&1 && return 0
  hyprctl dispatch sendshortcut ALT,D,address:"$addr"    >/dev/null 2>&1 && return 0
  hyprctl dispatch sendshortcut CTRL,code:46,address:"$addr" >/dev/null 2>&1 && return 0
  return 1
}

send_backspaces() {
  local addr="$1"
  local i
  for ((i=0; i<BACKSPACES; i++)); do
    hyprctl dispatch sendshortcut ,BackSpace,address:"$addr" >/dev/null 2>&1 \
      || hyprctl dispatch sendshortcut ,code:14,address:"$addr" >/dev/null 2>&1 || true
  done
}

declare -A PENDING=()
declare -A TITLEOK=()
ACTIVE_ADDR=""

maybe_fire() {
  local addr="$1"
  [[ -n "${PENDING[$addr]:-}" && -n "${TITLEOK[$addr]:-}" ]] || return 0
  sleep "$SETTLE_AFTER_ACTIVE"
  if focus_urlbar "$addr"; then
    sleep 0.05
    send_backspaces "$addr"
    unset PENDING["$addr"] TITLEOK["$addr"]
  fi
}

socat -u "UNIX-CONNECT:$SOCK" - 2>/dev/null \
| while IFS= read -r line; do
    case "${line%%>>*}" in
      openwindow)
        payload="${line#openwindow>>}"
        parsed="$(parse_openwindow "$payload" 2>/dev/null || true)"
        addr="$(cut -f1 <<<"$parsed")"
        cls="$(cut  -f2 <<<"$parsed")"
        title="$(cut -f3- <<<"$parsed")"
        [[ -n "${addr:-}" && -n "${cls:-}" && "$cls" == "$TARGET_CLASS" ]] || continue
        addr="$(normalize_addr "$addr")"
        PENDING["$addr"]=1
        [[ "$title" == "$TARGET_TITLE" ]] && TITLEOK["$addr"]=1
        ;;
      windowtitlev2)
        payload="${line#windowtitlev2>>}"
        wt="$(parse_windowtitlev2 "$payload")"
        waddr="$(normalize_addr "$(cut -f1 <<<"$wt")")"
        wtitle="$(cut -f2- <<<"$wt")"
        [[ "$wtitle" == "$TARGET_TITLE" ]] && TITLEOK["$waddr"]=1
        [[ "$ACTIVE_ADDR" == "$waddr" ]] && maybe_fire "$waddr"
        ;;
      activewindowv2)
        raw="${line#activewindowv2>>}"
        ACTIVE_ADDR="$(normalize_addr "$raw")"
        maybe_fire "$ACTIVE_ADDR"
        ;;
    esac
  done
