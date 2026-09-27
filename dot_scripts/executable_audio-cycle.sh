#!/usr/bin/env bash

# Cycle the PipeWire default sink or source.

set -euo pipefail

usage() {
    printf 'Usage: %s [output|sink|input|source] [list]\n' "$0" >&2
    exit 2
}

kind="${1:-}"
mode="${2:-}"
case "$kind" in
    output | sink) class="Audio/Sink" ;;
    input | source) class="Audio/Source" ;;
    *) usage ;;
esac
case "$mode" in
    "" | list) ;;
    *) usage ;;
esac

command -v jq >/dev/null 2>&1 || exit 0
dump="$(pw-dump 2>/dev/null)" || exit 0
rows="$(jq -r --arg class "$class" '
    [.[] | select(.type == "PipeWire:Interface:Node")
        | .id as $id | (.info.props // {}) as $props
        | select(($id | type) == "number"
            and $props["media.class"] == $class
            and ($props["node.name"] | type) == "string"
            and $props["node.name"] != "")
        | {id: $id, name: $props["node.name"]}]
    | sort_by(.name, .id)[] | [.id, .name] | @tsv
' <<<"$dump" 2>/dev/null)" || exit 0
devices=()
if [[ -n "$rows" ]]; then
    mapfile -t devices <<<"$rows"
fi

if [[ "$mode" == "list" ]]; then
    ((${#devices[@]})) && printf '%s\n' "${devices[@]}"
    exit 0
fi
((${#devices[@]} > 1)) || exit 0

placeholder="@DEFAULT_AUDIO_SINK@"
[[ "$class" == "Audio/Source" ]] && placeholder="@DEFAULT_AUDIO_SOURCE@"
info="$(wpctl inspect "$placeholder" 2>/dev/null)" || exit 0
[[ "$info" =~ ^id[[:space:]]+([0-9]+),[[:space:]]type[[:space:]]PipeWire:Interface:Node ]] || exit 0
current="${BASH_REMATCH[1]}"

index=-1
for i in "${!devices[@]}"; do
    [[ "${devices[$i]%%$'\t'*}" == "$current" ]] && index="$i" && break
done
[[ "$index" -ge 0 ]] || exit 0

next="${devices[$(((index + 1) % ${#devices[@]}))]}"
exec wpctl set-default "${next%%$'\t'*}"
