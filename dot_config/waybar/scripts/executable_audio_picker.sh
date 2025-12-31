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

if [[ -n "$default_index" ]]; then
	new_ids=("${node_ids[$default_index]}")
	new_names=("${node_names[$default_index]}")
	for i in "${!node_ids[@]}"; do
		[[ "$i" == "$default_index" ]] && continue
		new_ids+=("${node_ids[$i]}")
		new_names+=("${node_names[$i]}")
	done
	node_ids=("${new_ids[@]}")
	node_names=("${new_names[@]}")
fi

menu_input="$(printf '%s\n' "${node_names[@]}")"
lines="${#node_names[@]}"

chosen_index="$(
	printf '%s' "$menu_input" |
		wofi --dmenu --normal-window \
			--width 320 \
			--lines "$lines" \
			--hide-scroll \
			--hide-search \
			--define 'dmenu-print_line_num=true' \
			--define 'single_click=true'
)"

if [[ -n "${chosen_index:-}" && "$chosen_index" =~ ^[0-9]+$ ]] && ((chosen_index < ${#node_ids[@]})); then
	wpctl set-default "${node_ids[$chosen_index]}"
fi
