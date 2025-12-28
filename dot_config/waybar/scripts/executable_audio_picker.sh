#!/usr/bin/env bash
set -euo pipefail

get_default_node_id() {
	local default_key="$1"
	local media_class="$2"

	pw-dump | jq -r --arg default_key "$default_key" --arg media_class "$media_class" '
    . as $root
    | ([
        $root[]
        | select(.type == "PipeWire:Interface:Metadata")
        | .metadata[]?
        | select(.key == $default_key)
        | .value.name?
      ] | .[0] // empty) as $def_name
    | if ($def_name == "" ) then empty else
        ($root[]
          | select(.type == "PipeWire:Interface:Node")
          | select(.info.props["media.class"] == $media_class)
          | select(.info.props["node.name"] == $def_name)
          | .id)
      end
  ' | head -n1
}

list_nodes() {
	local media_class="$1"

	pw-dump | jq -r --arg media_class "$media_class" '
    .[]
    | select(.type == "PipeWire:Interface:Node")
    | select(.info.props["media.class"] == $media_class)
    | [
        (.id|tostring),
        (.info.props["node.name"] // ""),
        (.info.props["node.description"]
         // .info.props["node.nick"]
         // .info.props["node.name"]
         // "unknown")
      ]
    | @tsv
  '
}

case "${1-}" in
-i | --input | --source) mode="source" ;;
-o | --output | --sink) mode="sink" ;;
-h | --help)
	echo "usage: ${0##*/} [--output|--input]"
	exit 0
	;;
*)
	echo "usage: ${0##*/} [--output|--input]" >&2
	exit 2
	;;
esac

if [[ "$mode" == "sink" ]]; then
	default_key="default.audio.sink"
	media_class="Audio/Sink"
else
	default_key="default.audio.source"
	media_class="Audio/Source"
fi

default_node_id="$(get_default_node_id "$default_key" "$media_class" || true)"
node_ids=()
node_names=()

while IFS=$'\t' read -r id _node_name label; do
	node_ids+=("$id")
	node_names+=("$label")
done < <(list_nodes "$media_class")

default_index=""
for i in "${!node_ids[@]}"; do
	if [[ "${node_ids[$i]}" == "$default_node_id" ]]; then
		default_index="$i"
		break
	fi
done

menu_input="$(
	for i in "${!node_ids[@]}"; do
		printf '%s\t%s\n' "${node_ids[$i]}" "${node_names[$i]}"
	done
)"

chosen_id="$(
	printf '%s' "$menu_input" |
		fuzzel --dmenu -a top --minimal-lines --hide-prompt \
			--with-nth=2 --accept-nth=1 \
			${default_index:+--select-index="$default_index"}
)"

[[ -n "${chosen_id:-}" ]] && wpctl set-default "$chosen_id"
